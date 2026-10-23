import Testing
import Foundation
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

private func buildPage(_ urlString: String, html: String, ogTitle: String? = nil) -> ProductExtraction {
    ProductReader.build(
        sourceURL: URL(string: urlString)!,
        finalURL: nil,
        source: "page",
        html: html,
        ogTitle: ogTitle,
        ogDescription: nil,
        ogImageURL: nil,
        shopify: nil,
        now: Date(timeIntervalSince1970: 1_790_000_000)
    )
}

// MARK: - Classification

@Suite("Product classification")
struct ProductClassificationTests {

    @Test("og:type product → product (page)")
    func ogTypeProduct() {
        let result = classify("https://shop.example.com/item/lamp", ogType: "product")
        #expect(result.kind == .product)
        #expect(result.productSource == "page")
        #expect(classify("https://shop.example.com/item/lamp", ogType: "og:product").kind == .product)
        #expect(classify("https://shop.example.com/item/lamp", ogType: "product.item").kind == .product)
    }

    @Test("Product JSON-LD → product")
    func productJSONLD() {
        let html = """
        <html><head><script type="application/ld+json">
        {"@context":"https://schema.org","@type":"Product","name":"Mag Dock","brand":"Stuffcool"}
        </script></head><body></body></html>
        """
        let result = classify("https://stuffcool.com/item/mag-dock", html: html)
        #expect(result.kind == .product)
        #expect(result.productSource == "page")
    }

    @Test("Shopify /products/ path with a storefront marker → product, incl. under /collections/")
    func shopifyPath() {
        let html = #"<html><head><link rel="preconnect" href="https://cdn.shopify.com"></head><body></body></html>"#
        #expect(classify("https://stuffcool.com/products/mag-dock", html: html).kind == .product)
        #expect(classify("https://stuffcool.com/collections/desk/products/mag-dock?variant=1", html: html).kind == .product)
        #expect(classify("https://store.myshopify.com/products/mag-dock").kind == .product)
    }

    @Test("A /products/ path on a non-Shopify site stays link")
    func saasProductsPathStaysLink() {
        let html = "<html><head><title>Analytics</title></head><body>Our analytics product</body></html>"
        #expect(classify("https://saas.example.com/products/analytics", html: html).kind == .link)
    }

    @Test("Amazon product and Kickstarter project pages → product; other Amazon pages don't")
    func amazonAndKickstarter() {
        #expect(classify("https://www.amazon.in/Umbra-Buddy-Hooks/dp/B00ABC1234").kind == .product)
        #expect(classify("https://www.amazon.co.uk/gp/product/B00ABC1234").kind == .product)
        #expect(classify("https://amzn.to/3xYzAbc").kind == .product)
        #expect(classify("https://www.kickstarter.com/projects/maker/desk-lamp").kind == .product)
        #expect(classify("https://www.amazon.in/").kind == .link)
        #expect(classify("https://amazon.com.evil.net/dp/B00ABC1234").kind == .link)
        #expect(classify("https://www.kickstarter.com/discover").kind == .link)
    }

    @Test("Bare image URL is a product only with the wishlist label")
    func bareImageNeedsWishlist() {
        let url = "https://stuffcool.com/cdn/shop/files/umbra-buddy-wall-hooks-set-of-3-black-3.jpg?v=12"
        let labelled = classify(url, labels: ["Wishlist"])
        #expect(labelled.kind == .product)
        #expect(labelled.productSource == "image")
        #expect(classify(url).kind == .link)
        #expect(classify(url, labels: ["digital-tools"]).kind == .link)
    }

    @Test("Wishlist override: an Instagram post → product only when wishlisted")
    func instagramWishlistOverride() {
        let post = "https://www.instagram.com/reel/C1a2B3c4D5e/"
        let wishlisted = classify(post, labels: ["wishlist"])
        #expect(wishlisted.kind == .product)
        #expect(wishlisted.productSource == "instagram")
        // Not wishlisted: a post stays what it is today, even if the page claims og:type product.
        #expect(classify(post, ogType: "product").kind == .link)
        // A profile isn't a single post.
        #expect(PageClassifier.socialPostHost(for: URL(string: "https://www.instagram.com/stuffcool/")!) == nil)
    }

