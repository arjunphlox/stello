import Foundation
import CoreGraphics
import ImageIO
import SwiftData
import UniformTypeIdentifiers

/// Imports the old web library (the one-time Supabase export, Nov 2026) into the
/// app's SwiftData + CloudKit store, which makes it the iCloud library the web
/// app now reads.
///
/// File shape: `{ image_base_url, items: [{ id, slug, title, source_url, domain, author,
/// summary, body_markdown, status, needs_review, added_at, analyzed_at, updated_at,
/// tags: [{ tag, category, weight }], images: [{ path, source, is_primary, width, height }],
/// snippets: [{ text, source, added_at }] }] }`
///
/// Items keep their ids, slugs and dates. The import itself only writes rows: no
/// network, no AI. Everything slower happens afterwards in `classifyPending`, which
/// resumes on the next launch. Re-running the import skips items that already exist
/// (same id or source URL).
@Observable
@MainActor
final class WebLibraryImporter {
    static let shared = WebLibraryImporter()

    enum Phase: Equatable { case idle, importing, done, failed(String) }

    /// `enrichmentStatus` of an imported item whose kind isn't settled yet.
    /// Stored on the item, so the queue survives quits and syncs.
    nonisolated static let awaitingClassifyStatus = "awaiting_classify"
    /// Kind is settled. The background pass will write a summary if it's missing one.
    nonisolated static let awaitingAIStatus = "awaiting_ai"
    /// Nothing left for the background: full Enrich (snippets, why-saved, extra tags)
    /// runs when the item is first opened.
    nonisolated static let awaitingOpenStatus = "awaiting_open"
    private static let catalogPendingKey = "webImport.catalogPending"
    private static var isClassifyingPending = false

    private(set) var phase: Phase = .idle
    private(set) var total = 0
    private(set) var imported = 0
    private(set) var skipped = 0
    private(set) var stageName: String?
    private(set) var stageDone = 0
    private(set) var stageTotal = 0
    private var cancelled = false

    var isRunning: Bool { phase == .importing }

    var statusText: String {
        switch phase {
        case .idle: return ""
        case .importing: return "Importing \(imported + skipped) of \(total)…"
        case .done: return "Imported \(imported) items" + (skipped > 0 ? ", skipped \(skipped) already here" : "")
        case .failed(let message): return "Import failed: \(message)"
        }
    }

    /// The background stage in progress, for Settings.
    var stageText: String? {
        guard let stageName else { return nil }
        return stageTotal > 0 ? "\(stageName): \(stageDone) of \(stageTotal)" : stageName
    }

    private func setStage(_ name: String?, total: Int = 0) {
        stageName = name
        stageDone = 0
        stageTotal = total
    }

    func cancel() { cancelled = true }

    /// Writes the export's rows and settles what the URL and labels decide. No network.
    func run(fileURL: URL, context: ModelContext, limit: Int? = nil) async {
        guard !isRunning else { return }
        cancelled = false
        imported = 0; skipped = 0; total = 0
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
        let existing = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        var existingIDs = Set(existing.map(\.id))
        var existingURLs = Set(existing.compactMap(\.sourceURL))

        total = limit.map { min($0, export.items.count) } ?? export.items.count

        for record in export.items {
            if cancelled || (limit != nil && imported >= total) { break }
            let id = UUID(uuidString: record.id) ?? UUID()
            if existingIDs.contains(id) || (record.sourceURL.map { existingURLs.contains($0) } ?? false) {
                skipped += 1
                continue
            }
            let item = makeItem(record, id: id, context: context)
            queueCovers(record.images ?? [], for: item, baseURL: baseURL, context: context)
            existingIDs.insert(id)
            if let url = record.sourceURL { existingURLs.insert(url) }
            imported += 1
            // Batches keep a long import safe across a quit and let the UI breathe.
            if imported % 500 == 0 {
                try? context.save()
                await Task.yield()
            }
        }
        do { try context.save() } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        await Self.assignKindsFromLabels(context: context)
        // Full imports only: against a partial library the catalog would add rows the
        // rest of the export already has, and those URLs would then be skipped.
        if !cancelled, limit == nil {
            UserDefaults.standard.set(true, forKey: Self.catalogPendingKey)
        }
        phase = .done
    }

