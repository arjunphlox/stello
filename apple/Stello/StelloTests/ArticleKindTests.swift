import Testing
import Foundation
import SwiftData
@testable import Stello

private func words(_ count: Int) -> String {
    Array(repeating: "word", count: count).joined(separator: " ")
}

// MARK: - Fixtures

private let simonURL = "https://simonwillison.net/2025/Mar/11/using-llms-for-code/"
private let codropsURL = "https://tympanus.net/codrops/2025/03/11/building-an-infinite-slider-with-gsap/"

// MARK: - Readers

@Suite("Article readers")
struct ArticleReaderTests {

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
