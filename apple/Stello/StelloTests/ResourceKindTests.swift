import Testing
import Foundation
import SwiftData
@testable import Stello

// MARK: - Helpers

private func classify(
    _ urlString: String,
    html: String = "<html><head></head><body></body></html>",
    ogType: String? = nil,
    labels: [String] = []
) -> PageClassificationResult {
    let url = URL(string: urlString)!
    return PageClassifier.classify(
        html: html,
        baseURL: url,
        domain: url.host,
        title: "Some page",
        ogDescription: nil,
        ogType: ogType,
        collectionLabels: labels
    )
}

private func jsonLD(_ body: String) -> String {
    """
    <html><head><script type="application/ld+json">
    \(body)
    </script></head><body></body></html>
    """
}

private func buildResource(
    _ urlString: String,
    finalURL: String? = nil,
    html: String = "",
    ogTitle: String? = nil,
    labels: [String] = []
) -> ResourceExtraction {
    ResourceReader.build(
        sourceURL: URL(string: urlString)!,
        finalURL: finalURL.flatMap { URL(string: $0) },
        html: html,
        ogTitle: ogTitle,
        collectionLabels: labels
    )
}

private func isSingleBook(_ urlString: String, html: String = "") -> Bool {
    PageClassifier.isSingleBook(url: URL(string: urlString)!, html: html)
}

// MARK: - Fixtures

private let figmaPluginURL = "https://www.figma.com/community/plugin/735098390272716381/iconify"
private let framerTemplateURL = "https://www.framer.com/marketplace/templates/portfolio-pro/"

private let figmaCreativeWorkJSONLD = #"""
{"@context":"https://schema.org","@type":"CreativeWork","name":"Iconify",
 "creator":[{"@type":"Person","name":"Vjacheslav Trushkin","url":"https://www.figma.com/@cyberalien"}],
 "interactionStatistic":[
   {"@type":"InteractionCounter","interactionType":"https://schema.org/UseAction","userInteractionCount":124000},
   {"@type":"InteractionCounter","interactionType":{"@type":"LikeAction"},"userInteractionCount":"3,210"}
 ]}
"""#

private let framerFreeProductJSONLD = #"""
{"@context":"https://schema.org","@type":"Product","name":"Portfolio Pro",
 "brand":{"@type":"Brand","name":"Studio Nine","url":"https://www.framer.com/@studio-nine/"},
 "offers":{"@type":"Offer","price":"0","priceCurrency":"USD"}}
"""#

private let framerPaidProductJSONLD = #"""
{"@context":"https://schema.org","@type":"Product","name":"Agency X",
 "brand":{"@type":"Brand","name":"Nine Studio"},
 "offers":{"@type":"Offer","price":"49","priceCurrency":"USD"}}
