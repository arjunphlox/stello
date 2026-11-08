import Testing
import Foundation
@testable import Stello

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

    @Test("Price formatting: symbol for a known currency, code otherwise")
    func formattedPrice() {
        #expect(ProductMeta.formattedPrice("2699.00", currency: "INR") == "₹2,699")
        #expect(ProductMeta.formattedPrice("12", currency: "XYZ") == "XYZ 12")
    }

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