    @Test("Wishlisted X / Pinterest posts → product (page source)")
    func otherPostHosts() {
        let x = classify("https://x.com/maker/status/1234567890", labels: ["wishlist"])
        #expect(x.kind == .product)
        #expect(x.productSource == "page")
        #expect(classify("https://in.pinterest.com/pin/123456/", labels: ["wishlist"]).kind == .product)
        #expect(PageClassifier.socialPostHost(for: URL(string: "https://dribbble.com/shots/123-lamp")!) == "dribbble")
        #expect(PageClassifier.socialPostHost(for: URL(string: "https://www.behance.net/gallery/1/x")!) == "behance")
    }

    @Test("An article that lists products stays non-product")
    func articleStaysNonProduct() {
        let roundup = """
        <html><head><script type="application/ld+json">
        {"@context":"https://schema.org","@type":"Article","headline":"10 best desk lamps",
         "mainEntity":{"@type":"ItemList","itemListElement":[
           {"@type":"ListItem","position":1,"item":{"@type":"Product","name":"Lamp A"}},
           {"@type":"ListItem","position":2,"item":{"@type":"Product","name":"Lamp B"}}]}}
        </script></head><body></body></html>
        """
        #expect(classify("https://blog.example.com/best-desk-lamps", html: roundup).kind == .link)

        let yoast = """
        <html><head><script type="application/ld+json">
        {"@context":"https://schema.org","@graph":[
          {"@type":"Article","headline":"Review: Lamp A"},
          {"@type":"Product","name":"Lamp A"}]}
        </script></head><body></body></html>
        """
        #expect(classify("https://blog.example.com/lamp-a-review", html: yoast, ogType: "article").kind == .link)
        // A wishlist label on a non-product page is only a hint — the page decides.
        #expect(classify("https://blog.example.com/lamp-a-review", html: yoast, labels: ["wishlist"]).kind == .link)
    }
}

// MARK: - Shopify

@Suite("Product readers: Shopify .json")
struct ShopifyReaderTests {

    private let fixture = """
    {"product":{
      "id":1,"title":"Mag Dock","vendor":"Stuffcool","product_type":"Desk Accessories",
      "handle":"mag-dock","tags":"desk, cables",
      "variants":[{"id":1,"price":"2699.00"},{"id":2,"price":"3199.00"},{"id":3,"price":"2699.00"}],
      "images":[
        {"src":"https://stuffcool.com/cdn/shop/files/1.jpg","width":1200,"height":1200},
        {"src":"//stuffcool.com/cdn/shop/files/2.jpg","width":1200,"height":900},
        {"src":"https://stuffcool.com/cdn/shop/files/3.jpg"},
        {"src":"https://stuffcool.com/cdn/shop/files/4.jpg"},
        {"src":"https://stuffcool.com/cdn/shop/files/5.jpg"},
        {"src":"https://stuffcool.com/cdn/shop/files/6.jpg"},
        {"src":"https://stuffcool.com/cdn/shop/files/7.jpg"},
        {"src":"https://stuffcool.com/cdn/shop/files/8.jpg"},
        {"src":"https://stuffcool.com/cdn/shop/files/9.jpg"},
        {"src":"https://stuffcool.com/cdn/shop/files/10.jpg"}
      ]}}
    """

    @Test(".json URL strips the query and any /collections/ prefix")
    func jsonURL() {
        let url = URL(string: "https://stuffcool.com/collections/desk/products/mag-dock?variant=42")!
        #expect(ProductReader.shopifyJSONURL(for: url)?.absoluteString == "https://stuffcool.com/products/mag-dock.json")
        #expect(ProductReader.shopifyJSONURL(for: URL(string: "https://stuffcool.com/pages/about")!) == nil)
    }

    @Test("Parses title, vendor, product_type, variant prices (range) and images (cap 8)")
    func parsesProduct() throws {
        let product = try #require(ProductReader.parseShopifyProduct(Data(fixture.utf8)))
        #expect(product.title == "Mag Dock")
        #expect(product.vendor == "Stuffcool")
        #expect(product.productType == "Desk Accessories")
        #expect(product.variants?.count == 3)

        let extraction = ProductReader.build(
            sourceURL: URL(string: "https://stuffcool.com/products/mag-dock")!,
            finalURL: nil, source: "page", html: "", ogTitle: "Mag Dock – Stuffcool",
            ogDescription: nil, ogImageURL: nil, shopify: product
        )
        let meta = extraction.meta
        #expect(meta.productName == "Mag Dock")
        #expect(meta.productNameIsGuess == nil)
        #expect(meta.brand?.name == "Stuffcool")
        #expect(meta.category == "Desk Accessories")
        #expect(meta.price == "2699.00")
        #expect(meta.priceMin == "2699.00")
        #expect(meta.priceMax == "3199.00")
        #expect(meta.pricedAt != nil)
        #expect(meta.shop == "stuffcool.com")
        #expect(meta.buyURL == "https://stuffcool.com/products/mag-dock")
        #expect(extraction.imageURLs.count == ProductReader.galleryCap)
        #expect(extraction.imageURLs[1].absoluteString == "https://stuffcool.com/cdn/shop/files/2.jpg")
        #expect(extraction.title == "Mag Dock")
    }