    // MARK: - Background classify pass

    /// Runs the deferred work on imported items, cheapest and most visible first. Every
    /// stage keeps its queue on the rows themselves, so it's safe to stop anywhere: the
    /// next launch picks up what's left.
    /// 1. Kinds from URL and collection labels (no network).
    /// 2. Thumbnails for images whose URL the export already gave.
    /// 3. Pages for items still needing a kind or a cover (rules only, no AI).
    /// 4. The sample catalog, after a full import.
    /// 5. Summaries for items without one. Full Enrich waits until an item is opened.
    static func classifyPending(
        context: ModelContext,
        coordinator: EnrichmentCoordinator,
        network: ImportNetwork = .live
    ) async {
        guard !isClassifyingPending else { return }
        isClassifyingPending = true
        defer {
            isClassifyingPending = false
            shared.setStage(nil)
        }

        // The grid builds every card and rebuilds them when the main context changes, so
        // this work stays in its own context and only reaches the UI when it saves.
        let work = ModelContext(context.container)
        work.autosaveEnabled = false

        await assignKindsFromLabels(context: work)
        await downloadKnownCovers(context: work, network: network)
        await readPages(context: work, network: network)

        if !Task.isCancelled, UserDefaults.standard.bool(forKey: catalogPendingKey) {
            shared.setStage("Adding the sample catalog")
            await OptacosImporter.importIfNeeded(in: work, options: .uniqueIntoLibrary)
            UserDefaults.standard.set(false, forKey: catalogPendingKey)
        }

        await triageAwaitingAI(context: work)

        // Without the system model nothing can be written, so leave items queued for a
        // launch when it's available.
        guard coordinator.primary.isAvailable else { return }
        await enrichAwaitingAI(context: work, pause: { userIsActive ? .seconds(2) : .zero }) { item in
            await coordinator.writeSummary(for: item)
        }
    }

    static func isQueued(_ item: Item) -> Bool {
        [awaitingClassifyStatus, awaitingAIStatus, awaitingOpenStatus].contains(item.enrichmentStatus)
    }

    /// Mirrors the card's own test for real summary text.
    static func hasSummary(_ item: Item) -> Bool {
        (item.summary?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0) > 30
    }

