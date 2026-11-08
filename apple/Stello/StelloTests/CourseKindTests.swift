import Testing
import Foundation
import SwiftData
@testable import Stello

// MARK: - Readers

@Suite("Course readers")
struct CourseReaderTests {

    @Test("Kind line variants: provider · format, else duration, else price")
    func kindLine() {
        var meta = CourseMeta()
        #expect(meta.cardKindLine == nil)
        meta.provider = ToolReader.makerRef("Maven")
        #expect(meta.cardKindLine == "Maven")
        meta.isFree = true
        #expect(meta.cardKindLine == "Maven · Free")
        meta.durationMinutes = 330
        #expect(meta.cardKindLine == "Maven · 5 h 30 min")
        meta.format = "cohort"
        #expect(meta.cardKindLine == "Maven · Cohort")
        meta.provider = nil
        #expect(meta.cardKindLine == "Cohort")

        var length = CourseMeta()
        length.durationMinutes = 45
        #expect(length.durationLine == "45 min")
        length.lessons = 1
        #expect(length.lengthLine == "1 lesson · 45 min")
        length.durationMinutes = nil
        length.durationText = "6 weeks"
        length.lessons = 24
        #expect(length.lengthLine == "24 lessons · 6 weeks")

        var price = CourseMeta()
        price.isFree = false
        #expect(price.priceLine == "Paid")
        price.price = "1500"
        price.currency = "USD"
        #expect(price.priceLine == "$1,500")
        #expect(CourseMeta(format: "video series").formatLabel == "Video series")
    }

    @Test("Rule-based guess: cohort / self-paced words, 'N lessons', 'N hours of video'")
    func ruleBasedGuess() {
        let cohort = CourseReader.ruleBasedFacts(
            text: "Join the next cohort with weekly live sessions. 24 video lessons and 6 hours of video."
        )
        #expect(cohort == CourseFacts(format: "cohort", durationText: "6 hours", topics: [], lessons: 24))
        let selfPaced = CourseReader.ruleBasedFacts(text: "Learn at your own pace. 1 hour of content.")
        #expect(selfPaced == CourseFacts(format: "self-paced", durationText: "1 hour", topics: [], lessons: nil))
        #expect(CourseReader.ruleBasedFacts(text: "A beautiful course about type.") == nil)
        #expect(CourseReader.ruleBasedFacts(text: nil) == nil)
    }

    @Test("Guess fills only empty fields and marks them; read values win")
    func applyGuess() {
        var meta = CourseMeta()
        meta.lessons = 12
        CourseReader.applyGuess(
            CourseFacts(format: "Cohort-based", durationText: "6 weeks", topics: ["Figma", "figma", "Variables"], lessons: 30),
            to: &meta
        )
        #expect(meta.format == "cohort")
        #expect(meta.formatIsGuess)
        #expect(meta.durationText == "6 weeks")
        #expect(meta.durationIsGuess)
        #expect(meta.topics == ["Figma", "Variables"])
        #expect(meta.topicsAreGuess)
        #expect(meta.lessons == 12)
        #expect(!meta.lessonsIsGuess)

        var read = CourseMeta()
        read.format = "self-paced"
        read.durationMinutes = 300
        read.topics = ["React"]
        CourseReader.applyGuess(CourseFacts(format: "cohort", durationText: "6 weeks", topics: ["Vue"]), to: &read)
        #expect(read.format == "self-paced")
        #expect(!read.formatIsGuess)
        #expect(read.durationText == nil)
        #expect(read.topics == ["React"])
        #expect(!CourseReader.needsGuess(read))

        #expect(CourseReader.normalizeFormat("On-demand video course") == "self-paced")
        #expect(CourseReader.normalizeFormat("Live workshop") == "workshop")
        #expect(CourseReader.normalizeFormat("Certificate programme") == "program")
        #expect(CourseReader.normalizeFormat("video series") == "video series")
        #expect(CourseReader.normalizeFormat("online") == nil)
    }

    @Test("A refetch that reads less never erases what capture read; guesses survive")
    func merge() {
        var previous = CourseMeta()
        previous.provider = ToolReader.makerRef("Maven")
        previous.format = "cohort"
        previous.formatIsGuess = true
        previous.topics = ["Figma"]
        previous.topicsAreGuess = true
        previous.durationMinutes = 300
        var fresh = CourseMeta()
        fresh.lessons = 10
        let merged = CourseReader.merge(fresh: fresh, previous: previous)
        #expect(merged.provider?.name == "Maven")
        #expect(merged.format == "cohort")
        #expect(merged.formatIsGuess)
        #expect(merged.topics == ["Figma"])
        #expect(merged.topicsAreGuess)
        #expect(merged.durationMinutes == 300)
        #expect(merged.lessons == 10)
    }
}

// MARK: - Item level + refresh

@Suite("Course items")
struct CourseItemTests {

    @Test("Item kind line, typed panel, domain pill and search")
    @MainActor
    func itemLevel() {
        var meta = CourseMeta()
        meta.name = "Shift Nudge"
        meta.provider = EntityRef(name: "Shift Nudge", kind: "organization", url: "https://shiftnudge.com")
        meta.instructor = ArticleReader.authorRef("Matt D. Smith")
        meta.lessons = 234
        meta.level = "beginner"
        meta.isFree = true
        meta.topics = ["Interface design", "Typography", "Color", "Layout"]
        let item = Item(title: "Shift Nudge", sourceURL: "https://shiftnudge.com/", domain: "shiftnudge.com", kind: ItemKind.course.rawValue)
        item.setMetadata(meta)

        #expect(item.courseMeta() != nil)
        #expect(item.articleMeta() == nil)
        #expect(item.cardKindLine == "Shift Nudge · Free")
        #expect(item.hasRichTypedPanel)
        #expect(item.displayLink == "shiftnudge.com")
        for query in ["matt d. smith", "typography", "beginner"] {
            #expect(ItemFilter.apply([item], searchText: query, selectedTagNames: []).count == 1, "\(query)")
        }
    }

    @Test("Guess job: the rule-based pass fills format / lessons / duration as guesses")
    @MainActor
    func guessJob() async throws {
        let item = Item(title: "Design Systems", sourceURL: "https://example.com/courses/design-systems", kind: ItemKind.course.rawValue)
        item.setMetadata(CourseMeta())
        item.extractedText = "Join the next cohort: six weeks of live sessions. 18 lessons and 12 hours of video."

        await EnrichmentService.applyCourseGuessIfNeeded(item: item, enricher: RuleBasedFallbackEnricher())
        #expect(item.courseMeta()?.format == "cohort")
        #expect(item.courseMeta()?.formatIsGuess == true)
        #expect(item.courseMeta()?.lessons == 18)
        #expect(item.courseMeta()?.lessonsIsGuess == true)
        #expect(item.courseMeta()?.durationText == "12 hours")
        #expect(item.courseMeta()?.durationIsGuess == true)

        // The mock model gives nothing → the rule-based pass still runs.
        let other = Item(title: "Type", sourceURL: "https://example.com/courses/type", kind: ItemKind.course.rawValue)
        other.setMetadata(CourseMeta())
        other.extractedText = "A self-paced course. Learn at your own pace."
        await EnrichmentService.applyCourseGuessIfNeeded(item: other, enricher: MockEnricher())
        #expect(other.courseMeta()?.format == "self-paced")
        #expect(other.courseMeta()?.formatIsGuess == true)
    }
}
