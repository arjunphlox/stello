import Testing
import Foundation
@testable import Stello

@Suite("Panel dedupe")
struct PanelDedupeTests {

    @Test("normalize: entities, URL forms, @handle, punctuation and whitespace")
    func normalize() {
        #expect(PanelDedupe.normalize("Fish &amp; Chips &gt; all") == "fish chips all")
        #expect(PanelDedupe.normalize("https://www.X.com/") == "x com")
        #expect(PanelDedupe.normalize("x.com") == "x com")
        #expect(PanelDedupe.normalize("http://www.example.com/path/") == PanelDedupe.normalize("example.com/path"))
        #expect(PanelDedupe.normalize("@nickfloats") == "nickfloats")
        #expect(PanelDedupe.normalize("  Nick   St. Pierre · @nickfloats ") == "nick st pierre nickfloats")
        #expect(PanelDedupe.normalize("") == "")
    }

    @Test("isRedundant (prose): equal, a cut-off copy, and short values")
    func isRedundant() {
        let text = "Made a free Midjourney Style Reference Tool with fifteen thousand srefs and smart AI search"
        // Equal after normalising.
        #expect(PanelDedupe.isRedundant("X.com", against: ["https://www.x.com/"]))
        #expect(PanelDedupe.isRedundant("@nickfloats", against: ["nickfloats"]))
        // A cut-off copy of a longer text (the 200-character og description).
        #expect(PanelDedupe.isRedundant(String(text.prefix(40)), against: [text]))
        #expect(PanelDedupe.isRedundant("Midjourney Style Reference", against: [text]))
        // Values of 2 characters or fewer only match by equality.
        #expect(PanelDedupe.isRedundant("AI", against: [text]) == false)
        #expect(PanelDedupe.isRedundant("x", against: ["x"]))
        // A short value inside a word doesn't count.
        #expect(PanelDedupe.isRedundant("free", against: ["freedom of type"]) == false)
        #expect(PanelDedupe.isRedundant("Free", against: ["Mac · Free"]))
        // Unrelated values and empty input.
        #expect(PanelDedupe.isRedundant("Typography", against: [text]) == false)
        #expect(PanelDedupe.isRedundant("", against: [text]) == false)
    }

    @Test("isSameValue: facts repeat only on equality, never by containment")
    func isSameValue() {
        let text = "Made a free Midjourney Style Reference Tool with fifteen thousand srefs and smart AI search"
        #expect(PanelDedupe.isSameValue("X.com", against: ["https://www.x.com/"]))
        #expect(PanelDedupe.isSameValue("Fish &amp; Chips", against: ["fish & chips"]))
        // A short fact contained in a long text is NOT redundant under the fact rule…
        #expect(PanelDedupe.isSameValue("Midjourney", against: [text]) == false)
        // …though the prose rule would call it a repeat.
        #expect(PanelDedupe.isRedundant("Midjourney", against: [text]))
        // An album name inside the track's summary still shows as its own row.
        #expect(PanelDedupe.isSameValue("Hybrid Theory", against: ["In the End · Linkin Park · Hybrid Theory · 2000"]) == false)
        #expect(PanelDedupe.isSameValue("", against: [""]) == false)
    }

    @Test("factKey: numbers and yes/no keyed with their label; other values by themselves")
    func factKey() {
        #expect(PanelDedupe.factKey(label: "Weights", value: "12") != PanelDedupe.factKey(label: "Styles", value: "12"))
        #expect(PanelDedupe.factKey(label: "Release year", value: "2019") == PanelDedupe.factKey(label: "Release year", value: "2019"))
        #expect(PanelDedupe.factKey(label: "Trial", value: "Yes") != PanelDedupe.factKey(label: "Student discount", value: "Yes"))
        #expect(PanelDedupe.factKey(label: "Price", value: "Free") == PanelDedupe.factKey(label: "Paid / free", value: "free"))
        #expect(PanelDedupe.factKey(label: "Location", value: "Berlin, Germany")
            == PanelDedupe.factKey(label: "Geography", value: "Berlin Germany"))
        #expect(PanelDedupe.factKey(label: "Price range", value: "$$") != PanelDedupe.factKey(label: "Price range", value: "$$$"))
    }

    @Test("filterTags: host, handle and model hidden when shown; unrelated tags kept")
    func filterTags() {
        let shown = ["x.com", "Nick St. Pierre · @nickfloats", "Midjourney", "dribbble.com"]
        let kept = PanelDedupe.filterTags(
            ["x.com", "nickfloats", "midjourney", "Midjourney", "dribbble", "typography", "ai-art"],
            shown: shown
        )
        #expect(kept == ["typography", "ai-art"])
        // Nothing shown: every tag stays.
        #expect(PanelDedupe.filterTags(["x.com", "nickfloats"], shown: []) == ["x.com", "nickfloats"])
        // A word of a long text doesn't hide a tag.
        #expect(PanelDedupe.filterTags(
            ["typography"],
            shown: ["A long description about typography in modern editorial design"]
        ) == ["typography"])
    }

    @Test("primaryText: the first non-empty candidate; the rest without repeats")
    func primaryText() {
        #expect(PanelDedupe.primaryText(candidates: [nil, "  ", "Tagline", "Overview"]) == "Tagline")
        #expect(PanelDedupe.primaryText(candidates: [nil, ""]) == nil)
        let split = PanelDedupe.primaryAndRest(candidates: [
            "A fast issue tracker for teams",
            "A fast issue tracker",
            nil,
            "Built by Linear Orbit",
        ])
        #expect(split.primary == "A fast issue tracker for teams")
        #expect(split.rest == ["Built by Linear Orbit"])
    }

    @Test("namesSameSite and isSameURL")
    func sameSite() {
        #expect(PanelDedupe.namesSameSite("X", host: "x.com"))
        #expect(PanelDedupe.namesSameSite("Instagram", host: "instagram.com"))
        #expect(PanelDedupe.namesSameSite("Frontend Masters", host: "frontendmasters.com"))
        #expect(PanelDedupe.namesSameSite("simonwillison.net", host: "simonwillison.net"))
        #expect(PanelDedupe.namesSameSite("The Verge", host: "simonwillison.net") == false)
        #expect(PanelDedupe.isSameURL("https://www.example.com/a/", "http://example.com/a"))
        #expect(PanelDedupe.isSameURL("https://example.com/a", "https://example.com/b") == false)
        #expect(PanelDedupe.isSameURL(nil, "https://example.com") == false)
    }
}
