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

private func buildTool(
    _ urlString: String,
    finalURL: String? = nil,
    html: String = "",
    ogDescription: String? = nil,
    github: ToolReader.GitHubRepo? = nil
) -> ToolExtraction {
    ToolReader.build(
        sourceURL: URL(string: urlString)!,
        finalURL: finalURL.flatMap { URL(string: $0) },
        html: html,
        ogDescription: ogDescription,
        github: github
    )
}

// MARK: - Fixtures

private let softwareAppJSONLD = #"""
{"@context":"https://schema.org","@type":"SoftwareApplication","name":"Things 3",
 "operatingSystem":"macOS","applicationCategory":"ProductivityApplication",
 "offers":{"@type":"Offer","price":"49.99","priceCurrency":"USD"},
 "author":{"@type":"Organization","name":"Cultured Code"}}
"""#

private let githubRepoJSON = #"""
{"id":1,"name":"ripgrep","full_name":"BurntSushi/ripgrep",
 "owner":{"login":"BurntSushi","id":2},
 "html_url":"https://github.com/BurntSushi/ripgrep",
 "description":"ripgrep recursively searches directories for a regex pattern",
 "homepage":"https://burntsushi.net/ripgrep/",
 "stargazers_count":48211,"language":"Rust",
 "license":{"key":"unlicense","name":"The Unlicense","spdx_id":"Unlicense"},
 "pushed_at":"2026-09-30T14:02:11Z",
 "topics":["cli","search","regex"],"archived":false}
"""#

private let githubNoLicenseJSON = #"""
{"name":"dotfiles","full_name":"jane/dotfiles","owner":{"login":"jane"},
 "html_url":"https://github.com/jane/dotfiles","stargazers_count":12,"language":"Shell",
 "license":null,"pushed_at":"2025-01-02T03:04:05Z","topics":[]}
