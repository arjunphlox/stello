import Testing
import Foundation
import SwiftData
@testable import Stello

// MARK: - Helpers

private func classify(
    _ urlString: String,
    html: String = "<html><head></head><body></body></html>",
    ogType: String? = nil,
    labels: [String] = [],
    title: String = "Some page"
) -> PageClassificationResult {
    let url = URL(string: urlString)!
    return PageClassifier.classify(
        html: html,
        baseURL: url,
        domain: url.host,
        title: title,
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

private func buildCourse(
    _ urlString: String,
    finalURL: String? = nil,
    html: String = "",
    ogTitle: String? = nil,
    now: Date = utcDate(2026, 10, 1)
) -> CourseMeta {
    CourseReader.build(
        sourceURL: URL(string: urlString)!,
        finalURL: finalURL.flatMap { URL(string: $0) },
        html: html,
        ogTitle: ogTitle,
        now: now
    ).meta
}

private func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

// MARK: - Fixtures

private let frontendMastersURL = "https://frontendmasters.com/courses/complete-react-v9/"
private let shiftNudgeURL = "https://shiftnudge.com/"
private let mavenURL = "https://maven.com/jane-builder/ai-engineering"
private let webflowURL = "https://university.webflow.com/courses/webflow-101"

private let frontendMastersJSONLD = #"""
{"@context":"https://schema.org","@type":"Course","name":"Complete Intro to React, v9",
 "description":"Learn React from the ground up.",
 "provider":{"@type":"Organization","name":"Frontend Masters","sameAs":"https://frontendmasters.com"},
 "author":{"@type":"Person","name":"Brian Holt","url":"https://frontendmasters.com/teachers/brian-holt/"},
 "timeRequired":"PT5H","isAccessibleForFree":false,
 "offers":{"@type":"Offer","category":"Subscription","price":"39","priceCurrency":"USD"},
 "hasCourseInstance":{"@type":"CourseInstance","courseMode":"online","courseWorkload":"PT5H"}}
"""#

private let shiftNudgeJSONLD = #"""
{"@context":"https://schema.org","@type":"Course","name":"Shift Nudge",
 "description":"Interface design course.",
 "provider":{"@type":"Organization","name":"Shift Nudge","sameAs":"https://shiftnudge.com"},
 "author":{"@type":"Person","name":"Matt D. Smith"},
 "courseMode":"online","educationalLevel":"beginner","numberOfLessons":234,
 "teaches":["Interface design","Typography","Color","Layout"],
 "isAccessibleForFree":true}
"""#

private let mavenJSONLD = #"""
{"@context":"https://schema.org","@graph":[
 {"@type":"Course","name":"AI Engineering Bootcamp",
  "provider":{"@type":"Organization","name":"Maven","url":"https://maven.com"},
  "instructor":[{"@type":"Person","name":"Jane Builder","url":"https://maven.com/jane-builder"},
                {"@type":"Person","name":"Second Teacher"}],
  "offers":{"@type":"Offer","price":"1500","priceCurrency":"USD"}},
 {"@type":"EducationEvent","name":"AI Engineering Bootcamp — Cohort 4",
  "startDate":"2026-11-03T17:00:00Z","endDate":"2026-12-15T19:00:00Z"}
]}
"""#

private let webflowJSONLD = #"""
{"@context":"https://schema.org","@type":"Course","name":"Webflow 101",
 "provider":{"@type":"Organization","name":"Webflow University","sameAs":"https://university.webflow.com"}}
"""#

// MARK: - Classification

@Suite("Course classification")
struct CourseClassificationTests {

    @Test("Course JSON-LD → course (top level and inside @graph)")
    func courseJSONLD() {
        let top = jsonLD(#"{"@context":"https://schema.org","@type":"Course","name":"Motion basics"}"#)
        #expect(classify("https://example.com/motion-basics", html: top).kind == .course)
        let graph = jsonLD(#"{"@context":"https://schema.org","@graph":[{"@type":"WebPage"},{"@type":"Course","name":"x"}]}"#)
        #expect(classify("https://example.com/motion-basics", html: graph).kind == .course)
        #expect(classify(mavenURL, html: jsonLD(mavenJSONLD)).kind == .course)
    }

    @Test("Frontend Masters: /courses/<slug> → course; blog posts and the home page are not")
    func frontendMasters() {
        #expect(classify(frontendMastersURL).kind == .course)
        #expect(classify("https://frontendmasters.com/blog/react-19-and-the-compiler/").kind == .article)
        #expect(classify("https://frontendmasters.com/").kind != .course)
        #expect(classify("https://frontendmasters.com/courses/").kind != .course)
    }

    @Test("Big multi-purpose hosts need a course path")
    func multiPurposeHosts() {
        for url in [
            "https://www.udemy.com/course/the-web-developer-bootcamp/",
            "https://www.coursera.org/learn/machine-learning",
            "https://www.domestika.org/en/courses/1234-motion-design-basics",
            "https://www.skillshare.com/en/classes/branding-101/123456",
            "https://egghead.io/courses/build-a-react-app",
            webflowURL,
        ] {
            #expect(classify(url).kind == .course, "\(url)")
        }
        for url in [
            "https://www.udemy.com/user/jane-doe/",
            "https://www.coursera.org/",
            "https://www.domestika.org/en/blog/1234-color-theory",
            "https://www.skillshare.com/en/browse/design",
            "https://egghead.io/q/react",
        ] {
            #expect(classify(url).kind != .course, "\(url)")
        }
    }

    @Test("Maven: /<instructor>/<slug> → course; site pages and profiles are not")
    func maven() {
        #expect(classify(mavenURL).kind == .course)
        #expect(classify("https://maven.com/jane-builder").kind != .course)
        #expect(classify("https://maven.com/blog/how-cohorts-work").kind != .course)
        #expect(classify("https://maven.com/categories/engineering").kind != .course)
    }

    @Test("Single-purpose course sites count on any non-blog path")
    func singlePurposeHosts() {
        for url in [
            "https://shiftnudge.com/",
            "https://www.superhi.com/courses/intro-to-web",
            "https://thebasics.dev/",
            "https://designcourse.com/ui-ux-fundamentals",
        ] {
            #expect(classify(url).kind == .course, "\(url)")
        }
        #expect(classify("https://shiftnudge.com/blog/designing-with-grids").kind == .article)
        #expect(classify("https://www.joshwcomeau.com/courses/").kind == .course)
        #expect(classify("https://www.joshwcomeau.com/css/center-a-div/").kind != .course)
    }

    @Test("A Motion Design School course page with og:type article → course")
    func motionDesignSchool() {
        let html = metas([("og:type", "article"), ("author", "Motion Design School")])
        let result = classify("https://motiondesign.school/products/cinema-4d-basecamp", html: html, ogType: "article")
        #expect(result.kind == .course)
    }

    @Test("LABASAD master page: education label + 'Master' in the title → course")
    func labasad() {
        let url = "https://www.labasad.com/en/master/master-in-illustration/"
        let html = metas([("og:type", "article"), ("author", "LABASAD")])
        let result = classify(
            url, html: html, ogType: "article", labels: ["education"], title: "Master in Illustration | LABASAD"
        )
        #expect(result.kind == .course)
        // "Mastering" is not the whole word "master".
        #expect(classify(
            "https://example.com/mastering-grids", labels: ["education"], title: "Mastering grids"
        ).kind == .link)
    }

    @Test("Course path segments: followed by a slug or last with something before; never on a blog")
    func pathSegments() {
        for url in [
            "https://example.com/courses/motion-basics",
            "https://example.com/en/course/motion-basics",
            "https://example.com/program/ux-design",
            "https://example.com/programs/ux-design",
            "https://example.com/design/masterclass",
            "https://example.com/bootcamp/frontend",
            "https://example.com/events/workshop",
        ] {
            #expect(classify(url).kind == .course, "\(url)")
        }
        for url in [
            "https://example.com/courses",
            "https://example.com/courses/",
            "https://example.com/courses/page/2",
            "https://example.com/blog/courses/my-favourites",
            "https://example.com/2025/03/workshop/recap",
            "https://example.com/courses-i-like",
        ] {
            #expect(classify(url).kind != .course, "\(url)")
        }
    }

    @Test("A /program/ path → course with the program format; /workshop → workshop")
    func programFormat() {
        #expect(classify("https://example.com/program/ux-design").kind == .course)
        #expect(buildCourse("https://example.com/program/ux-design").format == "program")
        #expect(buildCourse("https://example.com/events/workshop").format == "workshop")
        #expect(buildCourse("https://example.com/courses/motion-basics").format == nil)
    }

    @Test("The education label alone never makes a course; on a blog post it stays an article")
    func educationLabelAlone() {
        #expect(classify("https://example.com/blog/what-i-learned-this-year", labels: ["education"]).kind == .article)
        // Even a course word in the title doesn't override a blog / dated URL.
        #expect(classify(
            "https://example.com/blog/how-i-learn-design", labels: ["education"], title: "How I learn design"
        ).kind == .article)
        #expect(classify("https://example.com/some-page", labels: ["education"]).kind == .link)
        #expect(classify("https://example.com/some-page", ogType: "article", labels: ["education"]).kind == .link)
    }

    @Test("Education label + a course word in the title on a plain page → course")
    func educationLabelWithTitle() {
        for title in ["Design Systems Course", "Figma Masterclass", "Frontend Bootcamp", "Type Workshop", "Motion Academy", "Learn Rive"] {
            #expect(classify("https://example.com/design-systems", labels: ["education"], title: title).kind == .course, "\(title)")
        }
        // Without the label the title alone decides nothing.
        #expect(classify("https://example.com/design-systems", title: "Design Systems Course").kind == .link)
    }

    @Test("A dated URL with Article JSON-LD and no course signal stays an article")
    func datedArticleStays() {
        let article = jsonLD(#"{"@context":"https://schema.org","@type":"Article","headline":"The best Figma courses"}"#)
        let result = classify(
            "https://example.com/2025/03/best-figma-courses", html: article,
            labels: ["education"], title: "The best Figma courses"
        )
        #expect(result.kind == .article)
    }

    @Test("An EducationEvent node on a course-ish page → course; on an unrelated page it isn't")
    func educationEvent() {
        let event = jsonLD(#"{"@context":"https://schema.org","@type":"EducationEvent","name":"x","startDate":"2026-11-03"}"#)
        #expect(classify("https://example.com/spring-type", html: event, title: "Spring Type Workshop").kind == .course)
        #expect(classify("https://example.com/spring-type", html: event, labels: ["education"]).kind == .course)
        #expect(classify("https://example.com/spring-type", html: event).kind == .link)
    }

    @Test("A course page that also carries a Product node with offers → course, not product")
    func courseBeatsProductJSONLD() {
        let html = jsonLD(#"""
        [{"@context":"https://schema.org","@type":"Course","name":"Motion basics"},
         {"@context":"https://schema.org","@type":"Product","name":"Motion basics","offers":{"@type":"Offer","price":"99"}}]
        """#)
        #expect(classify("https://example.com/motion-basics", html: html).kind == .course)
    }

    @Test("A course host's GitHub repo stays a tool; a tweet stays a post")
    func toolAndPostKeepPriority() {
        let course = jsonLD(#"{"@context":"https://schema.org","@type":"Course","name":"React"}"#)
        #expect(classify("https://github.com/FrontendMasters/complete-intro-to-react", html: course).kind == .tool)
        #expect(classify("https://x.com/FrontendMasters/status/1453768926539317251", html: course).kind == .post)
        #expect(classify("https://x.com/FrontendMasters/status/1453768926539317251", labels: ["education"], title: "New course").kind == .post)
    }

    @Test("A bare image file is never a course")
    func bareImage() {
        #expect(classify("https://example.com/courses/cover.png").kind != .course)
    }
}

// MARK: - Readers

@Suite("Course readers")
struct CourseReaderTests {

    @Test("Frontend Masters: author, offers, timeRequired, isAccessibleForFree, hasCourseInstance")
    func frontendMasters() {
        let meta = buildCourse(
            frontendMastersURL, html: jsonLD(frontendMastersJSONLD),
            ogTitle: "Complete Intro to React, v9 | Frontend Masters"
        )
        #expect(meta.name == "Complete Intro to React, v9")
        #expect(meta.provider?.name == "Frontend Masters")
        #expect(meta.provider?.url == "https://frontendmasters.com")
        #expect(meta.instructor?.name == "Brian Holt")
        #expect(meta.instructor?.url == "https://frontendmasters.com/teachers/brian-holt/")
        #expect(meta.instructor?.kind == ItemKind.individual.rawValue)
        #expect(meta.durationMinutes == 300)
        #expect(meta.durationText == nil)
        #expect(meta.format == nil)  // courseMode "online" is not a format
        #expect(meta.isFree == false)
        #expect(meta.price == "39")
        #expect(meta.currency == "USD")
        #expect(meta.cardKindLine == "Frontend Masters · 5 h")
        #expect(meta.priceLine == "$39")
    }

    @Test("Shift Nudge: courseMode, educationalLevel, numberOfLessons, teaches, isAccessibleForFree")
    func shiftNudge() {
        let meta = buildCourse(shiftNudgeURL, html: jsonLD(shiftNudgeJSONLD))
        #expect(meta.name == "Shift Nudge")
        #expect(meta.provider?.name == "Shift Nudge")
        #expect(meta.instructor?.name == "Matt D. Smith")
        #expect(meta.format == nil)
        #expect(meta.level == "Beginner")
        #expect(meta.lessons == 234)
        #expect(meta.topics == ["Interface design", "Typography", "Color", "Layout"])
        #expect(!meta.topicsAreGuess)
        #expect(meta.isFree == true)
        #expect(meta.cardKindLine == "Shift Nudge · Free")
        #expect(meta.lengthLine == "234 lessons")
    }

    @Test("Maven: Course + EducationEvent startDate → cohort, the next start date")
    func maven() {
        let meta = buildCourse(mavenURL, html: jsonLD(mavenJSONLD))
        #expect(meta.name == "AI Engineering Bootcamp")
        #expect(meta.provider?.name == "Maven")
        #expect(meta.instructor?.name == "Jane Builder")
        #expect(meta.instructor?.url == "https://maven.com/jane-builder")
        #expect(meta.format == "cohort")
        #expect(!meta.formatIsGuess)
        #expect(meta.startsAt == utcDate(2026, 11, 3, hour: 17))
        #expect(meta.isFree == false)
        #expect(meta.price == "1500")
        #expect(meta.cardKindLine == "Maven · Cohort")
        // A start date already past at capture isn't kept.
        let later = buildCourse(mavenURL, html: jsonLD(mavenJSONLD), now: utcDate(2027, 1, 1))
        #expect(later.startsAt == nil)
        #expect(later.format == "cohort")
    }

    @Test("Webflow University: provider only")
    func webflowUniversity() {
        let meta = buildCourse(webflowURL, html: jsonLD(webflowJSONLD))
        #expect(meta.name == "Webflow 101")
        #expect(meta.provider?.name == "Webflow University")
        #expect(meta.instructor == nil)
        #expect(meta.format == nil)
        #expect(meta.lessons == nil)
        #expect(meta.durationMinutes == nil)
        #expect(meta.isFree == nil)
        #expect(meta.topics.isEmpty)
        #expect(meta.cardKindLine == "Webflow University")
    }

    @Test("No JSON-LD: og:title cleaned, provider from og:site_name or the known host")
    func ogFallbacks() {
        let fm = buildCourse(frontendMastersURL, ogTitle: "Complete Intro to React, v9 | Frontend Masters")
        #expect(fm.name == "Complete Intro to React, v9")
        #expect(fm.provider?.name == "Frontend Masters")
        let site = buildCourse(
            "https://example.com/courses/motion-basics",
            html: metas([("og:site_name", "Motion Lab"), ("author", "Jane Doe")]),
            ogTitle: "Motion Basics - Motion Lab"
        )
        #expect(site.name == "Motion Basics")
        #expect(site.provider?.name == "Motion Lab")
        #expect(site.instructor?.name == "Jane Doe")
        #expect(buildCourse("https://www.example.com/courses/x").provider?.name == "example.com")
    }

    @Test("Name cleaning: ' | Site' always, ' - Provider' only when it names the provider")
    func cleanName() {
        let names = ["Shift Nudge", "shiftnudge.com"]
        #expect(CourseReader.cleanName("Design Systems - Shift Nudge", providerNames: names) == "Design Systems")
        #expect(CourseReader.cleanName("Design Systems — Shift Nudge", providerNames: names) == "Design Systems")
        #expect(CourseReader.cleanName("Shift Nudge - Interface Design Course", providerNames: names)
            == "Shift Nudge - Interface Design Course")
        #expect(CourseReader.cleanName("The Web Developer Bootcamp | Udemy", providerNames: ["udemy.com"])
            == "The Web Developer Bootcamp")
        #expect(CourseReader.cleanName("  ", providerNames: names) == nil)
    }

    @Test("Instructor: never the provider itself; meta author fallback")
    func instructor() {
        let orgAuthor = jsonLD(#"""
        {"@type":"Course","name":"x","provider":{"@type":"Organization","name":"Shift Nudge"},
         "author":{"@type":"Organization","name":"Shift Nudge"}}
        """#)
        #expect(buildCourse(shiftNudgeURL, html: orgAuthor).instructor == nil)
        let instance = jsonLD(#"""
        {"@type":"Course","name":"x","hasCourseInstance":[{"@type":"CourseInstance","instructor":{"@type":"Person","name":"Ada"}}]}
        """#)
        #expect(buildCourse("https://example.com/courses/x", html: instance).instructor?.name == "Ada")
    }

    @Test("Format from courseMode words; online / onsite / blended aren't formats")
    func courseMode() {
        #expect(CourseReader.format(fromCourseMode: "Self-paced") == "self-paced")
        #expect(CourseReader.format(fromCourseMode: "on demand") == "self-paced")
        #expect(CourseReader.format(fromCourseMode: ["online", "Cohort-based"]) == "cohort")
        #expect(CourseReader.format(fromCourseMode: "Live online") == "cohort")
        #expect(CourseReader.format(fromCourseMode: "asynchronous") == "self-paced")
        #expect(CourseReader.format(fromCourseMode: "synchronous") == "cohort")
        for mode in ["online", "Onsite", "blended", "https://schema.org/Online"] {
            #expect(CourseReader.format(fromCourseMode: mode) == nil, "\(mode)")
        }
        let instanceMode = jsonLD(#"""
        {"@type":"Course","name":"x","hasCourseInstance":{"@type":"CourseInstance","courseMode":"Self-paced"}}
        """#)
        #expect(buildCourse("https://example.com/courses/x", html: instanceMode).format == "self-paced")
    }

    @Test("Lessons: numberOfLessons, else lesson-typed hasPart items")
    func lessons() {
        let parts = jsonLD(#"""
        {"@type":"Course","name":"x","hasPart":[{"@type":"LearningResource","name":"1"},
         {"@type":"VideoObject","name":"2"},{"@type":"LearningResource","name":"3"}]}
        """#)
        #expect(buildCourse("https://example.com/courses/x", html: parts).lessons == 3)
        let modules = jsonLD(#"{"@type":"Course","name":"x","hasPart":[{"@type":"Course","name":"Module 1"}]}"#)
        #expect(buildCourse("https://example.com/courses/x", html: modules).lessons == nil)
        let stringCount = jsonLD(#"{"@type":"Course","name":"x","numberOfLessons":"42"}"#)
        #expect(buildCourse("https://example.com/courses/x", html: stringCount).lessons == 42)
    }

    @Test("Level and topics shapes: DefinedTerm, keywords string / array, about")
    func levelAndTopics() {
        let html = jsonLD(#"""
        {"@type":"Course","name":"x",
         "educationalLevel":{"@type":"DefinedTerm","name":"intermediate"},
         "teaches":[{"@type":"DefinedTerm","name":"Rive"},"State machines"],
         "keywords":"motion, Rive , interaction",
         "about":[{"@type":"Thing","name":"Animation"}]}
        """#)
        let meta = buildCourse("https://example.com/courses/x", html: html)
        #expect(meta.level == "Intermediate")
        #expect(meta.topics == ["Rive", "State machines", "motion", "interaction", "Animation"])
        let array = jsonLD(#"{"@type":"Course","name":"x","keywords":["a11y","CSS"]}"#)
        #expect(buildCourse("https://example.com/courses/x", html: array).topics == ["a11y", "CSS"])
    }

    @Test("ISO 8601 durations: minutes for H/M/S, text for D/W/M/Y")
    func durations() {
        #expect(CourseReader.parseDuration("PT5H30M") == CourseDuration(minutes: 330))
        #expect(CourseReader.parseDuration("PT45M") == CourseDuration(minutes: 45))
        #expect(CourseReader.parseDuration("PT5H") == CourseDuration(minutes: 300))
        #expect(CourseReader.parseDuration("pt1h30m15s") == CourseDuration(minutes: 90))
        #expect(CourseReader.parseDuration("PT90S") == CourseDuration(minutes: 2))
        #expect(CourseReader.parseDuration("PT2.5H") == CourseDuration(minutes: 150))
        #expect(CourseReader.parseDuration("P2W") == CourseDuration(text: "2 weeks"))
        #expect(CourseReader.parseDuration("P1W") == CourseDuration(text: "1 week"))
        #expect(CourseReader.parseDuration("P3D") == CourseDuration(text: "3 days"))
        #expect(CourseReader.parseDuration("P1DT2H") == CourseDuration(text: "1 day 2 h"))
        #expect(CourseReader.parseDuration("P1.5W") == CourseDuration(text: "1.5 weeks"))
        #expect(CourseReader.parseDuration("P6M") == CourseDuration(text: "6 months"))
        #expect(CourseReader.parseDuration("5 hours") == CourseDuration(text: "5 hours"))
        for bad in ["PT0S", "P", "PT", "PT5X", "P5", "nonsense", ""] {
            #expect(CourseReader.parseDuration(bad) == CourseDuration(), "\(bad)")
        }
        #expect(CourseReader.parseDuration(nil) == CourseDuration())
        // Weeks / days from timeRequired land in durationText, minutes stay nil.
        let weeks = jsonLD(#"{"@type":"Course","name":"x","timeRequired":"P6W"}"#)
        let meta = buildCourse("https://example.com/courses/x", html: weeks)
        #expect(meta.durationMinutes == nil)
        #expect(meta.durationText == "6 weeks")
    }

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

    @Test("Canonical URL: set when the final URL differs, else nil")
    func canonical() {
        let landed = "https://frontendmasters.com/courses/complete-react-v9/?utm=x"
        #expect(buildCourse(frontendMastersURL, finalURL: landed).canonicalURL == landed)
        #expect(buildCourse(frontendMastersURL, finalURL: frontendMastersURL).canonicalURL == nil)
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
        let meta = buildCourse(shiftNudgeURL, html: jsonLD(shiftNudgeJSONLD))
        let item = Item(title: "Shift Nudge", sourceURL: shiftNudgeURL, domain: "shiftnudge.com", kind: ItemKind.course.rawValue)
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

    @Test("Refresh flips a link to course, and an article on a course host; curated kinds never flip")
    @MainActor
    func refresh() async throws {
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)

        let link = Item(title: "React", sourceURL: frontendMastersURL, kind: ItemKind.link.rawValue)
        let article = Item(title: "Basecamp", sourceURL: "https://motiondesign.school/products/cinema-4d-basecamp", kind: ItemKind.article.rawValue)
        let website = Item(title: "Frontend Masters", sourceURL: frontendMastersURL, kind: ItemKind.website.rawValue)
        let blogArticle = Item(title: "React 19", sourceURL: "https://frontendmasters.com/blog/react-19/", kind: ItemKind.article.rawValue)
        for item in [link, article, website, blogArticle] { context.insert(item) }
        try context.save()

        let page = PageFetchResult(
            html: jsonLD(frontendMastersJSONLD),
            og: OGResult(title: "Complete Intro to React, v9 | Frontend Masters"),
            statusCode: 200
        )
        let url = URL(string: frontendMastersURL)!
        #expect(await EnrichmentService.refreshCourseIfClassified(item: link, context: context, url: url, page: page))
        #expect(link.kind == ItemKind.course.rawValue)
        #expect(link.courseMeta()?.instructor?.name == "Brian Holt")

        // An article from an earlier build on a course host becomes a course.
        let mdsPage = PageFetchResult(
            html: metas([("og:type", "article"), ("author", "Motion Design School")]),
            og: OGResult(title: "Cinema 4D Basecamp", ogType: "article"),
            statusCode: 200
        )
        #expect(await EnrichmentService.refreshCourseIfClassified(
            item: article, context: context,
            url: URL(string: "https://motiondesign.school/products/cinema-4d-basecamp")!, page: mdsPage
        ))
        #expect(article.kind == ItemKind.course.rawValue)
        #expect(article.courseMeta()?.provider?.name == "Motion Design School")

        #expect(await EnrichmentService.refreshCourseIfClassified(
            item: website, context: context, url: url, page: page
        ) == false)
        #expect(website.kind == ItemKind.website.rawValue)

        // A blog article on a course host (no Course JSON-LD) stays an article.
        let blogPage = PageFetchResult(
            html: jsonLD(#"{"@context":"https://schema.org","@type":"BlogPosting","headline":"React 19"}"#),
            og: OGResult(title: "React 19"),
            statusCode: 200
        )
        #expect(await EnrichmentService.refreshCourseIfClassified(
            item: blogArticle, context: context, url: URL(string: "https://frontendmasters.com/blog/react-19/")!,
            page: blogPage
        ) == false)
        #expect(blogArticle.kind == ItemKind.article.rawValue)
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
