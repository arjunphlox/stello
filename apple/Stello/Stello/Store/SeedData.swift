import Foundation
import SwiftData

enum SeedData {

    /// Bump when seed URLs or metadata change so persisted stores re-fetch OG covers.
    private static let catalogVersion = 3
    private static let catalogVersionKey = "stello.seedCatalogVersion"

    static var previewContainer: ModelContainer = {
        let schema = Schema([Item.self, Tag.self, ItemImage.self, Snippet.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let ctx = ModelContext(container)
        for item in makeSeedItems() { insertItemGraph(item, in: ctx) }
        try! ctx.save()
        return container
    }()

    static var sampleItem: Item { makeSeedItems()[0] }

    /// Item with AI enrichment output for previews and screenshot fixtures.
    static var enrichedSampleItem: Item {
        let item = Item(
            slug: "figma-auto-layout-guide",
            title: "Auto Layout Demystified",
            sourceURL: "https://www.figma.com/blog/design-systems-101-what-is-a-design-system/",
            domain: "figma.com",
            summary: "A comprehensive walkthrough of Figma's auto layout — constraints, gap, padding, and frame resizing.",
            enrichmentStatus: "candidates_done",
            whySavedSuggestionsJSON: EnrichmentService.encodeWhySavedSuggestions([
                "layout-reference",
                "auto-layout-patterns",
                "design-system-tips",
            ])
        )
        item.tags = [
            Tag(name: "tutorial", category: "format", weight: 0.9, source: "rule"),
            Tag(name: "figma", category: "tool", weight: 0.95, source: "rule"),
            Tag(name: "teal", category: "color", weight: 0.85, source: "ai"),
            Tag(name: "minimalist", category: "style", weight: 0.7, source: "ai"),
            Tag(name: "calm", category: "mood", weight: 0.6, source: "ai"),
        ]
        item.snippets = [
            Snippet(text: "Auto layout handles the hardest part of responsive design.", source: "ai"),
            Snippet(text: "Constraints and padding work together in Figma frames.", source: "ai"),
        ]
        return item
    }

    static func seedIfNeeded(in context: ModelContext) async {
        let count = (try? context.fetchCount(FetchDescriptor<Item>())) ?? 0
        guard count == 0 else { return }
        for item in makeSeedItems() { insertItemGraph(item, in: context) }
        try? context.save()
        UserDefaults.standard.set(catalogVersion, forKey: catalogVersionKey)
    }

    /// Updates persisted seed slugs to resolvable URLs and clears stale covers so backfill re-fetches OG images.
    static func refreshSeedCatalogIfNeeded(in context: ModelContext) async {
        let stored = UserDefaults.standard.integer(forKey: catalogVersionKey)
        guard stored < catalogVersion else { return }

        guard let items = try? context.fetch(FetchDescriptor<Item>()) else { return }
        let catalog = seedURLCatalog()
        var touched = false

        for item in items {
            guard let newURL = catalog[item.slug] else { continue }
            if item.sourceURL != newURL {
                item.sourceURL = newURL
                if let host = URL(string: newURL)?.host?.replacingOccurrences(of: "www.", with: "") {
                    item.domain = host
                }
                touched = true
            }
            if purgeAllCovers(for: item, in: context) { touched = true }
        }

        if touched { try? context.save() }
        UserDefaults.standard.set(catalogVersion, forKey: catalogVersionKey)
    }

    /// Idempotent launch migration: URL-backed items without renderable covers get an OG image
    /// via `CaptureService` (falls back to procedural gradient when offline or fetch fails).
    @discardableResult
    static func backfillSeedCovers(in context: ModelContext) async -> Int {
        guard let items = try? context.fetch(FetchDescriptor<Item>()) else { return 0 }
        var patched = 0
        for item in items where item.domain != nil {
            purgeBrokenGeneratedCovers(for: item, in: context)

            if let cover = item.coverImage, cover.source == "og", cover.hasRenderableCoverData {
                continue
            }

            var attached = false
            if let urlString = item.sourceURL, let url = URL(string: urlString) {
                attached = await attachOGCover(to: item, url: url, in: context)
            }

            if attached {
                removeGeneratedCovers(from: item, in: context)
                patched += 1
                continue
            }

            guard !item.hasRenderableCover else { continue }
            guard let cover = SampleCoverGenerator.cover(seed: SampleCoverGenerator.stableSeed(item.slug)) else {
                continue
            }
            demoteExistingPrimaries(on: item)
            let img = ItemImage(
                data: cover.data, source: "generated", isPrimary: true,
                width: cover.width, height: cover.height
            )
            context.insert(img)
            img.item = item
            if item.images == nil { item.images = [] }
            item.images?.append(img)
            patched += 1
        }
        if patched > 0 { try? context.save() }
        return patched
    }

    /// Inserts a fixed AI-enrichment demo item for simulator screenshots (`-screenshotEnrichmentDemo`).
    static func ensureEnrichmentDemo(in context: ModelContext) -> Item {
        let slug = "enrichment-demo"
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate<Item> { $0.slug == slug })
        if let existing = try? context.fetch(descriptor), let first = existing.first {
            return first
        }
        let item = enrichedSampleItem
        item.slug = slug
        context.insert(item)
        for tag in item.tags ?? [] {
            context.insert(tag)
            tag.item = item
        }
        for snippet in item.snippets ?? [] {
            context.insert(snippet)
            snippet.item = item
        }
        try? context.save()
        return item
    }

    // MARK: - Private

    /// Inserts an item and every related model so external-storage blobs persist on first save.
    private static func insertItemGraph(_ item: Item, in context: ModelContext) {
        for tag in item.tags ?? [] {
            context.insert(tag)
            tag.item = item
        }
        for img in item.images ?? [] {
            context.insert(img)
            img.item = item
        }
        for snippet in item.snippets ?? [] {
            context.insert(snippet)
            snippet.item = item
        }
        context.insert(item)
    }

    /// Drops generated covers whose bytes never persisted (CloudKit shell rows, failed external storage).
    private static func purgeBrokenGeneratedCovers(for item: Item, in context: ModelContext) {
        guard let images = item.images else { return }
        let broken = images.filter {
            ($0.source == "generated" || $0.source == "og") && !$0.hasRenderableCoverData
        }
        guard !broken.isEmpty else { return }
        for img in broken { context.delete(img) }
        item.images = images.filter { !broken.contains($0) }
    }

    @discardableResult
    private static func purgeAllCovers(for item: Item, in context: ModelContext) -> Bool {
        guard let images = item.images, !images.isEmpty else { return false }
        for img in images { context.delete(img) }
        item.images = []
        return true
    }

    /// Slug → canonical resolvable URL for seed items (real pages with og:image).
    private static func seedURLCatalog() -> [String: String] {
        [
            "figma-auto-layout-guide": "https://www.figma.com/blog/design-systems-101-what-is-a-design-system/",
            "figma-variables-tokens": "https://www.figma.com/blog/config-2024-recap/",
            "swift-composable-architecture": "https://github.com/pointfreeco/swift-composable-architecture",
            "dribbble-liquid-glass": "https://developer.apple.com/design/human-interface-guidelines/",
            "instagram-verte-studio": "https://tailwindcss.com/blog/tailwindcss-v4",
            "robin-rendle-display-type": "https://rsms.me/inter/",
            "alist-apart-web-typography": "https://alistapart.com/article/on-web-typography/",
            "youtube-helvetica-doc": "https://www.typewolf.com/",
            "are-na-visual-systems": "https://www.nngroup.com/articles/ten-usability-heuristics/",
            "producthunt-linear": "https://www.notion.so/product",
            "letterboxd-2001": "https://letterboxd.com/film/2001-a-space-odyssey/",
            "spotify-eno-ambient": "https://open.spotify.com/album/063f8Ej8rLVTz9KkjQKEMa",
            "goodreads-design-everyday-things": "https://www.goodreads.com/book/show/840.The_Design_of_Everyday_Things",
            "arxiv-attention-paper": "https://arxiv.org/abs/1706.03762",
            "vercel-v0-launch": "https://vercel.com/blog/ai-sdk-3-generative-ui",
            "github-swiftformat": "https://github.com/nicklockwood/SwiftFormat",
            "css-tricks-grid-guide": "https://css-tricks.com/snippets/css/complete-guide-grid/",
            "css-tricks-flexbox-gap": "https://css-tricks.com/minding-the-gap/",
        ]
    }

    private static func demoteExistingPrimaries(on item: Item) {
        for img in item.images ?? [] where img.isPrimary {
            img.isPrimary = false
        }
    }

    private static func removeGeneratedCovers(from item: Item, in context: ModelContext) {
        guard let images = item.images else { return }
        let generated = images.filter { $0.source == "generated" }
        guard !generated.isEmpty else { return }
        for img in generated { context.delete(img) }
        item.images = images.filter { !generated.contains($0) }
    }

    @discardableResult
    private static func attachOGCover(to item: Item, url: URL, in context: ModelContext) async -> Bool {
        let og = await CaptureService.fetchOG(url: url)
        guard let imgURL = og.imageURL,
              let (data, w, h) = await CaptureService.downloadImage(url: imgURL) else { return false }
        demoteExistingPrimaries(on: item)
        let img = ItemImage(data: data, source: "og", isPrimary: true, width: w, height: h)
        context.insert(img)
        img.item = item
        if item.images == nil { item.images = [] }
        item.images?.append(img)
        return true
    }

    private static func daysAgo(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -n, to: .now)!
    }