    /// True when someone used the keyboard or pointer in the last few seconds.
    private static var userIsActive: Bool {
        #if os(macOS)
        guard let anyInput = CGEventType(rawValue: ~0) else { return true }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput) < 5
        #else
        return true
        #endif
    }

    /// Items that already have a summary skip the background pass.
    static func triageAwaitingAI(context: ModelContext) async {
        let status = awaitingAIStatus
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate<Item> { $0.enrichmentStatus == status })
        for (index, item) in ((try? context.fetch(descriptor)) ?? []).enumerated() where hasSummary(item) {
            item.enrichmentStatus = awaitingOpenStatus
            if index % 500 == 499 { await Task.yield() }
        }
        try? context.save()
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

    private static func pendingCovers(in context: ModelContext) -> [ItemImage] {
        let descriptor = FetchDescriptor<ItemImage>(predicate: #Predicate<ItemImage> { $0.coverPending == true })
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Stage 1. Decides what the URL and labels alone can. The rest stay queued.
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
            if index % 500 == 499 {
                try? context.save()
                await Task.yield()
            }
        }
        try? context.save()
    }

    // MARK: Network pool

    /// Item IDs on screen right now; the pool serves these first.
    private static var priorityItems: [PersistentIdentifier] = []

    /// Called as a card appears, so what's visible gets its cover first.
    static func prioritize(_ item: Item) {
        guard isClassifyingPending,
              item.enrichmentStatus == awaitingAIStatus || item.images?.contains(where: \.coverPending) == true
        else { return }
        priorityItems.append(item.persistentModelID)
    }

    /// Runs `work` over `jobs` with a fixed number in flight, applying each result on
    /// the main actor. A stop leaves unapplied jobs queued for the next launch.
    private static func runPool<Job: Sendable, Outcome: Sendable>(
        jobs: [Job],
        itemID: (Job) -> PersistentIdentifier,
        concurrency: Int,
        context: ModelContext,
        saveEvery: Duration,
        work: @escaping @Sendable (Job) async -> Outcome,
        apply: (Outcome) -> Void
    ) async {
        var waiting: [PersistentIdentifier: [Job]] = [:]
        for job in jobs { waiting[itemID(job), default: []].append(job) }
        var order = jobs.makeIterator()
        var left = jobs.count

        func next() -> Job? {
            while let id = priorityItems.popLast() {
                if var list = waiting[id], !list.isEmpty {
                    let job = list.removeFirst()
                    waiting[id] = list
                    left -= 1
                    return job
                }
            }
            while let job = order.next() {
                let id = itemID(job)
                if let list = waiting[id], !list.isEmpty {
                    waiting[id] = Array(list.dropFirst())
                    left -= 1
                    return list[0]
                }
            }
            return nil
        }

        await withTaskGroup(of: Outcome.self) { group in
            for _ in 0..<concurrency {
                guard let job = next() else { break }
                group.addTask { await work(job) }
            }
            var finished = 0
            let clock = ContinuousClock()
            var lastSave = clock.now
            while let outcome = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                apply(outcome)
                finished += 1
                shared.stageDone = finished
                // Each save refreshes the whole grid, so it's the costly step here.
                if clock.now - lastSave >= saveEvery {
                    try? context.save()
                    lastSave = clock.now
                }
                if let job = next() { group.addTask { await work(job) } }
            }
        }
        try? context.save()
    }

    // MARK: Stage 2: known covers

    private struct CoverJob: Sendable {
        var itemID: PersistentIdentifier
        var imageID: PersistentIdentifier
        var url: URL
    }

    private struct CoverOutcome: Sendable {
        var imageID: PersistentIdentifier
        var thumbnail: ImportThumbnail?
    }

    /// Downloads images whose URL is already known and stores a small thumbnail.
    static func downloadKnownCovers(
        context: ModelContext,
        network: ImportNetwork,
        concurrency: Int = 24,
        saveEvery: Duration = .seconds(30)
    ) async {
        let jobs: [CoverJob] = pendingCovers(in: context).compactMap { image in
            guard let raw = image.sourceURL, let url = URL(string: raw), let item = image.item else { return nil }
            return CoverJob(itemID: item.persistentModelID, imageID: image.persistentModelID, url: url)
        }
        guard !jobs.isEmpty else { return }
        shared.setStage("Downloading covers", total: jobs.count)
        await runPool(
            jobs: jobs, itemID: \.itemID, concurrency: concurrency, context: context, saveEvery: saveEvery,
            work: { job in CoverOutcome(imageID: job.imageID, thumbnail: await network.thumbnail(job.url)) },
            apply: { outcome in
                guard let image = context.model(for: outcome.imageID) as? ItemImage else { return }
                image.coverPending = false
                if let thumbnail = outcome.thumbnail { image.apply(thumbnail) }
            }
        )
    }

    // MARK: Stage 3: pages

    private struct PageJob: Sendable {
        var itemID: PersistentIdentifier
        var coverRowID: PersistentIdentifier?
        var url: URL
        var domain: String?
        var title: String?
        var labels: [String]
    }

    private struct PageOutcome: Sendable {
        var job: PageJob
        var kind: ItemKind?
        var isGone = false
        var imageURL: URL?
        var thumbnail: ImportThumbnail?
    }

    private nonisolated static func readPage(_ job: PageJob, network: ImportNetwork) async -> PageOutcome {
        guard let page = await network.page(job.url) else { return PageOutcome(job: job) }
        let result = PageClassifier.classify(
            html: page.html, baseURL: job.url, domain: job.domain, title: job.title,
            ogDescription: page.og.description, ogType: page.og.ogType, collectionLabels: job.labels
        )
        var outcome = PageOutcome(
            job: job, kind: assignableKinds.contains(result.kind) ? result.kind : nil, isGone: page.isGone
        )
        if job.coverRowID != nil, let imageURL = page.og.imageURL {
            outcome.imageURL = imageURL
            outcome.thumbnail = await network.thumbnail(imageURL)
        }
        return outcome
    }

    /// One fetch per item that still needs a kind or a cover. Rules only, no AI. An item
    /// whose page can't be read moves on as a `link`; Enrich tries it again later.
    static func readPages(
        context: ModelContext,
        network: ImportNetwork,
        concurrency: Int = 24,
        saveEvery: Duration = .seconds(30)
    ) async {
        var coverRows: [PersistentIdentifier: ItemImage] = [:]
        for image in pendingCovers(in: context) where image.sourceURL == nil {
            guard let item = image.item else { continue }
            coverRows[item.persistentModelID] = image
        }
        var seen = Set<PersistentIdentifier>()
        let candidates = itemsAwaitingClassify(in: context) + coverRows.values.compactMap(\.item)
        var jobs: [PageJob] = []
        for item in candidates where seen.insert(item.persistentModelID).inserted {
            let id = item.persistentModelID
            guard let raw = item.sourceURL, let url = URL(string: raw) else {
                if item.enrichmentStatus == awaitingClassifyStatus { item.enrichmentStatus = awaitingAIStatus }
                if let row = coverRows[id] { context.delete(row) }
                continue
            }
            jobs.append(PageJob(
                itemID: id, coverRowID: coverRows[id]?.persistentModelID, url: url, domain: item.domain,
                title: item.title, labels: EnrichmentService.collectionLabels(for: item)
            ))
        }
        try? context.save()
        guard !jobs.isEmpty else { return }

        shared.setStage("Reading pages", total: jobs.count)
        await runPool(
            jobs: jobs, itemID: \.itemID, concurrency: concurrency, context: context, saveEvery: saveEvery,
            work: { job in await readPage(job, network: network) },
            apply: { outcome in
                if let item = context.model(for: outcome.job.itemID) as? Item {
                    if item.enrichmentStatus == awaitingClassifyStatus {
                        if let kind = outcome.kind { item.kind = kind.rawValue }
                        item.enrichmentStatus = awaitingAIStatus
                    }
                    if outcome.isGone { item.status = "gone" }
                }
                if let rowID = outcome.job.coverRowID, let row = context.model(for: rowID) as? ItemImage {
                    if let thumbnail = outcome.thumbnail {
                        row.coverPending = false
                        row.sourceURL = outcome.imageURL?.absoluteString
                        row.apply(thumbnail)
                    } else {
                        context.delete(row)
                    }
                }
            }
        )
    }

    /// Stage 5. One item at a time: cards on screen first, then the newest saves. An item
    /// moves on to `awaitingOpenStatus` either way, so this can't loop on one it can't help.
    static func enrichAwaitingAI(
        context: ModelContext,
        pause: () -> Duration,
        enrich: (Item) async -> Void
    ) async {
        let status = awaitingAIStatus
        var descriptor = FetchDescriptor<Item>(
            predicate: #Predicate<Item> { $0.enrichmentStatus == status },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        // Count before limiting the fetch to one item, or the total reads "1".
        let total = (try? context.fetchCount(descriptor)) ?? 0
        descriptor.fetchLimit = 1

        shared.setStage("Writing summaries", total: total)
        func next() -> Item? {
            while let id = priorityItems.popLast() {
                if let item = context.model(for: id) as? Item, item.enrichmentStatus == status { return item }
            }
            return try? context.fetch(descriptor).first
        }

        var finished = 0
        while !Task.isCancelled, let item = next() {
            await enrich(item)
            if Task.isCancelled { break }
            if item.enrichmentStatus == status { item.enrichmentStatus = awaitingOpenStatus }
            try? context.save()
            finished += 1
            shared.stageDone = finished
            NSLog("Web import enrich: %d finished this run", finished)
            try? await Task.sleep(for: pause())
        }
    }

    // MARK: - Mapping

    private func makeItem(_ r: Export.Record, id: UUID, context: ModelContext) -> Item {
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
            enrichmentStatus: r.sourceURL != nil ? Self.awaitingClassifyStatus : "candidates_done",
            kind: ItemKind.link.rawValue
        )
        context.insert(item)

        var seen = Set<String>()
        var tags: [ItemTag] = []
        for t in r.tags ?? [] {
            guard let name = t.tag, !name.isEmpty, let category = t.category else { continue }
            guard seen.insert("\(category):\(name.lowercased())").inserted else { continue }
            tags.append(ItemTag(name: name, category: category, weight: t.weight ?? 0.5, source: "import"))
        }
        item.tags = tags
        for s in r.snippets ?? [] {
            guard let text = s.text, !text.isEmpty else { continue }
            let snippet = Snippet(text: text, source: s.source ?? "import", addedAt: Self.date(s.addedAt) ?? item.addedAt)
            context.insert(snippet)
            snippet.item = item
        }
        return item
    }

    /// Records where each cover lives. The bytes arrive in the background. An item the
    /// export has no image for gets an empty row, and the page pass looks for one.
    private func queueCovers(_ images: [Export.Image], for item: Item, baseURL: URL?, context: ModelContext) {
        var hasPrimary = false
        var queued = false
        for image in images {
            guard let url = Self.resolve(image.path, baseURL: baseURL) else { continue }
            let isPrimary = (image.isPrimary ?? false) && !hasPrimary
            hasPrimary = hasPrimary || isPrimary
            let row = ItemImage(
                source: image.source?.isEmpty == false ? image.source! : "og",
                isPrimary: isPrimary, width: image.width, height: image.height
            )
            row.sourceURL = url.absoluteString
            row.coverPending = true
            context.insert(row)
            row.item = item
            queued = true
        }
        if queued {
            if !hasPrimary, let first = item.images?.first { first.isPrimary = true }
        } else if item.sourceURL != nil {
            let row = ItemImage(source: "og", isPrimary: true)
            row.coverPending = true
            context.insert(row)
            row.item = item
        }
    }

    private static func resolve(_ path: String?, baseURL: URL?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }
        // "/img/<key>" serve paths → <image_base_url><key>
        let key = path.hasPrefix("/img/") ? String(path.dropFirst(5)) : path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let baseURL else { return nil }
        return URL(string: key, relativeTo: baseURL)?.absoluteURL
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

