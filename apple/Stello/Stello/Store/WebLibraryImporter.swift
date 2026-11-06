import Foundation
import SwiftData

/// Imports the old web library (the one-time Supabase export, Nov 2026) into the
/// app's SwiftData + CloudKit store, which makes it the iCloud library the web
/// app now reads.
///
/// File shape: `{ image_base_url, items: [{ id, slug, title, source_url, domain, author,
/// summary, body_markdown, status, needs_review, added_at, analyzed_at, updated_at,
/// tags: [{ tag, category, weight }], images: [{ path, source, is_primary, width, height }],
/// snippets: [{ text, source, added_at }] }] }`
///
/// Items keep their ids, slugs and dates. They arrive as `link` items with their
/// tags (including `collection` labels); running Enrich on them afterwards
/// re-fetches each page and lets the classifier pick the kind, with the
/// collection labels breaking ties. Re-running the import skips items that
/// already exist (same id or source URL).
@Observable
@MainActor
final class WebLibraryImporter {
    static let shared = WebLibraryImporter()

    enum Phase: Equatable { case idle, importing, classifying, done, failed(String) }

    /// `enrichmentStatus` of an imported item still waiting for the background
    /// classify pass. Stored on the item, so the queue survives quits and syncs.
    nonisolated static let awaitingClassifyStatus = "awaiting_classify"
    /// Kind is settled; the item is still waiting for full Enrich (on-device AI).
    nonisolated static let awaitingAIStatus = "awaiting_ai"
    private static var isClassifyingPending = false

    private(set) var phase: Phase = .idle
    private(set) var total = 0
    private(set) var imported = 0
    private(set) var skipped = 0
    private(set) var classified = 0
    private var cancelled = false

    var isRunning: Bool { phase == .importing || phase == .classifying }

    var statusText: String {
        switch phase {
        case .idle: return ""
        case .importing: return "Importing \(imported + skipped) of \(total)…"
        case .classifying: return "Sorting into kinds: \(classified) of \(imported)…"
        case .done: return "Imported \(imported) items" + (skipped > 0 ? ", skipped \(skipped) already here" : "")
        case .failed(let message): return "Import failed: \(message)"
        }
    }

    func cancel() { cancelled = true }

    /// - Parameters:
    ///   - fileURL: the export JSON (security-scoped URLs from a file picker are handled).
    ///   - limit: import only the first N new items (pilot); nil = everything.
    ///   - classify: run Enrich on each imported item to fetch its page and set its kind.
    func run(
        fileURL: URL,
        context: ModelContext,
        coordinator: EnrichmentCoordinator,
        limit: Int? = nil,
        classify: Bool = true
    ) async {
        guard !isRunning else { return }
        cancelled = false
        imported = 0; skipped = 0; classified = 0; total = 0
        phase = .importing

        let export: Export
        do {
            let scoped = fileURL.startAccessingSecurityScopedResource()
            defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
            export = try JSONDecoder().decode(Export.self, from: Data(contentsOf: fileURL))
        } catch {
            phase = .failed("couldn't read the file (\(error.localizedDescription))")
            return
        }

        let baseURL = URL(string: export.imageBaseURL ?? "https://stello.arjunphlox.workers.dev/img/")
        var existingIDs = Set((try? context.fetch(FetchDescriptor<Item>()))?.map(\.id) ?? [])
        var existingURLs = Set((try? context.fetch(FetchDescriptor<Item>()))?.compactMap(\.sourceURL) ?? [])

        let candidates = export.items
        total = limit.map { min($0, candidates.count) } ?? candidates.count
        var newItems: [Item] = []

        for record in candidates {
            if cancelled || (limit != nil && newItems.count >= total) { break }
            let id = UUID(uuidString: record.id) ?? UUID()
            if existingIDs.contains(id) || (record.sourceURL.map { existingURLs.contains($0) } ?? false) {
                skipped += 1
                continue
            }
            let item = makeItem(record, id: id, deferClassify: !classify, context: context)
            await attachImages(record.images ?? [], to: item, baseURL: baseURL, context: context)
            newItems.append(item)
            existingIDs.insert(id)
            if let url = record.sourceURL { existingURLs.insert(url) }
            imported += 1
            // Save in small batches so a long import survives a quit and syncs as it goes.
            if imported % 25 == 0 { try? context.save() }
        }
        do { try context.save() } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        // Bring back the curated sample catalog (typefaces, foundries, sites,
        // studios), only the entries the library doesn't already have. Full imports
        // only: against a partial library it would add rows the rest of the export
        // already has, and those URLs would then be skipped by the full import.
        if !cancelled, limit == nil {
            await OptacosImporter.importIfNeeded(in: context, options: .uniqueIntoLibrary)
        }

        if classify, !cancelled {
            phase = .classifying
            for item in newItems where item.sourceURL != nil {
                if cancelled { break }
                await coordinator.enrichItem(item, context: context, force: true)
                classified += 1
            }
        }
        phase = .done
    }