    private static func makeSeedItems() -> [Item] {
        [
            seed("figma-auto-layout-guide",
                 title: "Auto Layout Demystified",
                 domain: "figma.com",
                 url: "https://www.figma.com/blog/design-systems-101-what-is-a-design-system/",
                 summary: "A comprehensive walkthrough of Figma's auto layout — constraints, gap, padding, and frame resizing.",
                 daysAgo: 1,
                 tags: [("tutorial","format",0.9),("figma","tool",0.95),("design-systems","domain",0.8),("layout","subject",0.85),("clean","style",0.6)]),

            seed("figma-variables-tokens",
                 title: "Config 2024 Recap",
                 domain: "figma.com",
                 url: "https://www.figma.com/blog/config-2024-recap/",
                 summary: "Variables, dev mode, and the design-token workflow shipped at Figma Config 2024.",
                 daysAgo: 2,
                 tags: [("reference","format",0.85),("figma","tool",0.95),("tokens","subject",0.9),("design-systems","domain",0.85),("systematic","style",0.7)]),

            seed("swift-composable-architecture",
                 title: "pointfreeco/swift-composable-architecture",
                 domain: "github.com",
                 url: "https://github.com/pointfreeco/swift-composable-architecture",
                 summary: "A library for building applications in a consistent and understandable way, with composition, testing, and ergonomics in mind.",
                 daysAgo: 0,
                 tags: [("library","format",0.9),("swift","tool",0.95),("architecture","subject",0.9),("ios","domain",0.85),("functional","style",0.8)]),

            seed("dribbble-liquid-glass",
                 title: "Materials — Human Interface Guidelines",
                 domain: "developer.apple.com",
                 url: "https://developer.apple.com/design/human-interface-guidelines/",
                 summary: "Apple's guidance on materials, vibrancy, and the Liquid Glass system across platforms.",
                 daysAgo: 4,
                 tags: [("inspiration","format",0.85),("ui-kit","domain",0.8),("translucent","style",0.9),("blue","color",0.6),("speculative","mood",0.7)]),

            seed("instagram-verte-studio",
                 title: "Tailwind CSS v4.0",
                 domain: "tailwindcss.com",
                 url: "https://tailwindcss.com/blog/tailwindcss-v4",
                 summary: "A ground-up rewrite of the utility-first framework — faster engine, native cascade layers, design tokens.",
                 daysAgo: 5,
                 tags: [("article","format",0.9),("css","tool",0.9),("layout","subject",0.95),("web","domain",0.85),("calm","mood",0.8)]),

            seed("robin-rendle-display-type",
                 title: "Inter — The Typeface",
                 domain: "rsms.me",
                 url: "https://rsms.me/inter/",
                 summary: "How large-scale type creates hierarchy, mood, and meaning in editorial design.",
                 daysAgo: 6,
                 tags: [("reference","format",0.9),("typography","subject",0.95),("editorial","domain",0.8),("expressive","style",0.85),("thoughtful","mood",0.75)]),

            seed("alist-apart-web-typography",
                 title: "On Web Typography",
                 domain: "alistapart.com",
                 url: "https://alistapart.com/article/on-web-typography/",
                 summary: "A deep dive into selecting, pairing, and using typefaces for the web.",
                 daysAgo: 7,
                 tags: [("article","format",0.9),("typography","subject",0.95),("web","domain",0.85),("classic","style",0.7),("reference","intent",0.9)]),

            seed("youtube-helvetica-doc",
                 title: "Typewolf — Typography Inspiration",
                 domain: "typewolf.com",
                 url: "https://www.typewolf.com/",
                 summary: "A daily showcase of typography in the wild — font pairings, type trends, and lettering on real sites.",
                 daysAgo: 8,
                 tags: [("reference","format",0.95),("typography","subject",0.95),("editorial","domain",0.85),("classic","style",0.8),("neutral","color",0.6)]),

            seed("are-na-visual-systems",
                 title: "Ten Usability Heuristics — NN/g",
                 domain: "nngroup.com",
                 url: "https://www.nngroup.com/articles/ten-usability-heuristics/",
                 summary: "A curated channel exploring grid systems, modular design, and visual order.",
                 daysAgo: 10,
                 tags: [("article","format",0.85),("ux","subject",0.9),("research","intent",0.9),("systematic","style",0.85)]),

            seed("producthunt-linear",
                 title: "Notion — The Connected Workspace",
                 domain: "notion.so",
                 url: "https://www.notion.so/product",
                 summary: "Docs, projects, and knowledge in one place — the workspace used by modern product teams.",
                 daysAgo: 10,
                 tags: [("product-launch","format",0.85),("productivity","subject",0.9),("tool","domain",0.95),("minimal","style",0.8),("energetic","mood",0.7)]),

            seed("letterboxd-2001",
                 title: "2001: A Space Odyssey (1968)",
                 domain: "letterboxd.com",
                 url: "https://letterboxd.com/film/2001-a-space-odyssey/",
                 summary: "Kubrick's landmark sci-fi epic exploring human evolution, AI, and the cosmos.",
                 daysAgo: 11,
                 tags: [("film","format",0.95),("cinema","domain",0.9),("sci-fi","subject",0.85),("transcendent","mood",0.9),("blue","color",0.65)]),

            seed("spotify-eno-ambient",
                 title: "Brian Eno — Ambient 1: Music for Airports",
                 domain: "spotify.com",
                 url: "https://open.spotify.com/album/063f8Ej8rLVTz9KkjQKEMa",
                 summary: "The 1978 album that defined the ambient genre. Designed to induce calm and a sense of space.",
                 daysAgo: 12,
                 tags: [("album","format",0.95),("ambient","subject",0.95),("music","domain",0.9),("calm","mood",0.9),("white","color",0.5)]),

            seed("goodreads-design-everyday-things",
                 title: "The Design of Everyday Things",
                 domain: "goodreads.com",
                 url: "https://www.goodreads.com/book/show/840.The_Design_of_Everyday_Things",
                 summary: "Norman's essential text on user-centered design, affordances, and mental models.",
                 daysAgo: 13,
                 tags: [("book","format",0.95),("ux","subject",0.9),("design","domain",0.85),("foundational","intent",0.9),("analytical","style",0.7)]),

            seed("arxiv-attention-paper",
                 title: "Attention Is All You Need (2017)",
                 domain: "arxiv.org",
                 url: "https://arxiv.org/abs/1706.03762",
                 summary: "The Transformer architecture paper by Vaswani et al. that underpins modern LLMs.",
                 daysAgo: 14,
                 tags: [("paper","format",0.95),("ml","subject",0.95),("research","domain",0.9),("foundational","intent",0.9),("dense","style",0.6)]),

            seed("note-stello-sprint-1",
                 title: "Ideas for Stello Sprint 1",
                 domain: nil, url: nil,
                 summary: "Detail view redesign, tag editor, search with embeddings, capture sheet.",
                 daysAgo: 3,
                 tags: [("note","format",0.9),("planning","intent",0.9),("product","subject",0.85),("energetic","mood",0.7)]),

            seed("note-typography-reading-list",
                 title: "Typography Reading List",
                 domain: nil, url: nil,
                 summary: "Thinking With Type, The Elements of Typographic Style, Fonts & Encodings.",
                 daysAgo: 9,
                 tags: [("note","format",0.9),("typography","subject",0.95),("reading","intent",0.85)]),

            seed("vercel-v0-launch",
                 title: "Generative UI with the Vercel AI SDK",
                 domain: "vercel.com",
                 url: "https://vercel.com/blog/ai-sdk-3-generative-ui",
                 summary: "Stream React components straight from the model — generative UI with the Vercel AI SDK.",
                 daysAgo: 13,
                 tags: [("article","format",0.85),("ai","subject",0.9),("web-dev","domain",0.85),("tool","intent",0.9),("modern","style",0.75)]),

            seed("github-swiftformat",
                 title: "nicklockwood/SwiftFormat",
                 domain: "github.com",
                 url: "https://github.com/nicklockwood/SwiftFormat",
                 summary: "A code library and command-line tool for reformatting Swift code on save.",
                 daysAgo: 15,
                 tags: [("tool","format",0.9),("swift","tool",0.95),("dev-tools","domain",0.85),("practical","intent",0.9)]),

            seed("css-tricks-grid-guide",
                 title: "A Complete Guide to CSS Grid",
                 domain: "css-tricks.com",
                 url: "https://css-tricks.com/snippets/css/complete-guide-grid/",
                 summary: "The definitive reference for CSS Grid — properties for the container and children.",
                 daysAgo: 16,
                 tags: [("reference","format",0.9),("css","tool",0.9),("web","domain",0.85),("layout","subject",0.85),("systematic","style",0.7)]),

            seed("css-tricks-flexbox-gap",
                 title: "The New Flexbox Gap Property",
                 domain: "css-tricks.com",
                 url: "https://css-tricks.com/minding-the-gap/",
                 summary: "How the gap property finally works in Flexbox, and why it matters for layout.",
                 daysAgo: 16,
                 tags: [("article","format",0.85),("css","tool",0.9),("web","domain",0.85),("layout","subject",0.8)]),
        ]
    }

    private static func seed(
        _ slug: String,
        title: String,
        domain: String?,
        url: String?,
        summary: String?,
        daysAgo: Int,
        tags: [(String, String, Double)]
    ) -> Item {
        let item = Item(
            slug: slug,
            title: title,
            sourceURL: url,
            domain: domain,
            summary: summary,
            needsReview: false,
            addedAt: Self.daysAgo(daysAgo),
            updatedAt: Self.daysAgo(daysAgo),
            enrichmentStatus: "candidates_done"
        )
        item.tags = tags.map { Tag(name: $0.0, category: $0.1, weight: $0.2) }
        return item
    }
}