"""#

// MARK: - Classification

@Suite("Resource classification")
struct ResourceClassificationTests {

    @Test("Figma Community plugin / widget / file URLs → resource")
    func figmaCommunity() {
        for url in [
            figmaPluginURL,
            "https://www.figma.com/community/plugin/735098390272716381",
            "https://www.figma.com/community/widget/1009867213296787406/voting-table",
            "https://www.figma.com/community/file/1035203688168086460/material-3-design-kit",
            "https://figma.com/community/file/1035203688168086460",
            "https://www.figma.com/@cyberalien/plugin/735098390272716381/iconify",
        ] {
            #expect(classify(url).kind == .resource, "\(url)")
        }
        #expect(PageClassifier.figmaCommunityResourceType(from: URL(string: figmaPluginURL)!) == "plugin")
    }

    @Test("Figma Community home, search, listings, profiles and design files are not resources")
    func figmaNonResources() {
        for url in [
            "https://www.figma.com/community",
            "https://www.figma.com/community/",
            "https://www.figma.com/community/search?resource_type=plugins&q=icons",
            "https://www.figma.com/community/plugins",
            "https://www.figma.com/community/plugin",
            "https://www.figma.com/@cyberalien",
            "https://www.figma.com/design/abc123/My-File",
            "https://www.figma.com/",
        ] {
            #expect(classify(url).kind != .resource, "\(url)")
        }
    }

    @Test("A Figma plugin wins over tool signals (SoftwareApplication JSON-LD, tool labels)")
    func figmaBeatsTool() {
        let app = jsonLD(#"{"@context":"https://schema.org","@type":"SoftwareApplication","name":"Iconify"}"#)
        #expect(classify(figmaPluginURL, html: app).kind == .resource)
        #expect(classify(figmaPluginURL, labels: ["digital-tools"]).kind == .resource)
    }

    @Test("Framer Marketplace template with Product JSON-LD + offers → resource, not product")
    func framerTemplate() {
        let html = jsonLD(framerFreeProductJSONLD)
        // The Product rule alone would claim it…
        #expect(PageClassifier.productSource(
            url: URL(string: framerTemplateURL)!, ogType: nil, html: html, collectionLabels: []
        ) == "page")
        // …but resource runs first.
        #expect(classify(framerTemplateURL, html: html).kind == .resource)
        #expect(classify(framerTemplateURL, html: html, ogType: "product").kind == .resource)
        #expect(classify("https://www.framer.com/marketplace/plugins/lottie/").kind == .resource)
        #expect(classify("https://framer.com/marketplace/components/marquee").kind == .resource)
        #expect(classify("https://www.framer.com/marketplace/vectors/phosphor-icons/").kind == .resource)
    }

    @Test("Framer Marketplace home, type listings, categories and creator pages are not resources")
    func framerNonResources() {
        for url in [
            "https://www.framer.com/marketplace/",
            "https://www.framer.com/marketplace/templates/",
            "https://www.framer.com/marketplace/templates/category/portfolio/",
            "https://www.framer.com/marketplace/creators/studio-nine/",
            "https://www.framer.com/templates/portfolio-pro/",
            "https://www.framer.com/",
        ] {
            #expect(classify(url).kind != .resource, "\(url)")
            #expect(PageClassifier.framerMarketplaceSegment(from: URL(string: url)!) == nil, "\(url)")
        }
    }

    @Test("CodePen pen → resource; profiles and the home page are not")
    func codepen() {
        #expect(classify("https://codepen.io/jane/pen/abcXYZ").kind == .resource)
        #expect(classify("https://codepen.io/jane/full/abcXYZ").kind == .resource)
        #expect(classify("https://codepen.io/jane").kind != .resource)
        #expect(classify("https://codepen.io/").kind != .resource)
        #expect(classify("https://codepen.io/jane/pens/popular").kind != .resource)
    }

    @Test("digital-resources label on a plain page → resource")
    func digitalResourcesLabel() {
        #expect(classify("https://lucide.dev/", labels: ["digital-resources"]).kind == .resource)
        #expect(classify("https://lucide.dev/", labels: ["Digital Resources"]).kind == .resource)
        #expect(classify("https://lucide.dev/", labels: ["digital_resources"]).kind == .resource)
        // A bare image file is never a resource by label.
        #expect(classify("https://cdn.example.com/kit.png", labels: ["digital-resources"]).kind != .resource)
    }

    @Test("digital-resources label + article → not a resource")
    func digitalResourcesArticle() {
        #expect(classify(
            "https://blog.example.com/best-icon-sets", ogType: "article", labels: ["digital-resources"]
        ).kind == .link)
        for type in ["Article", "BlogPosting", "NewsArticle"] {
            let html = jsonLD(#"{"@context":"https://schema.org","@type":"\#(type)","headline":"20 UI kits"}"#)
            #expect(classify(
                "https://blog.example.com/ui-kits", html: html, labels: ["digital-resources"]
            ).kind != .resource, "\(type)")
        }
    }

    @Test("digital-resources label beats a Product JSON-LD node and a tool label")
    func digitalResourcesBeatsProductAndTool() {
        let html = jsonLD(framerPaidProductJSONLD)
        #expect(classify("https://ui8.net/nine/products/agency-x", html: html, labels: ["digital-resources"]).kind == .resource)
        #expect(classify("https://lucide.dev/", labels: ["digital-resources", "digital-tools"]).kind == .resource)
    }

    @Test("books label on a list page → resource (reading list)")
    func booksReadingList() {
        let result = classify("https://fs.blog/reading-list/", labels: ["books"])
        #expect(result.kind == .resource)
        let extraction = buildResource(
            "https://fs.blog/reading-list/", ogTitle: "The Great Books Reading List", labels: ["books"]
        )
        #expect(extraction.meta.subtype == "reading list")
        #expect(extraction.meta.worksWith.isEmpty)
        #expect(extraction.meta.cardKindLine == "Reading list")
    }

    @Test("books label on a single book is left to the existing rules")
    func booksSingleBook() {
        // Amazon ISBN-10 page: product, as before.
        #expect(classify("https://www.amazon.com/dp/0760383383", labels: ["books"]).kind == .product)
        #expect(classify("https://www.amazon.in/Some-Title/dp/0760383383", labels: ["books"]).kind != .resource)
        // Goodreads / Open Library / StoryGraph / Book JSON-LD / book:isbn: not a reading list.
        #expect(classify("https://www.goodreads.com/book/show/40121378-atomic-habits", labels: ["books"]).kind != .resource)
        #expect(classify("https://openlibrary.org/works/OL17930368W", labels: ["books"]).kind != .resource)
        #expect(classify("https://app.thestorygraph.com/books/0a1b2c3d", labels: ["books"]).kind != .resource)
        let book = jsonLD(#"{"@context":"https://schema.org","@type":"Book","name":"Atomic Habits","isbn":"0735211299"}"#)
        #expect(classify("https://jamesclear.com/atomic-habits", html: book, labels: ["books"]).kind != .resource)
        let isbn = #"<html><head><meta property="book:isbn" content="9780735211292"></head></html>"#
        #expect(classify("https://example.com/atomic-habits", html: isbn, labels: ["books"]).kind != .resource)
    }

    @Test("Amazon /dp/B0… stays a product — with the wishlist label, and even with the books label")
    func amazonStaysProduct() {
        let url = "https://www.amazon.com/Stuffcool-Mag-Dock/dp/B0CHX1W1XY"
        #expect(classify(url, labels: ["wishlist"]).kind == .product)
        #expect(classify(url, labels: ["wishlist", "books"]).kind == .product)
        #expect(classify(url, labels: ["books"]).kind == .product)
        #expect(classify(url, labels: ["wishlist", "digital-resources"]).kind == .product)
    }

    @Test("A tweet with a digital-resources label stays a post")
    func tweetStaysPost() {
        let result = classify("https://x.com/janedoe/status/1453768926539317251", labels: ["digital-resources"])
        #expect(result.kind == .post)
        #expect(result.postPlatform == "x")
    }

    @Test("isSingleBook cases")
    func singleBook() {
        #expect(isSingleBook("https://www.amazon.com/dp/0760383383"))
        #expect(isSingleBook("https://www.amazon.com/Some-Book/dp/076038338X"))
        #expect(isSingleBook("https://www.amazon.co.uk/gp/product/076038338x"))
        #expect(!isSingleBook("https://www.amazon.com/dp/B0CHX1W1XY"))
        #expect(!isSingleBook("https://www.amazon.com/dp/07603833"))
        #expect(isSingleBook("https://www.goodreads.com/book/show/40121378-atomic-habits"))
        #expect(!isSingleBook("https://www.goodreads.com/list/show/1.Best_Books_Ever"))
        #expect(isSingleBook("https://openlibrary.org/books/OL26331930M"))
        #expect(isSingleBook("https://openlibrary.org/works/OL17930368W"))
        #expect(!isSingleBook("https://openlibrary.org/authors/OL1A"))
        #expect(isSingleBook("https://app.thestorygraph.com/books/0a1b2c3d"))
        #expect(isSingleBook(
            "https://example.com/x",
            html: jsonLD(#"{"@context":"https://schema.org","@type":"Book","name":"Atomic Habits"}"#)
        ))
        #expect(isSingleBook(
            "https://example.com/x",
            html: #"<html><head><meta property="book:isbn" content="9780735211292"></head></html>"#
        ))
        #expect(!isSingleBook("https://fs.blog/reading-list/"))
        #expect(PageClassifier.isISBN10("0760383383"))
        #expect(PageClassifier.isISBN10("076038338X"))
        #expect(!PageClassifier.isISBN10("B0CHX1W1XY"))
    }
}

// MARK: - Readers

@Suite("Resource readers")
struct ResourceReaderTests {

    @Test("Figma CreativeWork JSON-LD: name, creator with url, users + likes")
    func figmaCreativeWork() {
        let extraction = buildResource(
            figmaPluginURL, html: jsonLD(figmaCreativeWorkJSONLD), ogTitle: "Iconify | Figma"
        )
        let meta = extraction.meta
        #expect(meta.name == "Iconify")
        #expect(extraction.title == "Iconify")
        #expect(meta.maker?.name == "Vjacheslav Trushkin")
        #expect(meta.maker?.url == "https://www.figma.com/@cyberalien")
        #expect(meta.users == 124_000)
        #expect(meta.likes == 3_210)
        #expect(meta.subtype == "plugin")
        #expect(meta.worksWith == ["Figma"])
        #expect(meta.pricing == nil)
        #expect(meta.cardKindLine == "Figma plugin · 124k users")
    }

    @Test("Interaction statistic shapes: single counter, legacy UserLikes, string counts")
    func interactionShapes() {
        let single: [String: Any] = [
            "@type": "InteractionCounter",
            "interactionType": "http://schema.org/DownloadAction",
            "userInteractionCount": "12.4k",
        ]
        #expect(ResourceReader.interactionCounts(from: single).users == 12_400)
        let legacy: [Any] = [
            ["@type": "UserLikes", "userInteractionCount": 42] as [String: Any],
            ["@type": "InteractionCounter", "interactionType": "UserInteraction", "userInteractionCount": 7] as [String: Any],
        ]
        let counts = ResourceReader.interactionCounts(from: legacy)
        #expect(counts.likes == 42)
        #expect(counts.users == nil)
        #expect(ResourceReader.interactionCounts(from: nil).users == nil)
    }

    @Test("Framer Product JSON-LD: brand as maker, offers price 0 → free")
    func framerFree() {
        let extraction = buildResource(
            framerTemplateURL, html: jsonLD(framerFreeProductJSONLD),
            ogTitle: "Portfolio Pro — Free Website Template for Framer"
        )
        let meta = extraction.meta
        #expect(meta.name == "Portfolio Pro")
        #expect(meta.maker?.name == "Studio Nine")
        #expect(meta.maker?.url == "https://www.framer.com/@studio-nine/")
        #expect(meta.pricing == "free")
        #expect(meta.price == nil)
        #expect(meta.subtype == "template")
        #expect(meta.worksWith == ["Framer"])
        #expect(meta.cardKindLine == "Framer template · Free")
    }

    @Test("Framer paid template: price + currency")
    func framerPaid() {
        let meta = buildResource(framerTemplateURL, html: jsonLD(framerPaidProductJSONLD)).meta
        #expect(meta.pricing == "paid")
        #expect(meta.price == "49")
        #expect(meta.currency == "USD")
        #expect(meta.cardKindLine == "Framer template · $49")
    }

    @Test("og:title suffix stripping (no JSON-LD); 'Free' in the title → free")
    func ogTitleStripping() {
        #expect(ResourceReader.strippedName("Iconify | Figma") == "Iconify")
        #expect(ResourceReader.strippedName("Material 3 Design Kit | Figma Community") == "Material 3 Design Kit")
        #expect(ResourceReader.strippedName("Portfolio — Free Website Template for Framer") == "Portfolio")
        #expect(ResourceReader.strippedName("Marquee - Framer Marketplace") == "Marquee")
        #expect(ResourceReader.strippedName("Nova – UI Kit for Framer | Framer Marketplace") == "Nova")
        #expect(ResourceReader.strippedName("CodePen - Wavy text") == "Wavy text")
        #expect(ResourceReader.strippedName("Plain name") == "Plain name")
        #expect(ResourceReader.strippedName("| Figma") == "| Figma")

        let meta = buildResource(
            "https://www.framer.com/marketplace/templates/portfolio/",
            ogTitle: "Portfolio — Free Website Template for Framer"
        ).meta
        #expect(meta.name == "Portfolio")
        #expect(meta.pricing == "free")
    }

    @Test("Canonical URL: set when the final URL differs at all (Figma's longer slug), else nil")
    func canonical() {
        let short = "https://www.figma.com/community/plugin/735098390272716381"
        let redirected = buildResource(short, finalURL: figmaPluginURL).meta
        #expect(redirected.canonicalURL == figmaPluginURL)
        #expect(buildResource(figmaPluginURL, finalURL: figmaPluginURL).meta.canonicalURL == nil)
        #expect(buildResource(figmaPluginURL).meta.canonicalURL == nil)
    }

    @Test("Subtypes: path, CodePen, FigJam, title words, site home page")
    func subtypes() {
        #expect(buildResource("https://www.figma.com/community/widget/1/voting").meta.subtype == "widget")
        #expect(buildResource("https://www.figma.com/community/file/1/kit").meta.subtype == "file")
        let figjam = buildResource("https://www.figma.com/community/file/1/retro", ogTitle: "Retro board (FigJam) | Figma").meta
        #expect(figjam.worksWith == ["FigJam"])
        #expect(figjam.cardKindLine == "FigJam file")
        let pen = buildResource("https://codepen.io/jane/pen/abcXYZ", ogTitle: "Wavy text").meta
        #expect(pen.subtype == "pen")
        #expect(pen.worksWith == ["CodePen"])
        #expect(buildResource("https://www.framer.com/marketplace/components/marquee/").meta.subtype == "component")
        #expect(buildResource("https://www.framer.com/marketplace/plugins/lottie/").meta.subtype == "plugin")
        #expect(buildResource("https://ls.graphics/mockups/iphone", ogTitle: "iPhone 17 Mockup").meta.subtype == "mockup")
        #expect(buildResource("https://phosphoricons.com/x", ogTitle: "Phosphor Icons").meta.subtype == "icon set")
        #expect(buildResource("https://ui8.net/x/y", ogTitle: "Nova UI Kit").meta.subtype == "file")
        #expect(buildResource("https://lucide.dev/").meta.subtype == "library")
        #expect(buildResource("https://example.com/some/page", ogTitle: "Something").meta.subtype == nil)
    }

    @Test("Kind line variants")
    func kindLine() {
        var meta = ResourceMeta()
        #expect(meta.cardKindLine == nil)
        meta.subtype = "plugin"
        meta.worksWith = ["Figma"]
        #expect(meta.cardKindLine == "Figma plugin")
        meta.pricing = "free"
        #expect(meta.cardKindLine == "Figma plugin · Free")
        meta.pricing = nil
        meta.users = 12_400
        #expect(meta.cardKindLine == "Figma plugin · 12.4k users")
        meta.users = 1
        #expect(meta.cardKindLine == "Figma plugin · 1 user")

        var paid = ResourceMeta()
        paid.subtype = "template"
        paid.worksWith = ["Framer"]
        paid.pricing = "paid"
        #expect(paid.cardKindLine == "Framer template · Paid")
        paid.price = "49"
        paid.currency = "USD"
        paid.users = 900
        #expect(paid.cardKindLine == "Framer template · $49")

        var reading = ResourceMeta()
        reading.subtype = "reading list"
        #expect(reading.cardKindLine == "Reading list")

        var library = ResourceMeta()
        library.subtype = "library"
        #expect(library.cardKindLine == "Library")
    }

    @Test("A refetch that reads less never erases what capture read")
    func merge() {
        var previous = ResourceMeta()
        previous.name = "Iconify"
        previous.maker = ToolReader.makerRef("Vjacheslav")
        previous.users = 100
        previous.subtype = "plugin"
        previous.worksWith = ["Figma"]
        var fresh = ResourceMeta()
        fresh.likes = 5
        let merged = ResourceReader.merge(fresh: fresh, previous: previous)
        #expect(merged.name == "Iconify")
        #expect(merged.maker?.name == "Vjacheslav")
        #expect(merged.users == 100)
        #expect(merged.likes == 5)
        #expect(merged.subtype == "plugin")
        #expect(merged.worksWith == ["Figma"])
    }
}

// MARK: - Item level + refresh

@Suite("Resource items")
struct ResourceItemTests {

    @Test("Item kind line, typed panel, domain pill and search")
    @MainActor
    func itemLevel() {
        var meta = ResourceMeta()
        meta.subtype = "plugin"
        meta.worksWith = ["Figma"]
        meta.name = "Iconify"
        meta.maker = ToolReader.makerRef("Vjacheslav Trushkin")
        meta.pricing = "free"
        meta.canonicalURL = figmaPluginURL
        let item = Item(
            title: "Saved thing", sourceURL: "https://www.figma.com/community/plugin/735098390272716381",
            domain: "figma.com", kind: ItemKind.resource.rawValue
        )
        item.setMetadata(meta)

        #expect(item.resourceMeta() != nil)
        #expect(item.toolMeta() == nil)
        #expect(item.cardKindLine == "Figma plugin · Free")
        #expect(item.hasRichTypedPanel)
        #expect(item.displayLink == "figma.com")
        for query in ["iconify", "vjacheslav trushkin", "plugin", "figma"] {
            #expect(ItemFilter.apply([item], searchText: query, selectedTagNames: []).count == 1, "\(query)")
        }
    }

    @Test("Old JSON without the EntityRef url still decodes")
    @MainActor
    func entityRefBackCompat() throws {
        let json = #"{"name":"Studio","kind":"maker"}"#
        let ref = try JSONDecoder().decode(EntityRef.self, from: Data(json.utf8))
        #expect(ref.name == "Studio")
        #expect(ref.url == nil)
    }

    @Test("Refresh flips a Framer Marketplace product and a Figma Community tool to resource")
    @MainActor
    func refreshMigrations() async throws {
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)

        let product = Item(title: "Portfolio Pro", sourceURL: framerTemplateURL, kind: ItemKind.product.rawValue)
        let tool = Item(title: "Iconify", sourceURL: figmaPluginURL, kind: ItemKind.tool.rawValue)
        let website = Item(title: "Iconify", sourceURL: figmaPluginURL, kind: ItemKind.website.rawValue)
        let shopProduct = Item(title: "Mag Dock", sourceURL: "https://stuffcool.com/products/mag-dock", kind: ItemKind.product.rawValue)
        for item in [product, tool, website, shopProduct] { context.insert(item) }
        try context.save()

        let framerPage = PageFetchResult(
            html: jsonLD(framerFreeProductJSONLD),
            og: OGResult(title: "Portfolio Pro — Free Website Template for Framer"),
            statusCode: 200
        )
        let flippedProduct = await EnrichmentService.refreshResourceIfClassified(
            item: product, context: context, url: URL(string: framerTemplateURL)!, page: framerPage
        )
        #expect(flippedProduct)
        #expect(product.kind == ItemKind.resource.rawValue)
        #expect(product.resourceMeta()?.pricing == "free")

        let figmaPage = PageFetchResult(
            html: jsonLD(figmaCreativeWorkJSONLD), og: OGResult(title: "Iconify | Figma"), statusCode: 200
        )
        #expect(await EnrichmentService.refreshResourceIfClassified(
            item: tool, context: context, url: URL(string: figmaPluginURL)!, page: figmaPage
        ))
        #expect(tool.kind == ItemKind.resource.rawValue)
        #expect(tool.resourceMeta()?.users == 124_000)

        // Curated kinds are never flipped; a product off the marketplace stays a product.
        #expect(await EnrichmentService.refreshResourceIfClassified(
            item: website, context: context, url: URL(string: figmaPluginURL)!, page: figmaPage
        ) == false)
        #expect(website.kind == ItemKind.website.rawValue)
        let shopPage = PageFetchResult(html: jsonLD(framerPaidProductJSONLD), og: OGResult(), statusCode: 200)
        #expect(await EnrichmentService.refreshResourceIfClassified(
            item: shopProduct, context: context,
            url: URL(string: "https://stuffcool.com/products/mag-dock")!, page: shopPage
        ) == false)
        #expect(shopProduct.kind == ItemKind.product.rawValue)
    }
}
