import Foundation
import SwiftData

enum SeedData {

    static var previewContainer: ModelContainer = {
        let schema = Schema([Item.self, Tag.self, ItemImage.self, Snippet.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let ctx = ModelContext(container)
        for item in makeSeedItems() { ctx.insert(item) }
        try! ctx.save()
        return container
    }()

    static var sampleItem: Item { makeSeedItems()[0] }

    static func seedIfNeeded(in context: ModelContext) async {
        let count = (try? context.fetchCount(FetchDescriptor<Item>())) ?? 0
        guard count == 0 else { return }
        for item in makeSeedItems() { context.insert(item) }
        try? context.save()
    }

    // MARK: - Private

    private static func daysAgo(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -n, to: .now)!
    }

    private static func makeSeedItems() -> [Item] {
        [
            seed("figma-auto-layout-guide",
                 title: "Auto Layout Demystified",
                 domain: "figma.com",
                 url: "https://figma.com/blog/auto-layout",
                 summary: "A comprehensive walkthrough of Figma's auto layout — constraints, gap, padding, and frame resizing.",
                 daysAgo: 1,
                 tags: [("tutorial","format",0.9),("figma","tool",0.95),("design-systems","domain",0.8),("layout","subject",0.85),("clean","style",0.6)]),

            seed("figma-variables-tokens",
                 title: "Variables & Design Tokens in Figma",
                 domain: "figma.com",
                 url: "https://figma.com/blog/variables",
                 summary: "How to use variables for color, spacing, and typography tokens across a design system.",
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
                 title: "Liquid Glass UI Concepts",
                 domain: "dribbble.com",
                 url: "https://dribbble.com/shots/liquid-glass",
                 summary: "UI explorations using Apple's new Liquid Glass material system.",
                 daysAgo: 4,
                 tags: [("inspiration","format",0.85),("ui-kit","domain",0.8),("translucent","style",0.9),("blue","color",0.6),("speculative","mood",0.7)]),

            seed("instagram-verte-studio",
                 title: "@_verte.studio — Motion Studies",
                 domain: "instagram.com",
                 url: "https://instagram.com/_verte.studio",
                 summary: "Motion design experiments exploring transitions and material interactions.",
                 daysAgo: 5,
                 tags: [("video","format",0.9),("motion","subject",0.95),("minimal","style",0.85),("green","color",0.7),("calm","mood",0.8)]),

            seed("robin-rendle-display-type",
                 title: "The Architecture of Display Type",
                 domain: "robinrendle.com",
                 url: "https://robinrendle.com/notes/the-architecture-of-display-type",
                 summary: "How large-scale type creates hierarchy, mood, and meaning in editorial design.",
                 daysAgo: 6,
                 tags: [("essay","format",0.9),("typography","subject",0.95),("editorial","domain",0.8),("expressive","style",0.85),("thoughtful","mood",0.75)]),

            seed("alist-apart-web-typography",
                 title: "On Web Typography",
                 domain: "alistapart.com",
                 url: "https://alistapart.com/article/on-web-typography",
                 summary: "A deep dive into selecting, pairing, and using typefaces for the web.",
                 daysAgo: 7,
                 tags: [("article","format",0.9),("typography","subject",0.95),("web","domain",0.85),("classic","style",0.7),("reference","intent",0.9)]),

            seed("youtube-helvetica-doc",
                 title: "Helvetica (2007) — Gary Hustwit",
                 domain: "youtube.com",
                 url: "https://youtube.com/watch?v=wkoX0pEwSCw",
                 summary: "Feature-length documentary exploring the ubiquitous typeface and its cultural impact.",
                 daysAgo: 8,
                 tags: [("documentary","format",0.95),("typography","subject",0.95),("film","domain",0.85),("classic","style",0.8),("neutral","color",0.6)]),

            seed("are-na-visual-systems",
                 title: "Visual Systems + Order — Are.na",
                 domain: "are.na",
                 url: "https://are.na/arjun/visual-systems",
                 summary: "A curated channel exploring grid systems, modular design, and visual order.",
                 daysAgo: 10,
                 tags: [("collection","format",0.85),("grid-systems","subject",0.9),("research","intent",0.9),("systematic","style",0.85)]),

            seed("producthunt-linear",
                 title: "Linear — Issue Tracker for Modern Teams",
                 domain: "producthunt.com",
                 url: "https://producthunt.com/posts/linear",
                 summary: "The fast, focused project management tool used by the best product teams.",
                 daysAgo: 10,
                 tags: [("product-launch","format",0.85),("productivity","subject",0.9),("tool","domain",0.95),("minimal","style",0.8),("energetic","mood",0.7)]),

            seed("letterboxd-2001",
                 title: "2001: A Space Odyssey (1968)",
                 domain: "letterboxd.com",
                 url: "https://letterboxd.com/film/2001-a-space-odyssey",
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
                 url: "https://goodreads.com/book/show/840",
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
                 title: "Introducing v0 by Vercel",
                 domain: "vercel.com",
                 url: "https://vercel.com/blog/introducing-v0-generative-ui",
                 summary: "v0 generates copy-paste-friendly React code from natural language descriptions.",
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
                 url: "https://css-tricks.com/snippets/css/complete-guide-grid",
                 summary: "The definitive reference for CSS Grid — properties for the container and children.",
                 daysAgo: 16,
                 tags: [("reference","format",0.9),("css","tool",0.9),("web","domain",0.85),("layout","subject",0.85),("systematic","style",0.7)]),

            seed("css-tricks-flexbox-gap",
                 title: "The New Flexbox Gap Property",
                 domain: "css-tricks.com",
                 url: "https://css-tricks.com/minding-the-gap",
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
