import Testing
import Foundation
import SwiftData
@testable import Stello

// MARK: - Redirects, kind line, guess

@Suite("Tool redirects + kind line + guess")
struct ToolMiscTests {

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
