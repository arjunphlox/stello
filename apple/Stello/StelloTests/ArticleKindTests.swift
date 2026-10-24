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

/// `<meta>` tags from (key, content) pairs; `og:` / `article:` keys use `property`, the rest `name`.
private func metas(_ pairs: [(String, String)], extraHead: String = "") -> String {
    let tags = pairs.map { pair -> String in
        let (key, content) = pair
        let attr = key.hasPrefix("og:") || key.hasPrefix("article:") ? "property" : "name"
        return #"<meta \#(attr)="\#(key)" content="\#(content)">"#
    }.joined(separator: "\n")
    return "<html><head>\n\(tags)\n\(extraHead)</head><body></body></html>"
}

private func buildArticle(
    _ urlString: String,
    finalURL: String? = nil,
    html: String = "",
    ogTitle: String? = nil,
    pageText: String? = nil
) -> ArticleMeta {
    ArticleReader.build(
        sourceURL: URL(string: urlString)!,
        finalURL: finalURL.flatMap { URL(string: $0) },
        html: html,
        ogTitle: ogTitle,
        pageText: pageText
    )
}

private func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func words(_ count: Int) -> String {
    Array(repeating: "word", count: count).joined(separator: " ")
}

// MARK: - Fixtures

private let simonURL = "https://simonwillison.net/2025/Mar/11/using-llms-for-code/"
private let codropsURL = "https://tympanus.net/codrops/2025/03/11/building-an-infinite-slider-with-gsap/"

private let newsArticleJSONLD = #"""
{"@context":"https://schema.org","@type":"NewsArticle","headline":"Chip shortage eases",
 "author":{"@type":"Person","name":"Jane Reporter","url":"/staff/jane"},
 "publisher":{"@type":"Organization","name":"The Daily Bit"},
 "datePublished":"2025-03-11T09:30:00Z"}