"""#

// MARK: - Classification

@Suite("Tool classification")
struct ToolClassificationTests {

    @Test("SoftwareApplication / WebApplication / MobileApplication JSON-LD → tool")
    func softwareJSONLD() {
        #expect(classify("https://culturedcode.com/things/", html: jsonLD(softwareAppJSONLD)).kind == .tool)
        let web = jsonLD(#"{"@context":"https://schema.org","@type":"WebApplication","name":"Figma"}"#)
        #expect(classify("https://www.figma.com/", html: web).kind == .tool)
        let mobile = jsonLD(#"{"@context":"https://schema.org","@type":"MobileApplication","name":"Halide"}"#)
        #expect(classify("https://halide.cam/", html: mobile).kind == .tool)
        let graph = jsonLD(#"{"@context":"https://schema.org","@graph":[{"@type":"WebSite","name":"Linear"},{"@type":"WebApplication","name":"Linear"}]}"#)
        #expect(classify("https://linear.app/", html: graph).kind == .tool)
    }

    @Test("App Store URLs → tool")
    func appStore() {
        #expect(classify("https://apps.apple.com/us/app/things-3/id904237743").kind == .tool)
        #expect(classify("https://apps.apple.com/app/id904237743").kind == .tool)
        #expect(classify("https://itunes.apple.com/us/app/things-3/id904237743?mt=12").kind == .tool)
        #expect(classify("macappstore://apps.apple.com/app/id904280696").kind == .tool)
        #expect(PageClassifier.isMacAppStoreURL(URL(string: "https://apps.apple.com/us/app/things-3/id904280696?mt=12")!))
        #expect(PageClassifier.isMacAppStoreURL(URL(string: "https://apps.apple.com/us/app/things-3/id904237743")!) == false)
        // Not an app page.
        #expect(classify("https://apps.apple.com/us/charts").kind != .tool)
        #expect(classify("https://music.apple.com/us/album/x/1").kind != .tool)
    }

    @Test("GitHub repo root and repo subpages → tool")
    func githubRepos() {
        for url in [
            "https://github.com/BurntSushi/ripgrep",
            "https://github.com/BurntSushi/ripgrep/",
            "https://www.github.com/BurntSushi/ripgrep",
            "https://github.com/BurntSushi/ripgrep/releases",
            "https://github.com/BurntSushi/ripgrep/blob/master/README.md",
            "https://github.com/BurntSushi/ripgrep.git",
        ] {
            #expect(classify(url).kind == .tool, "\(url)")
        }
        let repo = PageClassifier.githubRepo(from: URL(string: "https://github.com/BurntSushi/ripgrep.git")!)
        #expect(repo?.owner == "BurntSushi")
        #expect(repo?.repo == "ripgrep")
    }

    @Test("GitHub profiles, site pages and gists are not tools")
    func githubNonRepos() {
        for url in [
            "https://github.com/BurntSushi",
            "https://github.com/",
            "https://github.com/topics/cli",
            "https://github.com/orgs/vercel/repositories",
            "https://github.com/features/copilot",
            "https://github.com/marketplace/actions/checkout",
            "https://github.com/settings/profile",
            "https://github.com/about/careers",
            "https://github.com/pricing/plans",
            "https://github.com/collections/clean-code-linters",
            "https://github.com/sponsors/BurntSushi",
            "https://gist.github.com/jane/0123456789abcdef",
        ] {
            #expect(classify(url).kind != .tool, "\(url)")
            #expect(PageClassifier.githubRepo(from: URL(string: url)!) == nil, "\(url)")
        }
    }

    @Test("A digital-tools / digital-productivity / gen-ai label on a plain page → tool")
    func labels() {
        #expect(classify("https://raycast.com/", labels: ["digital-tools"]).kind == .tool)
        #expect(classify("https://raycast.com/", labels: ["Digital Productivity"]).kind == .tool)
        #expect(classify("https://runwayml.com/", labels: ["gen-ai"]).kind == .tool)
        #expect(classify("https://runwayml.com/", labels: ["Gen AI"]).kind == .tool)
        #expect(classify("https://raycast.com/", labels: ["typography"]).kind == .link)
        // A bare image file is never a tool.
        #expect(classify("https://cdn.example.com/screenshot.png", labels: ["digital-tools"]).kind == .link)
    }

    @Test("gen-ai label + og:type article → not a tool")
    func genAIArticleOG() {
        let result = classify("https://blog.example.com/what-is-diffusion", ogType: "article", labels: ["gen-ai"])
        #expect(result.kind != .tool)
        #expect(result.kind == .link)
    }

    @Test("gen-ai label + Article / BlogPosting / NewsArticle JSON-LD → not a tool")
    func genAIArticleJSONLD() {
        for type in ["Article", "BlogPosting", "NewsArticle"] {
            let html = jsonLD(#"{"@context":"https://schema.org","@type":"\#(type)","headline":"10 AI tools"}"#)
            #expect(classify("https://news.example.com/ai-tools", html: html, labels: ["gen-ai"]).kind != .tool, "\(type)")
            #expect(classify("https://news.example.com/ai-tools", html: html, labels: ["digital-tools"]).kind != .tool, "\(type)")
        }
        // Yoast puts the Article in @graph — still an article.
        let yoast = jsonLD(#"{"@context":"https://schema.org","@graph":[{"@type":"Article","headline":"x"},{"@type":"WebPage"}]}"#)
        #expect(classify("https://blog.example.com/x", html: yoast, labels: ["gen-ai"]).kind != .tool)
    }

    @Test("Article override beats a SoftwareApplication node, but never a repo or an App Store URL")
    func articleOverride() {
        let review = jsonLD(#"""
        [{"@context":"https://schema.org","@type":"Article","headline":"Review: Things 3"},
         {"@context":"https://schema.org","@type":"SoftwareApplication","name":"Things 3"}]
        """#)
        #expect(classify("https://blog.example.com/things-review", html: review).kind != .tool)
        #expect(classify("https://blog.example.com/things-review", html: jsonLD(softwareAppJSONLD), ogType: "article").kind != .tool)
        // GitHub sets og:type object; a stray article node must not override a repo.
        #expect(classify("https://github.com/BurntSushi/ripgrep", html: review, ogType: "article").kind == .tool)
        #expect(classify("https://apps.apple.com/us/app/things-3/id904237743", html: review, ogType: "article").kind == .tool)
    }

    @Test("A tweet with a gen-ai label stays a post")
    func tweetStaysPost() {
        let result = classify("https://x.com/janedoe/status/1453768926539317251", labels: ["gen-ai"])
        #expect(result.kind == .post)
        #expect(result.postPlatform == "x")
    }

    @Test("A wishlisted Shopify product stays a product, even with a tool label")
    func shopifyStaysProduct() {
        let html = #"<html><head><link rel="preconnect" href="https://cdn.shopify.com"></head><body></body></html>"#
        let result = classify("https://stuffcool.com/products/mag-dock", html: html, labels: ["wishlist", "digital-tools"])
        #expect(result.kind == .product)
        #expect(result.productSource == "page")
    }
}

// MARK: - JSON-LD reader

@Suite("Tool readers: JSON-LD")
struct ToolJSONLDReaderTests {

    @Test("SoftwareApplication: name, platform, category, paid price, maker")
    func softwareApplication() {
        let extraction = buildTool("https://culturedcode.com/things/", html: jsonLD(softwareAppJSONLD))
        let meta = extraction.meta
        #expect(meta.name == "Things 3")
        #expect(extraction.title == "Things 3")
        #expect(meta.platforms == ["macOS"])
        #expect(meta.category == "Productivity")
        #expect(meta.pricing == "paid")
        #expect(meta.price == "49.99")
        #expect(meta.currency == "USD")
        #expect(meta.maker?.name == "Cultured Code")
        #expect(meta.subtype == "app")
        #expect(meta.cardKindLine == "Mac · $49.99")
    }

    @Test("operatingSystem: comma string vs array, normalised and de-duped")
    func operatingSystem() {
        #expect(ToolReader.platforms(from: "Mac OS X 10.15, Windows 10, Linux") == ["macOS", "Windows", "Linux"])
        #expect(ToolReader.platforms(from: "OSX; macOS") == ["macOS"])
        #expect(ToolReader.platforms(from: ["iOS 17.0 or later", "iPadOS", "Android", "Web browser"])
                == ["iOS", "iPadOS", "Android", "Web"])
        #expect(ToolReader.platforms(from: "Requires iOS 17.0 or later.") == ["iOS"])
        #expect(ToolReader.platforms(from: nil).isEmpty)
        #expect(ToolReader.normalizePlatform("Any") == nil)
    }

    @Test("Offers: price 0 → free; AggregateOffer 0…12 → freemium; an array mixes")
    func offers() {
        let free = ToolReader.offerPricing(from: ["@type": "Offer", "price": "0", "priceCurrency": "USD"] as [String: Any])
        #expect(free.pricing == "free")
        #expect(free.price == nil)

        let freeNumber = ToolReader.offerPricing(from: ["@type": "Offer", "price": NSNumber(value: 0)] as [String: Any])
        #expect(freeNumber.pricing == "free")

        let aggregate = ToolReader.offerPricing(from: [
            "@type": "AggregateOffer", "lowPrice": "0", "highPrice": "12", "priceCurrency": "usd",
        ] as [String: Any])
        #expect(aggregate.pricing == "freemium")
        #expect(aggregate.price == "12")
        #expect(aggregate.currency == "USD")

        let tiers = ToolReader.offerPricing(from: [
            ["@type": "Offer", "price": "0"] as [String: Any],
            ["@type": "Offer", "price": "8", "priceCurrency": "EUR"] as [String: Any],
            ["@type": "Offer", "price": "16", "priceCurrency": "EUR"] as [String: Any],
        ] as [Any])
        #expect(tiers.pricing == "freemium")
        #expect(tiers.price == "8")

        let paid = ToolReader.offerPricing(from: ["@type": "Offer", "price": "4.99", "priceCurrency": "GBP"] as [String: Any])
        #expect(paid.pricing == "paid")
        #expect(paid.price == "4.99")

        #expect(ToolReader.offerPricing(from: nil).pricing == nil)
    }

    @Test("A free web app from JSON-LD reads 'Web · Free'")
    func freeWebApp() {
        let html = jsonLD(#"""
        {"@context":"https://schema.org","@type":"WebApplication","name":"Excalidraw",
         "operatingSystem":"Web","applicationCategory":"DesignApplication",
         "offers":{"@type":"Offer","price":0}}
        """#)
        let meta = buildTool("https://excalidraw.com/", html: html).meta
        #expect(meta.pricing == "free")
        #expect(meta.category == "Design")
        #expect(meta.subtype == "web app")
        #expect(meta.cardKindLine == "Web · Free")
    }

    @Test("applicationCategory cleanup")
    func category() {
        #expect(ToolReader.cleanCategory("DeveloperApplication") == "Developer")
        #expect(ToolReader.cleanCategory("https://schema.org/GameApplication") == "Game")
        #expect(ToolReader.cleanCategory("SocialNetworkingApplication") == "Social Networking")
        #expect(ToolReader.cleanCategory("Productivity") == "Productivity")
        #expect(ToolReader.cleanCategory("Photo & Video") == "Photo & Video")
        #expect(ToolReader.cleanCategory(["UtilitiesApplication"]) == "Utilities")
        #expect(ToolReader.cleanCategory("Application") == "Application")
        #expect(ToolReader.cleanCategory(nil) == nil)
    }

    @Test("og tags: tagline from og:description, else meta description; site name as maker")
    func ogTags() {
        let html = """
        <html><head>
        <meta property="og:site_name" content="Raycast">
        <meta name="description" content="Your shortcut to everything.">
        </head><body></body></html>
        """
        let fromMeta = buildTool("https://raycast.com/", html: html).meta
        #expect(fromMeta.tagline == "Your shortcut to everything.")
        #expect(fromMeta.maker?.name == "Raycast")
        #expect(fromMeta.subtype == "web app")
        #expect(buildTool("https://raycast.com/", html: html, ogDescription: "A launcher.").meta.tagline == "A launcher.")
        // Store / host site names are not the maker.
        let store = #"<html><head><meta property="og:site_name" content="App Store"></head></html>"#
        #expect(buildTool("https://apps.apple.com/us/app/things-3/id904237743", html: store).meta.maker == nil)
    }

    @Test("App Store: the URL itself, else the first App Store badge link on the page")
    func appStoreLinks() {
        let direct = buildTool("https://apps.apple.com/us/app/things-3/id904280696?mt=12").meta
        #expect(direct.appStoreURL == "https://apps.apple.com/us/app/things-3/id904280696?mt=12")
        #expect(direct.platforms == ["macOS"])
        #expect(direct.subtype == "app")

        let html = """
        <html><body>
        <a href="https://apps.apple.com/us/charts">Charts</a>
        <a class="badge" href="https://apps.apple.com/us/app/halide-mark-ii/id885697368?l=en&amp;x=1">Download</a>
        </body></html>
        """
        let page = buildTool("https://halide.cam/", html: html).meta
        #expect(page.appStoreURL == "https://apps.apple.com/us/app/halide-mark-ii/id885697368?l=en&x=1")
    }

    @Test("Subtypes: extension hosts, Hugging Face models, web app default")
    func subtypes() {
        #expect(buildTool("https://chromewebstore.google.com/detail/ublock-origin/cjpalhdlnbpafiamejdnhcphjbkeiagm").meta.subtype == "extension")
        #expect(buildTool("https://addons.mozilla.org/en-US/firefox/addon/ublock-origin/").meta.subtype == "extension")
        #expect(buildTool("https://huggingface.co/black-forest-labs/FLUX.1-dev").meta.subtype == "AI model")
        #expect(buildTool("https://huggingface.co/spaces/foo/bar").meta.subtype == "web app")
        #expect(buildTool("https://github.com/BurntSushi/ripgrep").meta.subtype == "library")
    }
}

// MARK: - GitHub

@Suite("Tool readers: GitHub")
struct ToolGitHubReaderTests {

    @Test("REST JSON fixture: stars, language, licence, pushed date, topics, owner, homepage")
    func repoFixture() throws {
        let repo = try #require(ToolReader.parseGitHubRepo(data: Data(githubRepoJSON.utf8), statusCode: 200))
        let extraction = buildTool(
            "https://github.com/BurntSushi/ripgrep",
            ogDescription: "ripgrep recursively searches... Contribute to BurntSushi/ripgrep development by creating an account on GitHub.",
            github: repo
        )
        let meta = extraction.meta
        #expect(meta.name == "BurntSushi/ripgrep")
        #expect(extraction.title == "BurntSushi/ripgrep")
        #expect(meta.tagline == "ripgrep recursively searches directories for a regex pattern")
        #expect(meta.maker?.name == "BurntSushi")
        #expect(meta.stars == 48211)
        #expect(meta.language == "Rust")
        #expect(meta.license == "Unlicense")
        #expect(meta.pricing == "open source")
        #expect(meta.topics == ["cli", "search", "regex"])
        #expect(meta.homepageURL == "https://burntsushi.net/ripgrep/")
        #expect(meta.repoURL == "https://github.com/BurntSushi/ripgrep")
        #expect(meta.subtype == "library")
        #expect(meta.lastPushedAt == ISO8601DateFormatter().date(from: "2026-09-30T14:02:11Z"))
        #expect(meta.cardKindLine == "Open source · ★ 48.2k")
    }

    @Test("No licence: not 'open source'; the kind line shows only the stars")
    func noLicense() throws {
        let repo = try #require(ToolReader.parseGitHubRepo(data: Data(githubNoLicenseJSON.utf8), statusCode: 200))
        let meta = buildTool("https://github.com/jane/dotfiles", github: repo).meta
        #expect(meta.license == nil)
        #expect(meta.pricing == nil)
        #expect(meta.cardKindLine == "★ 12")
    }

    @Test("Rate limit / errors skip the API; the URL still gives repo, name and owner")
    func rateLimited() {
        #expect(ToolReader.parseGitHubRepo(data: Data(#"{"message":"API rate limit exceeded"}"#.utf8), statusCode: 403) == nil)
        #expect(ToolReader.parseGitHubRepo(data: Data(githubRepoJSON.utf8), statusCode: 429) == nil)
        #expect(ToolReader.parseGitHubRepo(data: Data("not json".utf8), statusCode: 200) == nil)
        #expect(ToolReader.parseGitHubRepo(data: nil, statusCode: nil) == nil)

        let extraction = buildTool(
            "https://github.com/BurntSushi/ripgrep/issues",
            ogDescription: "ripgrep recursively searches directories for a regex pattern - BurntSushi/ripgrep. Contribute to BurntSushi/ripgrep development by creating an account on GitHub."
        )
        let meta = extraction.meta
        #expect(meta.repoURL == "https://github.com/BurntSushi/ripgrep")
        #expect(meta.name == "BurntSushi/ripgrep")
        #expect(meta.maker?.name == "BurntSushi")
        #expect(meta.tagline == "ripgrep recursively searches directories for a regex pattern - BurntSushi/ripgrep.")
        #expect(meta.cardKindLine == nil)
        #expect(ToolReader.githubAPIURL(for: URL(string: "https://github.com/BurntSushi/ripgrep/issues")!)?.absoluteString
                == "https://api.github.com/repos/BurntSushi/ripgrep")
    }

    @Test("Licence label: SPDX id, NOASSERTION falls back to the name")
    func licenseLabel() {
        #expect(ToolReader.licenseLabel(ToolReader.GitHubLicense(spdxId: "MIT", name: "MIT License")) == "MIT")
        #expect(ToolReader.licenseLabel(ToolReader.GitHubLicense(spdxId: "NOASSERTION", name: "Other")) == "Other")
        #expect(ToolReader.licenseLabel(nil) == nil)
    }
}

// MARK: - Redirects, kind line, guess

@Suite("Tool redirects + kind line + guess")
struct ToolMiscTests {

    @Test("Redirect to another host sets canonicalURL; same host doesn't")
    func redirects() {
        let moved = buildTool("https://old-name.app/", finalURL: "https://www.newname.com/home").meta
        #expect(moved.canonicalURL == "https://www.newname.com/home")
        let same = buildTool("https://raycast.com/", finalURL: "https://www.raycast.com/").meta
        #expect(same.canonicalURL == nil)
        #expect(buildTool("https://raycast.com/").meta.canonicalURL == nil)
    }

    @Test("Kind line variants")
    func kindLine() {
        var meta = ToolMeta()
        #expect(meta.cardKindLine == nil)

        meta.platforms = ["macOS"]
        meta.pricing = "free"
        #expect(meta.cardKindLine == "Mac · Free")

        meta.platforms = ["Web"]
        meta.pricing = "freemium"
        #expect(meta.cardKindLine == "Web · Freemium")

        meta.platforms = ["macOS", "iOS", "Windows", "Linux"]
        meta.pricing = "paid"
        meta.price = "4.99"
        meta.currency = "USD"
        #expect(meta.cardKindLine == "Mac, iOS +2 · $4.99")

        meta.platforms = []
        meta.pricing = nil
        meta.price = nil
        #expect(meta.cardKindLine == nil)

        var repo = ToolMeta()
        repo.repoURL = "https://github.com/a/b"
        repo.pricing = "open source"
        #expect(repo.cardKindLine == "Open source")
        repo.stars = 12_400
        #expect(repo.cardKindLine == "Open source · ★ 12.4k")
        #expect(ToolMeta.compactCount(980) == "980")
        #expect(ToolMeta.compactCount(1_000) == "1k")
        #expect(ToolMeta.compactCount(1_260_000) == "1.3M")
    }

    @Test("Rule-based guess is conservative; applyGuess fills gaps only and flags them")
    func guess() {
        #expect(ToolReader.ruleBasedFacts(text: "A beautiful note-taking app.") == nil)
        #expect(ToolReader.ruleBasedFacts(text: nil) == nil)
        let facts = ToolReader.ruleBasedFacts(text: "Download for Mac. Free plan for individuals, Pro at $8 per month.")
        #expect(facts == ToolFacts(platforms: ["macOS"], pricing: "freemium"))

        var empty = ToolMeta()
        ToolReader.applyGuess(ToolFacts(platforms: ["mac", "Windows 11"], pricing: "Freemium"), to: &empty)
        #expect(empty.platforms == ["macOS", "Windows"])
        #expect(empty.platformsAreGuess)
        #expect(empty.pricing == "freemium")
        #expect(empty.pricingIsGuess)

        var read = ToolMeta()
        read.platforms = ["Web"]
        read.pricing = "paid"
        ToolReader.applyGuess(ToolFacts(platforms: ["macOS"], pricing: "free"), to: &read)
        #expect(read.platforms == ["Web"])
        #expect(read.platformsAreGuess == false)
        #expect(read.pricing == "paid")
        #expect(read.pricingIsGuess == false)

        var junk = ToolMeta()
        ToolReader.applyGuess(ToolFacts(platforms: [], pricing: "cheap"), to: &junk)
        #expect(junk.pricing == nil)
    }

    @Test("A refetch that reads less never erases what capture read")
    func mergeKeepsPrevious() {
        var previous = ToolMeta()
        previous.stars = 100
        previous.language = "Swift"
        previous.topics = ["ios"]
        previous.platforms = ["iOS"]
        previous.platformsAreGuess = true
        var fresh = ToolMeta()
        fresh.repoURL = "https://github.com/a/b"
        let merged = ToolReader.merge(fresh: fresh, previous: previous)
        #expect(merged.stars == 100)
        #expect(merged.language == "Swift")
        #expect(merged.topics == ["ios"])
        #expect(merged.platforms == ["iOS"])
        #expect(merged.platformsAreGuess)
        #expect(merged.repoURL == "https://github.com/a/b")
    }

    @Test("Guess pass on an item: the fallback enricher's keyword pass fills platforms")
    @MainActor
    func enrichmentPass() async throws {
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)
        var meta = ToolMeta()
        meta.subtype = "web app"
        let item = Item(
            title: "Cleanshot", extractedText: "Download for Mac — the best screenshot tool.",
            kind: ItemKind.tool.rawValue
        )
        item.setMetadata(meta)
        context.insert(item)
        try context.save()

        await EnrichmentService.applyToolGuessIfNeeded(item: item, enricher: RuleBasedFallbackEnricher())

        let after = try #require(item.toolMeta())
        #expect(after.platforms == ["macOS"])
        #expect(after.platformsAreGuess)
        #expect(after.pricing == nil)
    }

    @Test("Item kind line, typed panel, domain pill and search")
    @MainActor
    func itemLevel() {
        var meta = ToolMeta()
        meta.name = "Raycast"
        meta.tagline = "Your shortcut to everything"
        meta.maker = ToolReader.makerRef("Raycast Technologies")
        meta.platforms = ["macOS"]
        meta.pricing = "freemium"
        meta.category = "Productivity"
        meta.language = "Swift"
        meta.topics = ["launcher"]
        meta.canonicalURL = "https://www.raycast.com/home"
        let item = Item(
            title: "Saved thing", sourceURL: "https://raycast.app", domain: "raycast.app",
            kind: ItemKind.tool.rawValue
        )
        item.setMetadata(meta)

        #expect(item.cardKindLine == "Mac · Freemium")
        #expect(item.hasRichTypedPanel)
        #expect(item.displayLink == "raycast.com")
        #expect(item.sourceURL == "https://raycast.app")
        for query in ["shortcut to everything", "raycast technologies", "macos", "productivity", "swift", "launcher"] {
            #expect(ItemFilter.apply([item], searchText: query, selectedTagNames: []).count == 1, "\(query)")
        }
    }
}