    @Test("A numeric variant price decodes too; malformed JSON returns nil")
    func lenientPrice() throws {
        let json = #"{"product":{"title":"X","variants":[{"price":1999}]}}"#
        let product = try #require(ProductReader.parseShopifyProduct(Data(json.utf8)))
        #expect(product.variants?.first?.price?.value == "1999")
        #expect(ProductReader.parseShopifyProduct(Data("not json".utf8)) == nil)
    }
}

// MARK: - JSON-LD offers

@Suite("Product readers: JSON-LD + og")
struct ProductJSONLDTests {

    private func page(_ jsonLD: String, extraHead: String = "") -> String {
        """
        <html><head>\(extraHead)
        <script type="application/ld+json">\(jsonLD)</script>
        </head><body></body></html>
        """
    }

    @Test("Single Offer: price, currency, availability; brand as object")
    func singleOffer() {
        let html = page("""
        {"@context":"https://schema.org","@type":"Product","name":"Mag Dock","sku":"MD-1",
         "brand":{"@type":"Brand","name":"Stuffcool"},
         "image":["https://stuffcool.com/a.jpg","https://stuffcool.com/b.jpg"],
         "offers":{"@type":"Offer","price":"2699.00","priceCurrency":"inr",
                   "availability":"https://schema.org/InStock"}}
        """)
        let extraction = buildPage("https://stuffcool.com/item/mag-dock", html: html)
        let meta = extraction.meta
        #expect(meta.productName == "Mag Dock")
        #expect(meta.brand?.name == "Stuffcool")
        #expect(meta.price == "2699.00")
        #expect(meta.currency == "INR")
        #expect(meta.availability == "in stock")
        #expect(meta.priceMin == nil)
        #expect(extraction.imageURLs.count == 2)
        #expect(meta.cardKindLine == "₹2,699 · Stuffcool")
    }

    @Test("AggregateOffer: low/high range, brand as string")
    func aggregateOffer() {
        let html = page("""
        {"@type":"Product","name":"Desk Lamp","brand":"Lumen",
         "offers":{"@type":"AggregateOffer","lowPrice":19.5,"highPrice":"29.00","priceCurrency":"USD",
                   "offerCount":3}}
        """)
        let meta = buildPage("https://lumen.example/lamp", html: html).meta
        #expect(meta.brand?.name == "Lumen")
        #expect(meta.price == "19.5")
        #expect(meta.priceMin == "19.5")
        #expect(meta.priceMax == "29.00")
        #expect(meta.currency == "USD")
        #expect(ProductMeta.formattedPrice(meta.price, currency: meta.currency) == "$19.50")
    }

    @Test("Offers as an array, priceSpecification, out-of-stock")
    func offerArray() {
        let html = page("""
        {"@type":"Product","name":"Hooks","brand":[{"@type":"Brand","name":"Umbra"}],
         "offers":[
           {"@type":"Offer","availability":"http://schema.org/OutOfStock",
            "priceSpecification":{"@type":"UnitPriceSpecification","price":1299,"priceCurrency":"INR"}},
           {"@type":"Offer","price":"1499","priceCurrency":"INR"}]}
        """)
        let meta = buildPage("https://umbra.example/hooks", html: html).meta
        #expect(meta.brand?.name == "Umbra")
        #expect(meta.price == "1299")
        #expect(meta.currency == "INR")
        #expect(meta.availability == "out of stock")
    }