    // MARK: - Background classify pass

    /// Runs the deferred work on imported items, cheapest first. Every stage keeps
    /// its queue in `enrichmentStatus`, so it's safe to stop anywhere: unfinished
    /// items keep their marker and the next launch picks them up.
    /// 1. Kinds from URL and collection labels (no network).
    /// 2. Kinds from fetched pages, several at once (no AI).
    /// 3. Full Enrich with the on-device model, one at a time at low priority.
    static func classifyPending(
        context: ModelContext,
        coordinator: EnrichmentCoordinator,
        pause: Duration = .seconds(2)
    ) async {
        guard !isClassifyingPending else { return }
        isClassifyingPending = true
        defer { isClassifyingPending = false }

        await assignKindsFromLabels(context: context)
        await assignKindsFromPages(context: context) { await CaptureService.fetchPage(url: $0) }

        // Without the system model the fallback would finish items with nothing
        // learned, so leave them queued for a launch when it's available.
        guard coordinator.primary.isAvailable else { return }
        await enrichAwaitingAI(context: context, pause: pause) { item in
            await coordinator.enrichItem(item, context: context, force: true)
        }
    }

    static func isQueued(_ item: Item) -> Bool {
        item.enrichmentStatus == awaitingClassifyStatus || item.enrichmentStatus == awaitingAIStatus
    }

    /// The kinds Enrich can reach from a `link`, so the fast stages agree with it.
    private nonisolated static let assignableKinds: Set<ItemKind> = [
        .post, .resource, .book, .product, .tool, .course, .article,
    ]

    private static func itemsAwaitingClassify(in context: ModelContext) -> [Item] {
        let status = awaitingClassifyStatus
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate<Item> { $0.enrichmentStatus == status })
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Stage 1. Decides what the URL and labels alone can. The rest stay queued for stage 2.
    static func assignKindsFromLabels(context: ModelContext) async {
        for (index, item) in itemsAwaitingClassify(in: context).enumerated() {
            if Task.isCancelled { break }
            if let raw = item.sourceURL, let url = URL(string: raw) {
                let result = PageClassifier.classify(
                    html: "", baseURL: url, domain: item.domain, title: item.title, ogDescription: nil,
                    collectionLabels: EnrichmentService.collectionLabels(for: item)
                )
                if assignableKinds.contains(result.kind) {
                    item.kind = result.kind.rawValue
                    item.enrichmentStatus = awaitingAIStatus
                }
            }
            if index % 200 == 199 {
                try? context.save()
                await Task.yield()
            }
        }
        try? context.save()
    }

    private struct PageJob: Sendable {
        var id: PersistentIdentifier
        var url: URL
        var domain: String?
        var title: String?
        var labels: [String]
    }

    private struct PageOutcome: Sendable {
        var id: PersistentIdentifier
        var kind: ItemKind?
        var isGone = false
    }

