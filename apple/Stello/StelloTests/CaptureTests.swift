import Testing
import Foundation
import SwiftData
@testable import Stello

// MARK: - RuleTagger Tests

@Suite("RuleTagger: formatTagFor")
struct FormatTagTests {

    @Test("nil domain → text-note / format / 0.4")
    func nilDomain() {
        let tag = RuleTagger.formatTagFor(domain: nil)
        #expect(tag.name == "text-note")
        #expect(tag.category == "format")
        #expect(tag.weight == 0.4)
    }

    @Test("empty string domain → text-note")
    func emptyDomain() {
        #expect(RuleTagger.formatTagFor(domain: "").name == "text-note")
    }

    @Test("github.com → github / format / 0.5")
    func knownHostGithub() {
        let tag = RuleTagger.formatTagFor(domain: "github.com")
        #expect(tag.name == "github")
        #expect(tag.category == "format")
        #expect(tag.weight == 0.5)
    }

    @Test("youtube.com → youtube")
    func knownHostYoutube() {
        #expect(RuleTagger.formatTagFor(domain: "youtube.com").name == "youtube")
    }

    @Test("youtu.be → youtube")
    func knownHostYoutu() {
        #expect(RuleTagger.formatTagFor(domain: "youtu.be").name == "youtube")
    }

    @Test("unknown host → website / format / 0.4")
    func unknownHost() {
        let tag = RuleTagger.formatTagFor(domain: "mysite.com")
        #expect(tag.name == "website")
        #expect(tag.category == "format")
        #expect(tag.weight == 0.4)
    }
}

@Suite("RuleTagger: mineSubjectKeywords")
struct SubjectMiningTests {

    @Test("Title mining produces correct decreasing weights")
    func titleWeights() {
        let tags = RuleTagger.mineSubjectKeywords(
            from: "swift design patterns",
            limit: 5, minLen: 3,
            weightStart: 0.8, weightStep: 0.1, weightFloor: 0.5,
            extraStops: []
        )
        #expect(tags.count == 3)
        #expect(tags[0] == TagSpec(name: "swift", category: "subject", weight: 0.8))
        #expect(tags[1] == TagSpec(name: "design", category: "subject", weight: 0.7))
        #expect(tags[2] == TagSpec(name: "patterns", category: "subject", weight: 0.6))
    }