    @Test("og price without currency → price kept, currency from JSON-LD when present, else nil")
    func ogCurrencyMissing() {
        let ogOnly = """
        <html><head>
        <meta property="og:type" content="product">
        <meta property="og:site_name" content="Stuffcool">
        <meta property="product:price:amount" content="2,699.00">
        </head><body></body></html>
        """
        let ogMeta = buildPage("https://stuffcool.com/item/x", html: ogOnly, ogTitle: "Mag Dock").meta
        #expect(ogMeta.price == "2699.00")
        #expect(ogMeta.currency == nil)
        #expect(ogMeta.shop == "Stuffcool")
        #expect(ogMeta.productName == "Mag Dock")
        #expect(ogMeta.cardKindLine == "2,699")

        let withJSONLD = page(
            #"{"@type":"Product","name":"Mag Dock","offers":{"@type":"Offer","price":"2699","priceCurrency":"INR"}}"#,
            extraHead: #"<meta property="og:price:amount" content="2699"><meta property="og:price:currency" content="USD">"#
        )
        let merged = buildPage("https://stuffcool.com/item/x", html: withJSONLD).meta
        #expect(merged.currency == "INR")
    }

    @Test("Availability labels and price normalisation")
    func labels() {
        #expect(ProductReader.availabilityLabel("https://schema.org/PreOrder") == "pre-order")
        #expect(ProductReader.availabilityLabel("instock") == "in stock")
        #expect(ProductReader.availabilityLabel("oos") == "out of stock")
        #expect(ProductReader.normalizePrice("Rs. 2,699.00") == "2699.00")
        #expect(ProductReader.normalizePrice("0.00") == nil)
        #expect(ProductReader.normalizePrice("free") == nil)
        #expect(ProductMeta.formattedPrice("2699.00", currency: "INR") == "₹2,699")
        #expect(ProductMeta.formattedPrice("12", currency: "XYZ") == "XYZ 12")
    }
}

// MARK: - Instagram

@Suite("Product readers: Instagram og")
struct InstagramOGTests {

    @Test("og:description carries handle + caption; og:title carries the display name")
    func parsesPost() {
        let info = ProductReader.parseInstagramOG(
            title: #"Stuffcool on Instagram: "Mag Dock keeps every cable in place.""#,
            description: #"1,234 likes, 56 comments - stuffcool on March 3, 2025: "Mag Dock keeps every cable in place.". "#
        )
        #expect(info.handle == "stuffcool")
        #expect(info.displayName == "Stuffcool")
        #expect(info.caption == "Mag Dock keeps every cable in place.")
    }

    @Test("Title alone (with an @handle in parens) still yields name, handle and caption")
    func titleOnly() {
        let info = ProductReader.parseInstagramOG(
            title: "Desk Goods (@deskgoods) on Instagram: \"New lamp drop\"",
            description: nil
        )
        #expect(info.handle == "deskgoods")
        #expect(info.displayName == "Desk Goods")
        #expect(info.caption == "New lamp drop")
    }

    @Test("Instagram product build: creator, caption, original post, 'via @handle' card line")
    func instagramBuild() {
        let extraction = ProductReader.build(
            sourceURL: URL(string: "https://www.instagram.com/reel/C1a2B3c4D5e/")!,
            finalURL: nil,
            source: "instagram",
            html: "",
            ogTitle: #"Stuffcool on Instagram: "Mag Dock""#,
            ogDescription: #"12K likes, 300 comments - stuffcool on May 1, 2025: "Mag Dock""#,
            ogImageURL: URL(string: "https://scontent.cdninstagram.com/v/t51/abc.jpg?oe=1"),
            shopify: nil
        )
        let meta = extraction.meta
        #expect(meta.source == "instagram")
        #expect(meta.creatorHandle == "stuffcool")
        #expect(meta.creator?.name == "Stuffcool")
        #expect(meta.caption == "Mag Dock")
        #expect(meta.originalPostURL == "https://www.instagram.com/reel/C1a2B3c4D5e/")
        #expect(meta.price == nil)
        #expect(meta.cardKindLine == "via @stuffcool")
        #expect(extraction.imageURLs.count == 1)
    }

    @Test("A non-post description yields nothing")
    func nonPost() {
        let info = ProductReader.parseInstagramOG(title: "Instagram", description: "Create an account or log in.")
        #expect(info.handle == nil)
        #expect(info.caption == nil)
    }
}

// MARK: - Bare image filename + guesses

@Suite("Product readers: filename → title + guesses")
struct ProductFilenameTests {