    private nonisolated static func classifyPage(
        _ job: PageJob,
        fetch: @Sendable (URL) async -> PageFetchResult?
    ) async -> PageOutcome {
        guard let page = await fetch(job.url) else { return PageOutcome(id: job.id, kind: nil) }
        let result = PageClassifier.classify(
            html: page.html, baseURL: job.url, domain: job.domain, title: job.title,
            ogDescription: page.og.description, ogType: page.og.ogType, collectionLabels: job.labels
        )
        return PageOutcome(id: job.id, kind: assignableKinds.contains(result.kind) ? result.kind : nil, isGone: page.isGone)
    }

    /// Stage 2. Fetches the remaining pages a few at a time and applies the rules, no AI.
    /// An item whose page can't be read moves on as a `link`; stage 3 tries it again.
    static func assignKindsFromPages(
        context: ModelContext,
        concurrency: Int = 6,
        fetch: @escaping @Sendable (URL) async -> PageFetchResult?
    ) async {
        var jobs: [PageJob] = []
        for item in itemsAwaitingClassify(in: context) {
            guard let raw = item.sourceURL, let url = URL(string: raw) else {
                item.enrichmentStatus = awaitingAIStatus
                continue
            }
            jobs.append(PageJob(
                id: item.persistentModelID, url: url, domain: item.domain, title: item.title,
                labels: EnrichmentService.collectionLabels(for: item)
            ))
        }
        try? context.save()

        await withTaskGroup(of: PageOutcome.self) { group in
            var queue = jobs.makeIterator()
            for _ in 0..<concurrency {
                guard let job = queue.next() else { break }
                group.addTask { await classifyPage(job, fetch: fetch) }
            }
            var finished = 0
            while let outcome = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                if let item = context.model(for: outcome.id) as? Item, item.enrichmentStatus == awaitingClassifyStatus {
                    if let kind = outcome.kind { item.kind = kind.rawValue }
                    if outcome.isGone { item.status = "gone" }
                    item.enrichmentStatus = awaitingAIStatus
                }
                finished += 1
                if finished % 20 == 0 {
                    try? context.save()
                    NSLog("Web import kinds: %d of %d pages read", finished, jobs.count)
                }
                if let job = queue.next() {
                    group.addTask { await classifyPage(job, fetch: fetch) }
                }
            }
        }
        try? context.save()
    }

    /// Stage 3. Full Enrich, one item at a time with a pause so the app stays usable.
    static func enrichAwaitingAI(
        context: ModelContext,
        pause: Duration,
        enrich: (Item) async -> Void
    ) async {
        let status = awaitingAIStatus
        var descriptor = FetchDescriptor<Item>(
            predicate: #Predicate<Item> { $0.enrichmentStatus == status },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        var finished = 0
        while !Task.isCancelled, let item = try? context.fetch(descriptor).first {
            await enrich(item)
            if Task.isCancelled { break }
            // Enrich normally moves the item on; never loop on one that it didn't.
            if item.enrichmentStatus == status { item.enrichmentStatus = "candidates_done" }
            try? context.save()
            finished += 1
            NSLog("Web import enrich: %d finished this run", finished)
            try? await Task.sleep(for: pause)
        }
    }

    // MARK: - Mapping

    private func makeItem(_ r: Export.Record, id: UUID, deferClassify: Bool, context: ModelContext) -> Item {
        let item = Item(
            id: id,
            slug: r.slug ?? id.uuidString.lowercased(),
            title: r.title ?? r.domain ?? "Untitled",
            sourceURL: r.sourceURL,
            domain: r.domain,
            author: r.author,
            summary: r.summary,
            bodyMarkdown: r.bodyMarkdown,
            status: r.status == "gone" ? "gone" : "active",
            needsReview: r.needsReview ?? false,
            addedAt: Self.date(r.addedAt) ?? .now,
            analyzedAt: Self.date(r.analyzedAt),
            updatedAt: Self.date(r.updatedAt) ?? .now,
            // Terminal status: auto-enrichment leaves imported items alone; Enrich
            // (force) still runs on them to refetch and classify.
            enrichmentStatus: deferClassify && r.sourceURL != nil ? Self.awaitingClassifyStatus : "candidates_done",
            kind: ItemKind.link.rawValue
        )
        context.insert(item)

        var seen = Set<String>()
        for t in r.tags ?? [] {
            guard let name = t.tag, !name.isEmpty, let category = t.category else { continue }
            guard seen.insert("\(category):\(name.lowercased())").inserted else { continue }
            let tag = Tag(name: name, category: category, weight: t.weight ?? 0.5, source: "import")
            context.insert(tag)
            tag.item = item
        }
        for s in r.snippets ?? [] {
            guard let text = s.text, !text.isEmpty else { continue }
            let snippet = Snippet(text: text, source: s.source ?? "import", addedAt: Self.date(s.addedAt) ?? item.addedAt)
            context.insert(snippet)
            snippet.item = item
        }
        return item
    }

    private func attachImages(_ images: [Export.Image], to item: Item, baseURL: URL?, context: ModelContext) async {
        let resolved: [(Export.Image, URL)] = images.compactMap { image in
            guard let path = image.path, !path.isEmpty else { return nil }
            if path.hasPrefix("http"), let url = URL(string: path) { return (image, url) }
            // "/img/<key>" serve paths → <image_base_url><key>
            let key = path.hasPrefix("/img/") ? String(path.dropFirst(5)) : path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let baseURL, let url = URL(string: key, relativeTo: baseURL)?.absoluteURL else { return nil }
            return (image, url)
        }
        guard !resolved.isEmpty else { return }
        let downloads = await CaptureService.downloadImages(resolved.map(\.1))
        var hasPrimary = false
        for ((image, _), download) in zip(resolved, downloads) {
            guard let download else { continue }
            let (data, w, h) = download
            let isPrimary = (image.isPrimary ?? false) && !hasPrimary
            hasPrimary = hasPrimary || isPrimary
            let stored = ItemImage(
                data: data,
                source: image.source?.isEmpty == false ? image.source! : "og",
                isPrimary: isPrimary,
                width: w > 0 ? w : image.width,
                height: h > 0 ? h : image.height
            )
            context.insert(stored)
            stored.item = item
        }
        if !hasPrimary, let first = item.images?.first { first.isPrimary = true }
    }

    private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    private static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        return isoFull.date(from: string) ?? isoPlain.date(from: string)
    }

    // MARK: - File format

    struct Export: Decodable {
        var imageBaseURL: String?
        var items: [Record]

        enum CodingKeys: String, CodingKey {
            case imageBaseURL = "image_base_url"
            case items
        }

        struct Record: Decodable {
            var id: String
            var slug: String?
            var title: String?
            var sourceURL: String?
            var domain: String?
            var author: String?
            var summary: String?
            var bodyMarkdown: String?
            var status: String?
            var needsReview: Bool?
            var addedAt: String?
            var analyzedAt: String?
            var updatedAt: String?
            var tags: [TagRecord]?
            var images: [Image]?
            var snippets: [SnippetRecord]?

            enum CodingKeys: String, CodingKey {
                case id, slug, title, domain, author, summary, status, tags, images, snippets
                case sourceURL = "source_url"
                case bodyMarkdown = "body_markdown"
                case needsReview = "needs_review"
                case addedAt = "added_at"
                case analyzedAt = "analyzed_at"
                case updatedAt = "updated_at"
            }
        }

        struct TagRecord: Decodable {
            var tag: String?
            var category: String?
            var weight: Double?
        }

        struct Image: Decodable {
            var path: String?
            var source: String?
            var isPrimary: Bool?
            var width: Int?
            var height: Int?

            enum CodingKeys: String, CodingKey {
                case path, source, width, height
                case isPrimary = "is_primary"
            }
        }

        struct SnippetRecord: Decodable {
            var text: String?
            var source: String?
            var addedAt: String?

            enum CodingKeys: String, CodingKey {
                case text, source
                case addedAt = "added_at"
            }
        }
    }
}
