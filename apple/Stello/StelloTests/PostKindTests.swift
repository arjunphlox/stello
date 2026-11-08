import Testing
import Foundation
import SwiftData
@testable import Stello

// MARK: - AI art

@Suite("Post AI art")
struct PostAIArtTests {

    @Test("Collection labels flag AI art, with the model when the label names one")
    func labels() {
        #expect(PostReader.aiArtSignal(labels: ["Midjourney"], tags: [], text: nil)
                == AIArtSignal(isAIArt: true, model: "Midjourney"))
        #expect(PostReader.aiArtSignal(labels: ["nijijourney"], tags: [], text: nil).model == "Midjourney")
        #expect(PostReader.aiArtSignal(labels: ["Gen AI"], tags: [], text: nil)
                == AIArtSignal(isAIArt: true, model: nil))
        #expect(PostReader.aiArtSignal(labels: ["ai-art", "dall-e"], tags: [], text: nil).model == "DALL·E")
        #expect(PostReader.aiArtSignal(labels: ["wishlist", "typography"], tags: [], text: nil).isAIArt == false)
    }

    @Test("A tag flags AI art too")
    func tag() {
        #expect(PostReader.aiArtSignal(labels: [], tags: ["stable-diffusion"], text: nil)
                == AIArtSignal(isAIArt: true, model: "Stable Diffusion"))
    }

    @Test("Midjourney params in the text flag AI art as Midjourney")
    func params() {
        #expect(PostReader.aiArtSignal(labels: [], tags: [], text: "neon koi pond --ar 16:9 --v 6")
                == AIArtSignal(isAIArt: true, model: "Midjourney"))
        #expect(PostReader.aiArtSignal(labels: [], tags: [], text: "foggy tower —style raw").isAIArt)
        #expect(PostReader.aiArtSignal(labels: [], tags: [], text: "--sref 12345 --stylize 250").isAIArt)
        #expect(PostReader.aiArtSignal(labels: [], tags: [], text: "--chaos 20").isAIArt)
        #expect(PostReader.aiArtSignal(labels: [], tags: [], text: "--niji 6 cat").isAIArt)
        #expect(PostReader.aiArtSignal(labels: [], tags: [], text: "a --variant of the logo").isAIArt == false)
        #expect(PostReader.aiArtSignal(labels: [], tags: [], text: "I love this art").isAIArt == false)
        // A generic label + a model named in the text.
        #expect(PostReader.aiArtSignal(labels: ["gen-ai"], tags: [], text: "made with Midjourney").model == "Midjourney")
    }

    @Test("Prompt: after 'prompt:' / 'Prompt —', else the sentence with the params")
    func promptExtraction() {
        #expect(PostReader.extractPrompt(from: "New piece! Prompt: a neon koi pond at night, ukiyo-e style --ar 3:2")
                == "a neon koi pond at night, ukiyo-e style --ar 3:2")
        #expect(PostReader.extractPrompt(from: #"Prompt — "misty pine forest, morning light""#)
                == "misty pine forest, morning light")
        #expect(PostReader.extractPrompt(from: "Made this today. a brutalist tower in fog, cinematic --ar 2:3 --v 6\n#midjourney")
                == "a brutalist tower in fog, cinematic --ar 2:3 --v 6")
        #expect(PostReader.extractPrompt(from: "just vibes") == nil)
        #expect(PostReader.extractPrompt(from: nil) == nil)
    }

    @Test("A param needs a value or the end of the line: prose like \"the --sref's\" is no prompt")
    func proseParamIsNoPrompt() {
        let tweet = "Made a free Midjourney Style Reference Tool\n\n>15k srefs\n>smart AI search\n"
            + ">view prompt + parameters\n>search by color, hex code, vibe, subject\n\n"
            + "I also curated 5 boards to visualize the --sref's against different styles\n\n"
            + "Link below. It's free and very useful"
        #expect(PostReader.hasMidjourneyParams(tweet) == false)
        #expect(PostReader.extractPrompt(from: tweet) == nil)

        // The label still flags AI art (label rule), but the prompt stays nil.
        var meta = PostMeta()
        meta.text = tweet
        PostReader.applyAIArt(to: &meta, labels: ["midjourney"], tags: [])
        #expect(meta.isAIArt)
        #expect(meta.aiModel == "Midjourney")
        #expect(meta.prompt == nil)

        #expect(PostReader.hasMidjourneyParams("the --sref, again") == false)
        #expect(PostReader.hasMidjourneyParams("koi pond --ar 16:9"))
        #expect(PostReader.hasMidjourneyParams("--sref 123"))
        #expect(PostReader.hasMidjourneyParams("tower --v 6"))
        #expect(PostReader.hasMidjourneyParams("cat in rain --niji"))
    }

    @Test("applyAIArt: rule-read prompt replaces a guess; no signal clears the flag")
    func applyAIArt() {
        var meta = PostMeta()
        meta.text = "Made this today. a brutalist tower in fog --ar 2:3"
        meta.prompt = "old guess"
        meta.promptIsGuess = true
        PostReader.applyAIArt(to: &meta, labels: [], tags: [])
        #expect(meta.isAIArt)
        #expect(meta.aiModel == "Midjourney")
        #expect(meta.prompt == "a brutalist tower in fog --ar 2:3")
        #expect(meta.promptIsGuess == false)

        var plain = PostMeta()
        plain.text = "Golden hour on the rooftop"
        plain.isAIArt = true
        PostReader.applyAIArt(to: &plain, labels: [], tags: [])
        #expect(plain.isAIArt == false)
        #expect(plain.aiModel == nil)
    }

    @Test("Enrichment flags a labelled post; the fallback enricher leaves the prompt empty")
    @MainActor
    func enrichmentPass() async throws {
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)

        var meta = PostMeta()
        meta.platform = "instagram"
        meta.authorHandle = "janedoe"
        meta.text = "Brutalist library at dusk #aiart"
        let item = Item(title: "@janedoe: Brutalist library at dusk #aiart", kind: ItemKind.post.rawValue)
        item.setMetadata(meta)
        context.insert(item)
        item.tags = [ItemTag(name: "midjourney", category: "collection", weight: 1.0)]
        try context.save()

        await EnrichmentService.applyPostAIArtIfNeeded(item: item, enricher: RuleBasedFallbackEnricher())

        let after = try #require(item.postMeta())
        #expect(after.isAIArt)
        #expect(after.aiModel == "Midjourney")
        #expect(after.prompt == nil)
        #expect(after.promptIsGuess == false)
    }
}