"""#

// MARK: - Classification

@Suite("Article classification")
struct ArticleClassificationTests {

    @Test("Article-family JSON-LD → article")
    func jsonLDTypes() {
        for type in ["Article", "NewsArticle", "BlogPosting", "TechArticle", "Report", "ScholarlyArticle"] {
            let html = jsonLD(#"{"@context":"https://schema.org","@type":"\#(type)","headline":"x"}"#)
            #expect(classify("https://example.com/some-story", html: html).kind == .article, "\(type)")
        }
        #expect(classify("https://news.example.com/chips", html: jsonLD(newsArticleJSONLD)).kind == .article)
    }

    @Test("article:published_time meta → article")
    func publishedTime() {
        let html = metas([("article:published_time", "2025-03-11T09:30:00Z")])
        #expect(classify("https://example.com/some-story", html: html).kind == .article)
    }

    @Test("Dated paths → article: /YYYY/Mon/DD/slug, /YYYY/MM/slug, /YYYY/MM/DD/slug")
    func datedPaths() {
        #expect(classify(simonURL).kind == .article)
        #expect(classify("https://example.com/2020/06/some-slug").kind == .article)
        #expect(classify("https://www.nytimes.com/2024/11/05/technology/ai-chips.html").kind == .article)
        #expect(classify("https://example.com/blog/2019/12/31/year-in-review/").kind == .article)
        // Archive listings (no slug after the date), bad months and non-19xx/20xx years don't count.
        #expect(classify("https://example.com/2025/03/").kind == .link)
        #expect(classify("https://example.com/2025/13/slug").kind == .link)
        #expect(classify("https://example.com/2525/03/slug").kind == .link)
        #expect(classify("https://example.com/products/2025/xyz").kind != .article)
    }

    @Test("URL path date parsing: numeric and three-letter months, optional day")
    func urlPathDate() {
        let mar = PageClassifier.urlPathDate(URL(string: simonURL)!)
        #expect(mar?.year == 2025)
        #expect(mar?.month == 3)
        #expect(mar?.day == 11)
        let june = PageClassifier.urlPathDate(URL(string: "https://example.com/2020/06/some-slug")!)
        #expect(june?.year == 2020)
        #expect(june?.month == 6)
        #expect(june?.day == nil)
        #expect(PageClassifier.urlPathDate(URL(string: "https://example.com/2020/sept/slug")!) == nil)
    }

    @Test("A blog / post / news segment followed by a slug → article; the index alone is not")
    func blogSlug() {
        for url in [
            "https://example.com/blog/my-first-post",
            "https://example.com/en/blog/my-first-post/",
            "https://example.com/posts/hello-world",
            "https://example.com/news/launch-day",
            "https://example.com/essays/on-taste",
            "https://example.com/writing/notes-on-grids",
            "https://example.com/articles/css-grid",
        ] {
            #expect(classify(url).kind == .article, "\(url)")
        }
        for url in [
            "https://example.com/blog/",
            "https://example.com/blog",
            "https://example.com/blog/page/2",
            "https://example.com/blog/tag/design",
            "https://example.com/blog/category/news/",
            "https://example.com/blog/feed",
            "https://example.com/blogging-tips",
        ] {
            #expect(classify(url).kind != .article, "\(url)")
        }
    }

    @Test("og:type article alone is not an article")
    func ogTypeAlone() {
        #expect(classify("https://example.com/some-page", ogType: "article").kind == .link)
    }

    @Test("og:type article + an author or date signal → article")
    func ogTypeWithSignal() {
        let author = metas([("og:type", "article"), ("author", "Jane Doe")])
        #expect(classify("https://example.com/some-page", html: author, ogType: "article").kind == .article)
        let articleAuthor = metas([("article:author", "https://www.facebook.com/jane")])
        #expect(classify("https://example.com/some-page", html: articleAuthor, ogType: "article").kind == .article)
        let twitter = metas([("twitter:label1", "Written by"), ("twitter:data1", "Jane Doe")])
        #expect(classify("https://example.com/some-page", html: twitter, ogType: "article").kind == .article)
        let modified = metas([("article:modified_time", "2025-03-12T10:00:00Z")])
        #expect(classify("https://example.com/some-page", html: modified, ogType: "article").kind == .article)
        let webPage = jsonLD(#"{"@context":"https://schema.org","@type":"WebPage","datePublished":"2025-03-11"}"#)
        #expect(classify("https://example.com/some-page", html: webPage, ogType: "article").kind == .article)
        // The signals alone (no og:type article, no other rule) don't make an article.
        #expect(classify("https://example.com/some-page", html: author).kind == .link)
    }

    @Test("The news label breaks the og:type-article tie; education never makes an article")
    func labels() {
        #expect(classify("https://example.com/some-page", ogType: "article", labels: ["news"]).kind == .article)
        #expect(classify("https://example.com/some-page", ogType: "article", labels: ["News"]).kind == .article)
        #expect(classify("https://example.com/some-page", labels: ["news"]).kind == .link)
        #expect(classify("https://example.com/some-page", ogType: "article", labels: ["education"]).kind == .link)
        #expect(classify("https://example.com/some-page", labels: ["education"]).kind == .link)
    }

    @Test("Medium and Substack posts → article; profiles and home pages are not")
    func mediumSubstack() {
        #expect(classify("https://medium.com/@jane/why-grids-matter-3f2a1b").kind == .article)
        #expect(classify("https://medium.com/design-bootcamp/why-grids-matter-3f2a1b").kind == .article)
        #expect(classify("https://jane.medium.com/why-grids-matter-3f2a1b").kind == .article)
        #expect(classify("https://jane.substack.com/p/why-grids-matter").kind == .article)
        #expect(classify("https://medium.com/@jane").kind != .article)
        #expect(classify("https://medium.com/tag/design/archive").kind != .article)
        #expect(classify("https://jane.medium.com/").kind != .article)
        #expect(classify("https://jane.substack.com/").kind != .article)
        #expect(classify("https://jane.substack.com/archive").kind != .article)
    }

    @Test("A dated Codrops URL → article, and a tutorial")
    func codrops() {
        #expect(classify(codropsURL).kind == .article)
        #expect(PageClassifier.isCodropsArticle(URL(string: "https://tympanus.net/codrops/2025/x")!))
        #expect(!PageClassifier.isCodropsArticle(URL(string: "https://tympanus.net/codrops/category/tutorials/")!))
        let meta = buildArticle(codropsURL, ogTitle: "Building an Infinite Slider with GSAP | Codrops")
        #expect(meta.isTutorial)
    }

    @Test("A Framer Marketplace page with og:type article stays a resource")
    func framerStaysResource() {
        let url = "https://www.framer.com/marketplace/templates/portfolio-pro/"
        let html = metas([("og:type", "article"), ("author", "Studio Nine")])
        #expect(classify(url, html: html, ogType: "article").kind == .resource)
    }

    @Test("A course-like page with og:type article only is not an article")
    func coursePage() {
        #expect(classify("https://www.domestika.org/en/courses/1234-motion-design-basics", ogType: "article").kind != .article)
        #expect(classify("https://www.skillshare.com/en/classes/branding-101/123456", ogType: "article").kind != .article)
    }

    @Test("A gen-ai-labelled blog post → article, not tool")
    func genAIBlogPost() {
        let html = metas([("og:type", "article"), ("author", "Simon Willison")])
        let result = classify(simonURL, html: html, ogType: "article", labels: ["gen-ai"])
        #expect(result.kind == .article)
        let blogPosting = jsonLD(#"{"@context":"https://schema.org","@type":"BlogPosting","headline":"LLM tools"}"#)
        #expect(classify("https://example.com/blog/llm-tools", html: blogPosting, labels: ["gen-ai"]).kind == .article)
        #expect(classify("https://example.com/notes/llm-tools", html: blogPosting, labels: ["digital-tools"]).kind == .article)
        // URL signals alone (no markup) also beat a tool label.
        #expect(classify("https://example.com/blog/llm-tools", labels: ["gen-ai"]).kind == .article)
        #expect(classify("https://example.com/2025/03/llm-tools", labels: ["digital-tools"]).kind == .article)
        #expect(classify("https://raycast.com/", labels: ["digital-tools"]).kind == .tool)
    }

    @Test("A tweet stays a post, even with article signals or the news label")
    func tweetStaysPost() {
        let result = classify(
            "https://x.com/janedoe/status/1453768926539317251",
            html: metas([("article:published_time", "2025-03-11T09:30:00Z")]),
            ogType: "article",
            labels: ["news"]
        )
        #expect(result.kind == .post)
    }

    @Test("A bare image file is never an article")
    func bareImage() {
        #expect(classify("https://example.com/2025/03/hero.png").kind != .article)
    }
}

// MARK: - Readers

@Suite("Article readers")
struct ArticleReaderTests {

    @Test("NewsArticle JSON-LD: author object with url, publisher, datePublished")
    func newsArticle() {
        let meta = buildArticle("https://news.example.com/chips", html: jsonLD(newsArticleJSONLD))
        #expect(meta.author?.name == "Jane Reporter")
        #expect(meta.author?.url == "https://news.example.com/staff/jane")
        #expect(meta.author?.kind == ItemKind.individual.rawValue)
        #expect(meta.publication == "The Daily Bit")
        #expect(meta.publishedAt == utcDate(2025, 3, 11, hour: 9, minute: 30))
    }

    @Test("Author shapes: string, object, array → first")
    func authorShapes() {
        let string = jsonLD(#"{"@type":"BlogPosting","author":"Jane Doe"}"#)
        #expect(buildArticle("https://example.com/a", html: string).author?.name == "Jane Doe")
        let object = jsonLD(#"{"@type":"BlogPosting","author":{"@type":"Person","name":"Jane Doe","url":"https://jane.dev"}}"#)
        let fromObject = buildArticle("https://example.com/a", html: object).author
        #expect(fromObject?.name == "Jane Doe")
        #expect(fromObject?.url == "https://jane.dev")
        let array = jsonLD(#"{"@type":"BlogPosting","author":[{"@type":"Person","name":"First Author"},{"@type":"Person","name":"Second"}]}"#)
        #expect(buildArticle("https://example.com/a", html: array).author?.name == "First Author")
    }

    @Test("Author fallbacks: meta author, article:author (not a URL), twitter 'Written by'")
    func authorFallbacks() {
        #expect(buildArticle("https://example.com/a", html: metas([("author", "Meta Author")])).author?.name == "Meta Author")
        #expect(buildArticle("https://example.com/a", html: metas([("article:author", "Article Author")])).author?.name == "Article Author")
        // A URL-only article:author is ignored.
        #expect(buildArticle("https://example.com/a", html: metas([("article:author", "https://www.facebook.com/jane")])).author == nil)
        let twitter = metas([
            ("article:author", "https://www.facebook.com/jane"),
            ("twitter:label1", "Written by"), ("twitter:data1", "Twitter Author"),
        ])
        #expect(buildArticle("https://example.com/a", html: twitter).author?.name == "Twitter Author")
        // twitter:data1 under another label is not an author.
        let readingTime = metas([("twitter:label1", "Est. reading time"), ("twitter:data1", "6 minutes")])
        #expect(buildArticle("https://example.com/a", html: readingTime).author == nil)
        // JSON-LD wins over meta tags.
        let both = jsonLD(#"{"@type":"Article","author":"JSON Author"}"#)
            .replacingOccurrences(of: "</head>", with: #"<meta name="author" content="Meta Author"></head>"#)
        #expect(buildArticle("https://example.com/a", html: both).author?.name == "JSON Author")
    }

    @Test("Date precedence: JSON-LD datePublished → article:published_time → URL date")
    func datePrecedence() {
        let all = jsonLD(#"{"@type":"Article","datePublished":"2024-01-05"}"#)
            .replacingOccurrences(of: "</head>", with: #"<meta property="article:published_time" content="2023-02-02T08:00:00+00:00"></head>"#)
        #expect(buildArticle(simonURL, html: all).publishedAt == utcDate(2024, 1, 5))
        let metaOnly = metas([("article:published_time", "2023-02-02T08:00:00+00:00")])
        #expect(buildArticle(simonURL, html: metaOnly).publishedAt == utcDate(2023, 2, 2, hour: 8))
        #expect(buildArticle(simonURL).publishedAt == utcDate(2025, 3, 11, hour: 12))
        #expect(buildArticle("https://example.com/2020/06/some-slug").publishedAt == utcDate(2020, 6, 1, hour: 12))
        #expect(buildArticle("https://example.com/blog/no-date").publishedAt == nil)
    }

    @Test("ISO date variants")
    func dateVariants() {
        #expect(ArticleReader.parseDate("2025-03-11T09:30:00Z") == utcDate(2025, 3, 11, hour: 9, minute: 30))
        #expect(ArticleReader.parseDate("2025-03-11T09:30:00.000Z") == utcDate(2025, 3, 11, hour: 9, minute: 30))
        #expect(ArticleReader.parseDate("2025-03-11T15:00:00+05:30") == utcDate(2025, 3, 11, hour: 9, minute: 30))
        #expect(ArticleReader.parseDate("2025-03-11T09:30:00") == utcDate(2025, 3, 11, hour: 9, minute: 30))
        #expect(ArticleReader.parseDate("2025-03-11") == utcDate(2025, 3, 11))
        #expect(ArticleReader.parseDate("last Tuesday") == nil)
        #expect(ArticleReader.parseDate(nil) == nil)
    }

    @Test("Reading minutes: words ÷ 230 rounded up, at least 1, nil without text")
    func readingMinutes() {
        #expect(ArticleReader.readingMinutes(text: nil) == nil)
        #expect(ArticleReader.readingMinutes(text: "   ") == nil)
        #expect(ArticleReader.readingMinutes(text: "one") == 1)
        #expect(ArticleReader.readingMinutes(text: words(230)) == 1)
        #expect(ArticleReader.readingMinutes(text: words(231)) == 2)
        #expect(ArticleReader.readingMinutes(text: words(1_380)) == 6)
        #expect(buildArticle(simonURL, pageText: words(1_380)).readingMinutes == 6)
    }

    @Test("Full page text counts for reading time (not the 4,000-character AI slice)")
    func fullTextReadingTime() {
        let body = "<html><body><p>\(words(2_300))</p></body></html>"
        #expect(CaptureService.extractText(html: body)!.count <= 4_000)
        let full = CaptureService.extractText(html: body, limit: nil)
        #expect(ArticleReader.readingMinutes(text: full) == 10)
    }

    @Test("Publication: og:site_name → JSON-LD publisher → host without www")
    func publication() {
        let site = metas([("og:site_name", "Simon Willison’s Weblog")])
        #expect(buildArticle(simonURL, html: site).publication == "Simon Willison’s Weblog")
        let publisher = jsonLD(#"{"@type":"Article","publisher":{"@type":"Organization","name":"The Daily Bit"}}"#)
        #expect(buildArticle("https://www.dailybit.com/a", html: publisher).publication == "The Daily Bit")
        #expect(buildArticle(simonURL).publication == "simonwillison.net")
        #expect(buildArticle("https://www.example.com/blog/x").publication == "example.com")
    }

    @Test("Tutorial flag: Codrops host, /tutorial(s)/ segment, 'How to' / 'Tutorial' titles")
    func tutorial() {
        #expect(buildArticle(codropsURL).isTutorial)
        #expect(buildArticle("https://example.com/tutorials/grid-layout").isTutorial)
        #expect(buildArticle("https://example.com/blog/tutorial/grid-layout").isTutorial)
        #expect(buildArticle("https://example.com/blog/x", ogTitle: "How to build a grid").isTutorial)
        #expect(buildArticle("https://example.com/blog/x", ogTitle: "Tutorial: shaders in SwiftUI").isTutorial)
        #expect(!buildArticle("https://example.com/blog/x", ogTitle: "Why grids matter").isTutorial)
        #expect(!buildArticle("https://example.com/blog/how-to-x", ogTitle: "Knowing how to wait").isTutorial)
    }

    @Test("Canonical URL: set when the final URL differs, else nil")
    func canonical() {
        let short = "https://jane.substack.com/p/why-grids-matter"
        let landed = "https://www.janedoe.com/p/why-grids-matter"
        #expect(buildArticle(short, finalURL: landed).canonicalURL == landed)
        #expect(buildArticle(short, finalURL: short).canonicalURL == nil)
        #expect(buildArticle(short).canonicalURL == nil)
    }

    @Test("Kind line variants")
    func kindLine() {
        var meta = ArticleMeta()
        #expect(meta.cardKindLine == nil)
        meta.publication = "simonwillison.net"
        #expect(meta.cardKindLine == "simonwillison.net")
        meta.readingMinutes = 6
        #expect(meta.cardKindLine == "simonwillison.net · 6 min")
        meta.publication = "  "
        #expect(meta.cardKindLine == "6 min")
        #expect(meta.readingLine == "6 min read")
    }

    @Test("Rule-based tech stack: known names as whole words, conservative, max 5")
    func ruleBasedTechStack() {
        let text = "We build the scene in three.js, animate it with GSAP and write a GLSL shader. React is optional."
        #expect(ArticleReader.ruleBasedTechStack(text: text) == ["three.js", "GSAP", "React", "GLSL"])
        // Everyday words don't count: "react", "swift", "rive" in lowercase prose.
        #expect(ArticleReader.ruleBasedTechStack(text: "How users react to a swift, rive-like change") == [])
        #expect(ArticleReader.ruleBasedTechStack(text: "Built with SwiftUI, not UIKit.") == ["SwiftUI"])
        #expect(ArticleReader.ruleBasedTechStack(text: "Next.js and Tailwind with Vue.js") == ["Next.js", "Vue", "Tailwind"])
        let many = "three.js GSAP React WebGL GLSL CSS Figma Svelte"
        #expect(ArticleReader.ruleBasedTechStack(text: many).count == 5)
        #expect(ArticleReader.ruleBasedTechStack(text: nil) == [])
    }

    @Test("Digest: summary stored as a guess; tech stack only for tutorials, rule-based fallback")
    func digest() {
        var essay = ArticleMeta()
        ArticleReader.applyDigest(
            ArticleFacts(summary: "  Grids remove decisions.  ", techStack: ["CSS"]), text: "CSS grids", to: &essay
        )
        #expect(essay.summary == "Grids remove decisions.")
        #expect(essay.summaryIsGuess)
        #expect(essay.techStack.isEmpty)

        var tutorial = ArticleMeta()
        tutorial.isTutorial = true
        ArticleReader.applyDigest(nil, text: "Animate it with GSAP and a WebGL shader.", to: &tutorial)
        #expect(tutorial.summary == nil)
        #expect(!tutorial.summaryIsGuess)
        #expect(tutorial.techStack == ["GSAP", "WebGL"])

        var modelStack = ArticleMeta()
        modelStack.isTutorial = true
        ArticleReader.applyDigest(
            ArticleFacts(summary: nil, techStack: ["Rive", "rive", " ", "Figma"]), text: "GSAP", to: &modelStack
        )
        #expect(modelStack.techStack == ["Rive", "Figma"])

        // Stored values are never replaced.
        var kept = ArticleMeta()
        kept.summary = "Existing."
        ArticleReader.applyDigest(ArticleFacts(summary: "New."), text: nil, to: &kept)
        #expect(kept.summary == "Existing.")
        #expect(!ArticleReader.needsDigest(kept))
    }

    @Test("A refetch that reads less never erases what capture read; AI fields are kept")
    func merge() {
        var previous = ArticleMeta()
        previous.publication = "The Daily Bit"
        previous.author = ArticleReader.authorRef("Jane")
        previous.readingMinutes = 4
        previous.summary = "A summary."
        previous.summaryIsGuess = true
        previous.techStack = ["CSS"]
        previous.isTutorial = true
        var fresh = ArticleMeta()
        fresh.readingMinutes = 5
        let merged = ArticleReader.merge(fresh: fresh, previous: previous)
        #expect(merged.publication == "The Daily Bit")
        #expect(merged.author?.name == "Jane")
        #expect(merged.readingMinutes == 5)
        #expect(merged.summary == "A summary.")
        #expect(merged.summaryIsGuess)
        #expect(merged.techStack == ["CSS"])
        #expect(merged.isTutorial)
    }
}

// MARK: - Item level + refresh

@Suite("Article items")
struct ArticleItemTests {

    @Test("Item kind line, typed panel, domain pill and search")
    @MainActor
    func itemLevel() {
        var meta = ArticleMeta()
        meta.publication = "simonwillison.net"
        meta.author = ArticleReader.authorRef("Simon Willison")
        meta.readingMinutes = 6
        meta.summary = "Using LLMs to write code works best with tight feedback loops."
        meta.summaryIsGuess = true
        meta.isTutorial = true
        meta.techStack = ["Python"]
        let item = Item(title: "Using LLMs for code", sourceURL: simonURL, domain: "simonwillison.net", kind: ItemKind.article.rawValue)
        item.setMetadata(meta)

        #expect(item.articleMeta() != nil)
        #expect(item.resourceMeta() == nil)
        #expect(item.cardKindLine == "simonwillison.net · 6 min")
        #expect(item.hasRichTypedPanel)
        #expect(item.displayLink == "simonwillison.net")
        for query in ["simon willison", "feedback loops", "python"] {
            #expect(ItemFilter.apply([item], searchText: query, selectedTagNames: []).count == 1, "\(query)")
        }
    }

    @Test("Refresh flips a link to article; curated kinds are never flipped")
    @MainActor
    func refresh() async throws {
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)

        let link = Item(title: "Chips", sourceURL: "https://news.example.com/chips", kind: ItemKind.link.rawValue)
        let website = Item(title: "Daily Bit", sourceURL: "https://news.example.com/chips", kind: ItemKind.website.rawValue)
        for item in [link, website] { context.insert(item) }
        try context.save()

        let page = PageFetchResult(
            html: jsonLD(newsArticleJSONLD), og: OGResult(title: "Chip shortage eases"), statusCode: 200
        )
        let url = URL(string: "https://news.example.com/chips")!
        #expect(await EnrichmentService.refreshArticleIfClassified(item: link, context: context, url: url, page: page))
        #expect(link.kind == ItemKind.article.rawValue)
        #expect(link.articleMeta()?.publication == "The Daily Bit")
        #expect(link.articleMeta()?.author?.name == "Jane Reporter")

        #expect(await EnrichmentService.refreshArticleIfClassified(
            item: website, context: context, url: url, page: page
        ) == false)
        #expect(website.kind == ItemKind.website.rawValue)

        // A link whose page has no article signal stays a link.
        let plain = Item(title: "Home", sourceURL: "https://example.com/", kind: ItemKind.link.rawValue)
        context.insert(plain)
        #expect(await EnrichmentService.refreshArticleIfClassified(
            item: plain, context: context, url: URL(string: "https://example.com/")!,
            page: PageFetchResult(html: "<html></html>", og: OGResult(), statusCode: 200)
        ) == false)
        #expect(plain.kind == ItemKind.link.rawValue)
    }

    @Test("Digest job: rule-based fallback fills a tutorial's tech stack, no summary")
    @MainActor
    func digestJob() async throws {
        var meta = ArticleMeta()
        meta.isTutorial = true
        let item = Item(title: "Infinite slider", sourceURL: codropsURL, kind: ItemKind.article.rawValue)
        item.setMetadata(meta)
        item.extractedText = "In this tutorial we animate an infinite slider with GSAP and a WebGL shader."

        await EnrichmentService.applyArticleDigestIfNeeded(item: item, enricher: RuleBasedFallbackEnricher())
        #expect(item.articleMeta()?.summary == nil)
        #expect(item.articleMeta()?.techStack == ["GSAP", "WebGL"])

        let essay = Item(title: "Essay", sourceURL: simonURL, kind: ItemKind.article.rawValue)
        essay.setMetadata(ArticleMeta())
        essay.extractedText = "Some prose about React and GSAP."
        await EnrichmentService.applyArticleDigestIfNeeded(item: essay, enricher: MockEnricher())
        #expect(essay.articleMeta()?.summary == nil)
        #expect(essay.articleMeta()?.techStack.isEmpty == true)
    }
}