    @Test("Weight floor clamps at weightFloor")
    func weightFloor() {
        let tags = RuleTagger.mineSubjectKeywords(
            from: "alpha beta gamma delta epsilon zeta eta theta iota kappa",
            limit: 10, minLen: 3,
            weightStart: 0.8, weightStep: 0.1, weightFloor: 0.5,
            extraStops: []
        )
        for tag in tags { #expect(tag.weight >= 0.5) }
    }

    @Test("Limit is respected")
    func limitCap() {
        let tags = RuleTagger.mineSubjectKeywords(
            from: "alpha beta gamma delta epsilon zeta eta theta iota kappa",
            limit: 5, minLen: 3,
            weightStart: 0.8, weightStep: 0.1, weightFloor: 0.5,
            extraStops: []
        )
        #expect(tags.count == 5)
    }

    @Test("STOP_WORDS are filtered")
    func stopWordsFiltered() {
        let tags = RuleTagger.mineSubjectKeywords(
            from: "the and for typography design",
            limit: 5, minLen: 3,
            weightStart: 0.8, weightStep: 0.1, weightFloor: 0.5,
            extraStops: []
        )
        let names = tags.map(\.name)
        #expect(!names.contains("the"))
        #expect(!names.contains("and"))
        #expect(!names.contains("for"))
        #expect(names.contains("typography"))
        #expect(names.contains("design"))
    }

    @Test("extraStops are filtered")
    func extraStopsFiltered() {
        let tags = RuleTagger.mineSubjectKeywords(
            from: "design tool building",
            limit: 5, minLen: 3,
            weightStart: 0.8, weightStep: 0.1, weightFloor: 0.5,
            extraStops: ["design", "building"]
        )
        let names = tags.map(\.name)
        #expect(!names.contains("design"))
        #expect(!names.contains("building"))
        #expect(names.contains("tool"))
    }

    @Test("minLen filters words shorter than threshold")
    func minLen() {
        let tags = RuleTagger.mineSubjectKeywords(
            from: "ui ux design",
            limit: 5, minLen: 3,
            weightStart: 0.8, weightStep: 0.1, weightFloor: 0.5,
            extraStops: []
        )
        let names = tags.map(\.name)
        #expect(!names.contains("ui"))
        #expect(!names.contains("ux"))
        #expect(names.contains("design"))
    }

    @Test("Description mining: weightStep 0 produces flat 0.5")
    func descFlatWeight() {
        let tags = RuleTagger.mineSubjectKeywords(
            from: "design portfolio motion branding",
            limit: 3, minLen: 4,
            weightStart: 0.5, weightStep: 0, weightFloor: 0.5,
            extraStops: RuleTagger.stopWordsExt.union(RuleTagger.platformNoise)
        )
        for tag in tags { #expect(tag.weight == 0.5) }
    }
}

@Suite("RuleTagger: word boundary & rule enrichment")
struct WordBoundaryTests {

    @Test("'swift' matches in phrase")
    func swiftMatches() {
        #expect(RuleTagger.wordBoundaryMatch(pattern: "swift", in: "using swift for ios"))
    }

    @Test("'swift' does NOT match inside 'swiftly'")
    func swiftlyNoMatch() {
        #expect(!RuleTagger.wordBoundaryMatch(pattern: "swift", in: "written swiftly"))
    }

    @Test("'figma' matches exactly")
    func figmaMatches() {
        #expect(RuleTagger.wordBoundaryMatch(pattern: "figma", in: "open in figma today"))
    }

    @Test("'figma' does NOT match 'prefigma'")
    func figmaPrefixNoMatch() {
        #expect(!RuleTagger.wordBoundaryMatch(pattern: "figma", in: "prefigma"))
    }

    @Test("Tool tag produced at weight 0.7")
    func toolTagWeight() {
        let tags = RuleTagger.runRuleEnrichment(
            text: "built with swift", domain: "", existingNames: []
        )
        let swiftTag = tags.first { $0.name == "swift" }
        #expect(swiftTag != nil)
        #expect(swiftTag?.category == "tool")
        #expect(swiftTag?.weight == 0.7)
    }

    @Test("Style tag produced at weight 0.65")
    func styleTagWeight() {
        let tags = RuleTagger.runRuleEnrichment(
            text: "minimalist poster design", domain: "", existingNames: []
        )
        let t = tags.first { $0.name == "minimalist" }
        #expect(t?.category == "style")
        #expect(t?.weight == 0.65)
    }

    @Test("Mood tag produced at weight 0.55")
    func moodTagWeight() {
        let tags = RuleTagger.runRuleEnrichment(
            text: "dark and elegant interface", domain: "", existingNames: []
        )
        let dark = tags.first { $0.name == "dark" }
        #expect(dark?.category == "mood")
        #expect(dark?.weight == 0.55)
    }

    @Test("Location tag produced at weight 0.6")
    func locationTagWeight() {
        let tags = RuleTagger.runRuleEnrichment(
            text: "studio based in tokyo", domain: "", existingNames: []
        )
        let t = tags.first { $0.name == "japan" }
        #expect(t?.category == "location")
        #expect(t?.weight == 0.6)
    }

    @Test("existingNames dedupe prevents re-adding known tags")
    func existingNamesDeduped() {
        let tags = RuleTagger.runRuleEnrichment(
            text: "swift design", domain: "", existingNames: ["swift"]
        )
        #expect(!tags.contains { $0.name == "swift" })
    }
}

@Suite("RuleTagger: TLD fallback")
struct TLDTests {

    @Test(".de domain → germany at weight 0.3")
    func tldGermany() {
        let tags = RuleTagger.runRuleEnrichment(
            text: "neutral content", domain: "example.de", existingNames: []
        )
        let t = tags.first { $0.name == "germany" }
        #expect(t != nil)
        #expect(t?.weight == 0.3)
    }

    @Test(".jp domain → japan")
    func tldJapan() {
        let tags = RuleTagger.runRuleEnrichment(
            text: "neutral content", domain: "example.jp", existingNames: []
        )
        #expect(tags.contains { $0.name == "japan" })
    }

    @Test(".com domain → no TLD location added")
    func tldComNoMatch() {
        let tags = RuleTagger.runRuleEnrichment(
            text: "neutral content", domain: "example.com", existingNames: []
        )
        #expect(!tags.contains { $0.category == "location" && $0.weight == 0.3 })
    }

    @Test(".co.uk domain → uk")
    func tldCoUk() {
        let tags = RuleTagger.runRuleEnrichment(
            text: "neutral content", domain: "bbc.co.uk", existingNames: []
        )
        #expect(tags.contains { $0.name == "uk" })
    }
}

@Suite("RuleTagger: pipeline cap & dedupe")
struct PipelineTests {

    @Test("generateTags: capped to at most 12 tags")
    func capTo12() {
        let title = "figma framer webflow blender react swift minimalist editorial dark vibrant dynamic"
        let desc = "photoshop illustrator procreate gsap cinematic professional"
        let tags = RuleTagger.generateTags(title: title, description: desc, domain: "github.com")
        #expect(tags.count <= 12)
    }

    @Test("generateTags: no duplicate names")
    func noDuplicates() {
        let tags = RuleTagger.generateTags(
            title: "github design tool",
            description: "github portfolio site",
            domain: "github.com"
        )
        let names = tags.map(\.name)
        #expect(names.count == Set(names).count)
    }

    @Test("generateTags: domain tag has weight 0.6")
    func domainWeight() {
        let tags = RuleTagger.generateTags(title: "Test Item", description: nil, domain: "example.com")
        let dt = tags.first { $0.category == "domain" }
        #expect(dt?.name == "example.com")
        #expect(dt?.weight == 0.6)
    }
}

// MARK: - Input Classification Tests

@Suite("CaptureService: input classification")
struct ClassificationTests {

    @Test("Single URL → one .url input")
    func singleURL() {
        let inputs = CaptureService.classify(text: "https://example.com")
        #expect(inputs.count == 1)
        if case .url(let url) = inputs[0] {
            #expect(url.host == "example.com")
        } else {
            Issue.record("Expected .url")
        }
    }

    @Test("Two URLs in text → two .url inputs")
    func twoURLs() {
        let inputs = CaptureService.classify(text: "Check https://a.com and also https://b.com please")
        #expect(inputs.count == 2)
        for input in inputs {
            if case .url = input {} else { Issue.record("Expected .url") }
        }
    }

    @Test("Plain text longer than 5 chars → one .text input")
    func plainText() {
        let inputs = CaptureService.classify(text: "This is a note about typography and design")
        #expect(inputs.count == 1)
        if case .text(let t) = inputs[0] {
            #expect(t.contains("typography"))
        } else {
            Issue.record("Expected .text")
        }
    }

    @Test("Text with 5 or fewer chars → empty (no capture)")
    func shortTextEmpty() {
        #expect(CaptureService.classify(text: "hi").isEmpty)
        #expect(CaptureService.classify(text: "hello").isEmpty)
    }

    @Test("http:// URL is recognised")
    func httpScheme() {
        let inputs = CaptureService.classify(text: "http://example.com/path")
        #expect(inputs.count == 1)
        if case .url = inputs[0] {} else { Issue.record("Expected .url") }
    }
}

// MARK: - OG Parsing Tests

@Suite("CaptureService: OG parsing")
struct OGParsingTests {

    private let base = URL(string: "https://example.com")!

    @Test("og:title with content attribute before property (reversed order)")
    func ogTitleReversedOrder() {
        let html = #"""
        <html><head>
        <meta content="My Reversed Title" property="og:title">
        </head></html>
        """#
        let r = CaptureService.parseOG(html: html, baseURL: base)
        #expect(r.title == "My Reversed Title")
    }

    @Test("og:description parsed normally")
    func ogDescription() {
        let html = #"""
        <html><head>
        <meta property="og:description" content="A great design resource">
        </head></html>
        """#
        #expect(CaptureService.parseOG(html: html, baseURL: base).description == "A great design resource")
    }

    @Test("og:image parsed")
    func ogImage() {
        let html = #"""
        <html><head>
        <meta property="og:image" content="https://example.com/cover.jpg">
        </head></html>
        """#
        let r = CaptureService.parseOG(html: html, baseURL: base)
        #expect(r.imageURL?.absoluteString == "https://example.com/cover.jpg")
    }

    @Test("twitter:image fallback when no og:image")
    func twitterImageFallback() {
        let html = #"""
        <html><head>
        <meta name="twitter:image" content="https://example.com/tw.jpg">
        </head></html>
        """#
        let r = CaptureService.parseOG(html: html, baseURL: base)
        #expect(r.imageURL?.absoluteString == "https://example.com/tw.jpg")
    }

    @Test("og:image takes precedence over twitter:image")
    func ogPrecedenceOverTwitter() {
        let html = #"""
        <html><head>
        <meta property="og:image" content="https://example.com/og.jpg">
        <meta name="twitter:image" content="https://example.com/tw.jpg">
        </head></html>
        """#
        let r = CaptureService.parseOG(html: html, baseURL: base)
        #expect(r.imageURL?.absoluteString == "https://example.com/og.jpg")
    }

    @Test("<title> used as fallback when no og:title")
    func titleFallback() {
        let html = #"""
        <html><head><title>Plain Title Tag</title></head></html>
        """#
        #expect(CaptureService.parseOG(html: html, baseURL: base).title == "Plain Title Tag")
    }

    @Test("name=description parsed")
    func metaNameDescription() {
        let html = #"""
        <html><head>
        <meta name="description" content="Regular meta description here">
        </head></html>
        """#
        #expect(CaptureService.parseOG(html: html, baseURL: base).description == "Regular meta description here")
    }

    @Test("All OG fields together with mixed attribute order")
    func allFieldsMixed() {
        let html = #"""
        <html><head>
        <meta content="Page Title" property="og:title">
        <meta property="og:description" content="Page description">
        <meta content="https://example.com/img.jpg" property="og:image">
        </head></html>
        """#
        let r = CaptureService.parseOG(html: html, baseURL: base)
        #expect(r.title == "Page Title")
        #expect(r.description == "Page description")
        #expect(r.imageURL?.absoluteString == "https://example.com/img.jpg")
    }
}

// MARK: - Slug Tests

@Suite("CaptureService: slug generation")
struct SlugTests {

    @Test("Spaces → hyphens, lowercased")
    func spacesHyphensLower() {
        #expect(CaptureService.makeSlug(from: "Hello World", isUnique: { _ in true }) == "hello-world")
    }

    @Test("Special characters stripped (ASCII only)")
    func specialCharsStripped() {
        #expect(CaptureService.makeSlug(from: "iOS Design!", isUnique: { _ in true }) == "ios-design")
    }

    @Test("Suffix incremented to ensure uniqueness")
    func uniquenessSuffix() {
        let taken = Set(["hello-world", "hello-world-2"])
        let slug = CaptureService.makeSlug(from: "Hello World") { !taken.contains($0) }
        #expect(slug == "hello-world-3")
    }

    @Test("First candidate returned when already unique")
    func firstCandidate() {
        #expect(CaptureService.makeSlug(from: "My Article", isUnique: { _ in true }) == "my-article")
    }

    @Test("All-special title falls back to 'item'")
    func emptyAfterFilter() {
        #expect(CaptureService.makeSlug(from: "!!!", isUnique: { _ in true }) == "item")
    }

    @Test("Consecutive hyphens collapsed")
    func consecutiveHyphens() {
        let slug = CaptureService.makeSlug(from: "Hello   World", isUnique: { _ in true })
        #expect(!slug.contains("--"))
    }
}