// MARK: - Import network

/// A cover scaled down for the synced store. Full size stays at `ItemImage.sourceURL`.
struct ImportThumbnail: Sendable {
    var data: Data
    var width: Int
    var height: Int

    nonisolated init(data: Data, width: Int, height: Int) {
        self.data = data
        self.width = width
        self.height = height
    }

    /// nil when the bytes aren't a bitmap ImageIO can read.
    nonisolated init?(imageData: Data, maxPixels: Int = 600) {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let hasAlpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let output = NSMutableData()
        let type = (hasAlpha ? UTType.png : UTType.jpeg).identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        self.init(data: output as Data, width: image.width, height: image.height)
    }
}

extension ItemImage {
    func apply(_ thumbnail: ImportThumbnail) {
        data = thumbnail.data
        width = thumbnail.width
        height = thumbnail.height
    }
}

/// What the background stages fetch, kept off the main actor. Injected in tests.
struct ImportNetwork: Sendable {
    var page: @Sendable (URL) async -> PageFetchResult?
    var thumbnail: @Sendable (URL) async -> ImportThumbnail?

    nonisolated static let live = ImportNetwork(
        page: { url in
            guard let (data, response) = await fetch(url) else { return nil }
            // Same 2MB bound as `CaptureService.fetchPage`.
            let slice = data.prefix(2_000_000)
            guard let html = String(data: slice, encoding: .utf8) ?? String(data: slice, encoding: .isoLatin1) else { return nil }
            return PageFetchResult(
                html: html,
                og: CaptureService.parseOG(html: html, baseURL: url),
                statusCode: (response as? HTTPURLResponse)?.statusCode,
                finalURL: response.url
            )
        },
        thumbnail: { url in
            guard let (data, response) = await fetch(url),
                  ((response as? HTTPURLResponse)?.statusCode ?? 200) < 400 else { return nil }
            return ImportThumbnail(imageData: data)
        }
    )

    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        config.httpMaximumConnectionsPerHost = 8
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        ]
        return URLSession(configuration: config)
    }()

    private nonisolated static func fetch(_ url: URL) async -> (Data, URLResponse)? {
        try? await session.data(from: url)
    }
}