    @Test("Shop CDN filename slug → sentence-case title")
    func filenameTitle() {
        let url = URL(string: "https://stuffcool.com/cdn/shop/files/umbra-buddy-wall-hooks-set-of-3-black-3.jpg?v=1699")!
        #expect(ProductReader.titleFromImageFilename(url) == "Umbra buddy wall hooks set of 3 black")
        #expect(ProductReader.titleFromImageFilename(URL(string: "https://x.com/cdn/shop/files/desk_lamp_1024x1024@2x.png")!) == "Desk lamp")
        #expect(ProductReader.titleFromImageFilename(URL(string: "https://x.com/files/Oak%20Stool-a1b2c3d4e5.webp")!) == "Oak stool")
    }

    @Test("Camera-roll style names give no title")
    func genericFilenames() {
        #expect(ProductReader.titleFromImageFilename(URL(string: "https://x.com/cdn/shop/files/IMG_1234.jpg")!) == nil)
        #expect(ProductReader.titleFromImageFilename(URL(string: "https://x.com/123456.png")!) == nil)
    }

    @Test("Image product build marks the filename title as a guess")
    func imageBuild() {
        let extraction = ProductReader.build(
            sourceURL: URL(string: "https://stuffcool.com/cdn/shop/files/umbra-buddy-wall-hooks-set-of-3-black-3.jpg")!,
            finalURL: nil, source: "image", html: "", ogTitle: nil, ogDescription: nil,
            ogImageURL: nil, shopify: nil
        )
        #expect(extraction.meta.productName == "Umbra buddy wall hooks set of 3 black")
        #expect(extraction.meta.productNameIsGuess == true)
        #expect(extraction.meta.brand == nil)
        #expect(extraction.meta.shop == "stuffcool.com")
        #expect(extraction.imageURLs.count == 1)
    }

    @Test("Rule-based guess: filename → name, never a brand; captions aren't parsed")
    func ruleGuess() {
        let fromFile = ProductReader.ruleBasedGuess(caption: nil, filename: "umbra-buddy-wall-hooks-set-of-3-black-3.jpg")
        #expect(fromFile.productName == "Umbra buddy wall hooks set of 3 black")
        #expect(fromFile.brand == nil)
        #expect(ProductReader.ruleBasedGuess(caption: "Love this lamp", filename: nil) == ProductGuess())
    }

    @Test("A guess never replaces a read name; it does replace an earlier guess")
    func applyGuess() {
        var read = ProductMeta()
        read.productName = "Mag Dock"
        ProductReader.applyGuess(ProductGuess(productName: "Dock", brand: "Stuffcool"), to: &read)
        #expect(read.productName == "Mag Dock")
        #expect(read.productNameIsGuess == nil)
        #expect(read.brand?.name == "Stuffcool")
        #expect(read.brandIsGuess == true)

        var guessed = ProductMeta()
        guessed.productName = "Old guess"
        guessed.productNameIsGuess = true
        ProductReader.applyGuess(ProductGuess(productName: "Better guess", brand: nil), to: &guessed)
        #expect(guessed.productName == "Better guess")
    }

    @Test("Fallback enricher guess runs end to end on an image product")
    @MainActor
    func fallbackGuessOnItem() async {
        var meta = ProductMeta()
        meta.source = "image"
        let item = Item(
            title: "Untitled",
            sourceURL: "https://stuffcool.com/cdn/shop/files/umbra-buddy-wall-hooks-set-of-3-black-3.jpg",
            kind: ItemKind.product.rawValue
        )
        item.setMetadata(meta)

        await EnrichmentService.applyProductGuessIfNeeded(item: item, enricher: RuleBasedFallbackEnricher())

        #expect(item.productMeta()?.productName == "Umbra buddy wall hooks set of 3 black")
        #expect(item.productMeta()?.productNameIsGuess == true)
    }
}

// MARK: - Search

@Suite("Product search blob")
struct ProductSearchTests {

    @Test("Search hits product name, brand and shop")
    @MainActor
    func searchProductMeta() {
        var meta = ProductMeta()
        meta.productName = "Mag Dock"
        meta.brand = ProductReader.brandRef("Stuffcool")
        meta.shop = "Stuffcool Store"
        let item = Item(title: "Saved thing", kind: ItemKind.product.rawValue)
        item.setMetadata(meta)

        #expect(ItemFilter.apply([item], searchText: "mag dock", selectedTagNames: []).count == 1)
        #expect(ItemFilter.apply([item], searchText: "stuffcool", selectedTagNames: []).count == 1)
        #expect(ItemFilter.apply([item], searchText: "stuffcool store", selectedTagNames: []).count == 1)
        #expect(item.cardKindLine == "Stuffcool")
        #expect(item.hasRichTypedPanel)
    }
}
