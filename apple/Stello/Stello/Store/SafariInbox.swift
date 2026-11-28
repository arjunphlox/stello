import Foundation
import SwiftData
import os

/// The app side of saving from Safari and the share sheet's canvas row (`SafariSaveInbox`).
///
/// Each waiting request is saved through the normal capture path (so the folder write,
/// web copy and enrichment work exactly as for any other save), then its items are placed
/// together on the chosen canvas. Requests are deleted once handled. Runs at launch, when
/// the app comes to the front, and at once on the Mac when Safari pokes the app's port.
@MainActor
final class SafariInbox {
    static let shared = SafariInbox()
    private static let log = Logger(subsystem: "com.arjunphlox.Stello", category: "SafariInbox")
    /// More than this many links in one save are not enriched now: they wait until opened.
    private static let enrichUpTo = 5

    private var context: ModelContext?
    private var coordinator: EnrichmentCoordinator?
    private var running = false
    private var again = false

    func start(context: ModelContext, coordinator: EnrichmentCoordinator) {
        guard !WebInboxProcessor.isDisabled, self.context == nil else { return }
        self.context = context
        self.coordinator = coordinator
        Task {
            await CanvasStore.shared.refreshList()
            await process()
        }
    }

    func processSoon() { Task { await process() } }

    func process() async {
        guard let context else { return }
        if running { again = true; return }
        running = true
        defer { running = false }
        repeat {
            again = false
            for (file, request) in SafariSaveInbox.pending() {
                await handle(request, context: context)
                SafariSaveInbox.remove(file)
            }
        } while again
    }

    private func handle(_ request: SafariSaveInbox.Request, context: ModelContext) async {
        let items = await save(request.entries, context: context)
        let enrich = items.count <= Self.enrichUpTo
        if enrich, let coordinator {
            for item in items where item.enrichmentStatus != "done" {
                coordinator.scheduleEnrichment(for: item, context: context)
            }
        }
        var placed: (id: String, name: String)?
        if let canvas = request.canvas, !items.isEmpty {
            let heights = Dictionary(items.map { ($0.slug, Self.cardHeight($0)) }, uniquingKeysWith: { a, _ in a })
            placed = await CanvasStore.shared.place(
                items.map(\.slug), in: canvas, newName: request.newName, groupName: request.groupName,
                height: { heights[$0] ?? (CanvasMetrics.cardWidth * 0.62).rounded() })
        }
        let canvasName = placed?.name
        let text: String
        switch (items.count, canvasName) {
        case (0, _): text = "Couldn't save"
        case (1, let name?): text = "Added to \(name)"
        case (let n, let name?): text = "Added \(n) to \(name)"
        case (1, nil): text = "Saved to Stello"
        case (let n, nil): text = "Saved \(n) to Stello"
        }
        SafariSaveInbox.markDone(request.id, text: text, canvas: placed?.id)
        Self.log.info("Safari save \(request.id, privacy: .public): \(text, privacy: .public)")
    }

    /// Web links or pictures dropped on the canvas from Safari or another app: saved the
    /// same way, returned for the canvas to place where they were dropped.
    func saveDropped(_ entries: [SafariSaveInbox.Entry], context: ModelContext) async -> [Item] {
        let items = await save(entries, context: context)
        if items.count <= Self.enrichUpTo, let coordinator = coordinator {
            for item in items where item.enrichmentStatus != "done" {
                coordinator.scheduleEnrichment(for: item, context: context)
            }
        }
        return items
    }

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "avif", "heic"]

    /// Saves each entry (four at a time), keeping their order. Already saved addresses
    /// return the item you have.
    private func save(_ entries: [SafariSaveInbox.Entry], context: ModelContext) async -> [Item] {
        var out = [Item?](repeating: nil, count: entries.count)
        var next = 0
        while next < entries.count {
            let batch = Array(next..<min(entries.count, next + 4))
            await withTaskGroup(of: (Int, Item?).self) { group in
                for i in batch {
                    let entry = entries[i]
                    group.addTask { @MainActor in (i, await Self.save(entry, context: context)) }
                }
                for await (i, item) in group { out[i] = item }
            }
            next += 4
        }
        var seen = Set<String>()
        return out.compactMap { $0 }.filter { seen.insert($0.slug).inserted }
    }

    private static func save(_ entry: SafariSaveInbox.Entry, context: ModelContext) async -> Item? {
        guard let url = URL(string: entry.url) else { return nil }
        do {
            if entry.kind == "image" { return try await saveImage(url, entry: entry, context: context) }
            return try await CaptureService.captureURL(url, context: context)
        } catch {
            log.error("Safari save failed for \(entry.url, privacy: .private): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// A picture from a page: its own item, titled after the page, opening the picture.
    private static func saveImage(_ url: URL, entry: SafariSaveInbox.Entry, context: ModelContext) async throws -> Item? {
        let address = CaptureService.normalizeURL(url)
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate<Item> { $0.sourceURL == address })
        if let existing = try? context.fetch(descriptor).first { return existing }
        guard let (data, _, _) = await CaptureService.downloadImage(url: url) else {
            // Not a picture we can fetch (signed-in, blocked): save the page instead.
            guard let page = entry.page.flatMap(URL.init(string:)) else { return nil }
            return try await CaptureService.captureURL(page, context: context)
        }
        let item = try CaptureService.captureImage(data, context: context)
        let page = entry.page.flatMap(URL.init(string:))
        let title = entry.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty { item.title = title }
        item.sourceURL = address
        item.domain = page.flatMap(CaptureService.domain(from:)) ?? CaptureService.domain(from: url)
        if let page { item.summary = "From \(page.absoluteString)" }
        item.updatedAt = .now
        try context.save()
        return item
    }

    static func cardHeight(_ item: Item) -> CGFloat {
        let img = item.coverImage
        return CanvasMetrics.cardHeight(imageWidth: img?.width, imageHeight: img?.height,
                                        hasImage: img != nil)
    }
}