// MARK: - Title rule

@Suite("Post title rule")
struct PostTitleRuleTests {

    @Test("Dribbble: 'by Name on Dribbble' gives the author and the shot title")
    func dribbbleTitle() {
        let parsed = PostReader.parseDribbbleTitle("Desk lamp by Jane Doe on Dribbble")
        #expect(parsed.work == "Desk lamp")
        #expect(parsed.author == "Jane Doe")
    }

    private let longText = "Shipping the new type specimen today with every weight and the italics"

    @Test("Generic platform titles are recognised; real titles are not")
    func genericPatterns() {
        for title in [
            "Jane Doe (@janedoe) on X",
            #"Jane Doe on X: "hello""#,
            "Jane Doe on Twitter",
            #"Jane Doe on Twitter: "hello""#,
            #"Jane Doe on Instagram: "hello""#,
            "Jane Doe (@janedoe) • Instagram photos and videos",
            "Instagram",
            "Behance",
            "Dribbble",
            "Pin on Interiors",
            "x.com",
            "",
        ] {
            #expect(PostReader.isGenericPostTitle(title), "\(title)")
        }
        #expect(PostReader.isGenericPostTitle("Brand Identity for Foo on Behance") == false)
        #expect(PostReader.isGenericPostTitle("Desk lamp") == false)
    }

    @Test("Each generic pattern becomes '@handle: first 8 words…'")
    func replacesGeneric() {
        let expected = "@janedoe: Shipping the new type specimen today with every…"
        for title in ["Jane Doe (@janedoe) on X", #"Jane Doe on X: "Shipping…""#, "Jane Doe on Twitter",
                      #"Jane Doe on Instagram: "Shipping…""#, "Behance", "Dribbble"] {
            #expect(PostReader.postTitle(currentTitle: title, handle: "janedoe", authorName: "Jane Doe", text: longText)
                    == expected, "\(title)")
        }
    }

    @Test("Short text keeps no ellipsis; no handle uses the author's name")
    func shortText() {
        #expect(PostReader.postTitle(currentTitle: "Jane Doe on X", handle: "janedoe", authorName: nil, text: "gm")
                == "@janedoe: gm")
        #expect(PostReader.postTitle(currentTitle: "Instagram", handle: nil, authorName: "Jane Doe", text: "New lamp drop")
                == "Jane Doe: New lamp drop")
        #expect(PostReader.textExcerpt("one two three four five six seven eight") == "one two three four five six seven eight")
        #expect(PostReader.textExcerpt("one, two, three, four, five, six, seven, eight, nine") == "one, two, three, four, five, six, seven, eight…")
    }

    @Test("No text falls back to the original title; a real title is kept")
    func noTextAndRealTitle() {
        #expect(PostReader.postTitle(currentTitle: "Jane Doe (@janedoe) on X", handle: "janedoe", authorName: nil, text: nil)
                == "Jane Doe (@janedoe) on X")
        #expect(PostReader.postTitle(currentTitle: "My favourite lamp", handle: "janedoe", authorName: nil, text: longText)
                == "My favourite lamp")
        #expect(PostReader.postTitle(currentTitle: "Desk lamp by Jane Doe on Dribbble", handle: nil, authorName: nil, text: nil)
                == "Desk lamp")
    }
}

// MARK: - Kind line, panel + search

@Suite("Post kind line + search")
struct PostKindLineTests {

    @Test("Kind line is '@handle', nothing without a handle")
    func kindLine() {
        var meta = PostMeta()
        #expect(meta.cardKindLine == nil)
        meta.authorHandle = "  "
        #expect(meta.cardKindLine == nil)
        meta.authorHandle = "janedoe"
        #expect(meta.cardKindLine == "@janedoe")
    }

    @Test("Item kind line, typed panel and search over author, handle, text and prompt")
    @MainActor
    func itemLevel() {
        var meta = PostMeta()
        meta.platform = "x"
        meta.author = EntityRef(name: "Jane Doe", slug: nil, kind: ItemKind.individual.rawValue)
        meta.authorHandle = "janedoe"
        meta.text = "Four colour studies"
        meta.isAIArt = true
        meta.prompt = "brutalist library at dusk"
        let item = Item(title: "Saved thing", kind: ItemKind.post.rawValue)
        item.setMetadata(meta)

        #expect(item.cardKindLine == "@janedoe")
        #expect(item.hasRichTypedPanel)
        #expect(item.typedTopMediaRoles.contains(ItemImageRole.gallery.rawValue))
        #expect(ItemFilter.apply([item], searchText: "jane doe", selectedTagNames: []).count == 1)
        #expect(ItemFilter.apply([item], searchText: "@janedoe", selectedTagNames: []).count == 1)
        #expect(ItemFilter.apply([item], searchText: "colour studies", selectedTagNames: []).count == 1)
        #expect(ItemFilter.apply([item], searchText: "brutalist library", selectedTagNames: []).count == 1)
    }
}
