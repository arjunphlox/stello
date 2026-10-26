import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Navigation

private struct DetailOpenItemKey: EnvironmentKey {
    static let defaultValue: ((Item) -> Void)? = nil
}

extension EnvironmentValues {
    var detailOpenItem: ((Item) -> Void)? {
        get { self[DetailOpenItemKey.self] }
        set { self[DetailOpenItemKey.self] = newValue }
    }
}

// MARK: - Panel layout

/// The header card: the title once, the kind line, and the main text once (no field labels).
private struct PanelHeader {
    var title: String
    var kindLine: String?
    var mainText: String?
    /// The main text is the article's on-device summary (marked "AI summary").
    var mainTextIsAISummary: Bool = false
    /// Further texts that aren't repeats of the main text (website / typeface only).
    var extraTexts: [String] = []
    /// A Post flagged as AI art with no model and no prompt: a small "AI art" badge line.
    var showsAIArtBadge: Bool = false

    /// Every value the header shows.
    var shownValues: [String] {
        [title, kindLine, mainText].compactMap { $0 } + extraTexts
    }

    /// The texts snippets (and other prose) are checked against.
    var texts: [String] {
        [mainText].compactMap { $0 } + extraTexts
    }
}

/// What one section card after the Summary shows.
private enum PanelSectionBody {
    case facts([(String, String?)])
    /// Chips with an optional caption ("12 weights").
    case chips([String], caption: String?)
    /// Chips that drop chips naming a value the panel already shows (Tech stack).
    case dedupedChips([String])
    case refs([EntityRef])
    /// Prose; dropped when the header's texts already hold it.
    case text(String)
    case gallery([String])
    case faqs([FAQItem])
    /// Chips and rows in one card (typeface "Formats & tech").
    case chipsAndFacts([String], [(String, String?)])
}

/// One section card of a dossier kind (typeface, website, individual, studio, foundry), in the
/// order the panel had before the de-duplication pass.
private struct PanelSection {
    var title: String
    var body: PanelSectionBody
}

/// What one kind contributes to the panel before de-duplication.
private struct KindPanelInput {
    var titleOverride: String?
    var mainCandidates: [String?] = []
    /// Show the non-repeating later candidates under the main text (website / typeface).
    var showsExtraTexts: Bool = false
    var mainIsAISummary: Bool = false
    var showsAIArtBadge: Bool = false
    /// The labelled row that says what the title is (Album, Name, Course…). It leads the
    /// Summary and is never dropped for equalling the title.
    var identityRow: (String, String?)?
    var facts: [(String, String?)] = []
    /// Keep site rows that name the source host (music: which service it's on matters).
    var keepsSiteRows: Bool = false
    /// (Summary label, section label) pairs naming the same fact under two labels, so a section
    /// row with the other label and the same value counts as a repeat.
    var factAliases: [(String, String)] = []
    var links: [(String, String?)] = []
    /// Section cards after the Summary (dossier kinds).
    var sections: [PanelSection] = []
    /// Chip groups that drop chips repeating the facts (Subjects / Teaches / Topics).
    var dedupedChips: [String: [String]] = [:]
    /// Chip groups shown as they are (still count as shown for the tags).
    var plainChips: [String: [String]] = [:]
    /// Further shown values (model, handle, artist names…): the tags and the Author row are
    /// checked against them.
    var extraShown: [String] = []
    /// The kind's canonical page (after redirects), else nil: the Source row opens it.
    var canonicalURL: String?
}

/// The de-duplicated panel: header, Summary (with Author, Source and Added), sections, links,
/// chips, and the values the tags are filtered against.
private struct PanelLayout {
    var header: PanelHeader
    var facts: [(String, String?)]
    /// Fact label → URL it opens (the Source row).
    var factLinks: [String: String]
    var sections: [PanelSection]
    var links: [(String, String?)]
    var chips: [String: [String]]
    var tagShown: [String]
    var snippetTexts: [String]
}

// MARK: - CardSubcards

struct CardSubcards: View {
    @Bindable var item: Item
    var embedsInPanel: Bool = false

    @Environment(\.appTheme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.enrichmentCoordinator) private var enrichmentCoordinator
    @State private var storeItems: [Item] = []
    @State private var gridWidth: CGFloat = 300

    private static let twoColumnThreshold: CGFloat = 520

    /// Rows that name the source site; dropped when they match `displayLink`.
    private static let siteLabels: Set<String> = ["Platform", "Shop", "Publication", "Provider"]

    private var itemKind: ItemKind {
        ItemKind(rawValue: item.kind) ?? .link
    }

    /// The typed panel's kind; `.link` when the kind has no metadata (generic panel).
    private var panelKind: ItemKind {
        item.hasRichTypedPanel ? itemKind : .link
    }

    private var columns: [GridItem] {
        gridWidth >= Self.twoColumnThreshold
            ? [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)]
            : [GridItem(.flexible(), alignment: .top)]
    }

    private var sortedTags: [Tag] {
        (item.tags ?? []).sorted { $0.weight > $1.weight }
    }

    private var sortedSnippets: [Snippet] {
        (item.snippets ?? []).sorted { $0.addedAt < $1.addedAt }
    }

    private var whySavedSuggestions: [String] {
        EnrichmentService.decodeWhySavedSuggestions(from: item.whySavedSuggestionsJSON)
    }

    // User-invoked Enrich may re-run terminal states (candidates_done/error) — see
    // EnrichmentService.enrich(force:); only an in-flight capture is off-limits.
    private var canEnrich: Bool {
        item.enrichmentStatus != "pending"
    }

    /// Panel footer label "Wnn YYYY" per BUILD_SPEC.
    private var weekFooter: String {
        let key = WeekGroup.isoWeekKey(for: item.addedAt)
        guard key != "undated" else { return "Undated" }
        let parts = key.split(separator: "-")
        guard parts.count == 2 else { return key }
        return "W\(parts[1]) \(parts[0])"
    }

    var body: some View {
        let layout = panelLayout()
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            topImagesSubCard()
                .gridCellColumns(columns.count)

            headerCard(layout.header)
                .gridCellColumns(columns.count)

            summaryCard(layout)

            switch panelKind {
            case .typeface, .website, .individual, .studio, .foundry, .place:
                sectionCards(layout.sections)
            case .music:
                if let meta = item.musicMeta() { musicCards(meta, layout: layout) }
            case .product:
                if let meta = item.productMeta() { productCards(meta, layout: layout) }
            case .post:
                if let meta = item.postMeta() { postCards(meta, layout: layout) }
            case .tool:
                if let meta = item.toolMeta() { toolCards(meta, layout: layout) }
            case .resource, .book, .course, .article:
                kindChipsCards(layout)
                linksCard(layout)
            case .link:
                if let md = item.bodyMarkdown, !md.isEmpty {
                    markdownSubCard(md)
                }
            }

            // AI enrichment surfaces (why-saved / tags / snippets / Enrich + its error line)
            // apply to every kind — without these, enriching an entity item persisted results
            // the panel never displayed, and Enrich looked like a silent no-op (2026-07-11).
            enrichmentSubCards(layout)
        }
        .padding(.horizontal, 16)
        .padding(.top, embedsInPanel ? 0 : 16)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { _, newWidth in
            gridWidth = newWidth
        }
        .task { await loadStoreItemsIfNeeded() }
    }

    @MainActor
    private func loadStoreItemsIfNeeded() async {
        guard storeItems.isEmpty else { return }
        let descriptor = FetchDescriptor<Item>(sortBy: [SortDescriptor(\.slug)])
        storeItems = (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Layout (de-duplication)

    /// Every value is shown once. Facts and rows drop only on an exact (normalised) repeat;
    /// containment counts only for prose against prose (snippets, extra texts, Review) and for
    /// tags / chips.
    private func panelLayout() -> PanelLayout {
        let input = kindPanelInput()

        // Header: title once, kind line unless it equals the title, main text unless it
        // equals the title.
        let title = decoded(input.titleOverride ?? item.title.nilIfEmpty ?? "Untitled")
        var kindLine = item.cardKindLine?.nilIfEmpty.map { decoded($0) }
        if let line = kindLine, PanelDedupe.isSameValue(line, against: [title]) { kindLine = nil }
        let texts = PanelDedupe.primaryAndRest(candidates: input.mainCandidates.map { $0.map { decoded($0) } })
        var main = texts.primary
        if let text = main, PanelDedupe.isSameValue(text, against: [title]) { main = nil }
        let extras = input.showsExtraTexts
            ? texts.rest.filter { !PanelDedupe.isSameValue($0, against: [title]) }
            : []
        let firstCandidate = (input.mainCandidates.first ?? nil)?.nilIfEmpty.map { decoded($0) }
        let header = PanelHeader(
            title: title,
            kindLine: kindLine,
            mainText: main,
            mainTextIsAISummary: input.mainIsAISummary && main != nil && main == firstCandidate,
            extraTexts: extras,
            showsAIArtBadge: input.showsAIArtBadge
        )

        let host = item.displayLink
        let hasSource = !host.isEmpty && host != "local"
        let sourcePage = input.canonicalURL?.nilIfEmpty ?? item.sourceURL?.nilIfEmpty
        let sourceURLs = [item.sourceURL, sourcePage].compactMap { $0 }

        // Summary: the identity row, then the kind's facts. A row drops only when its value
        // equals the title (identity rows exempt), the kind line, the Source page, or a row
        // already kept; site rows naming the source host drop too (unless the kind keeps them).
        var shownKeys = Set<String>()
        var facts: [(String, String?)] = []
        var factValues: [String] = []
        var summaryRows = input.facts
        if let identity = input.identityRow { summaryRows.insert(identity, at: 0) }
        for (index, row) in summaryRows.enumerated() {
            let (label, value) = row
            guard let v = value?.nilIfEmpty.map({ decoded($0) }) else { continue }
            let isIdentity = input.identityRow != nil && index == 0
            if !isIdentity, PanelDedupe.isSameValue(v, against: [title]) { continue }
            if let kindLine, PanelDedupe.isSameValue(v, against: [kindLine]) { continue }
            if sourceURLs.contains(where: { PanelDedupe.isSameURL($0, v) }) { continue }
            if hasSource, !input.keepsSiteRows, Self.siteLabels.contains(label),
               PanelDedupe.namesSameSite(v, host: host) { continue }
            let key = PanelDedupe.factKey(label: label, value: v)
            guard shownKeys.insert(key).inserted else { continue }
            facts.append((label, v))
            factValues.append(v)
        }
        for (summaryLabel, otherLabel) in input.factAliases {
            for (label, value) in facts where label == summaryLabel {
                if let value { shownKeys.insert(PanelDedupe.factKey(label: otherLabel, value: value)) }
            }
        }

        // Author (the old Summary row): for every kind, unless the same value already shows
        // anywhere in the panel (a row, a ref, the title, the kind line).
        if let author = item.author?.nilIfEmpty.map({ decoded($0) }) {
            let elsewhere = [title] + [kindLine].compactMap { $0 } + factValues + input.extraShown
                + Self.sectionValues(input.sections)
            let key = PanelDedupe.factKey(label: "Author", value: author)
            if !PanelDedupe.isSameValue(author, against: elsewhere), shownKeys.insert(key).inserted {
                facts.append(("Author", author))
                factValues.append(author)
            }
        }

        // Source (tappable: the canonical page, else the saved URL) and Added last.
        var factLinks: [String: String] = [:]
        if hasSource {
            facts.append(("Source", host))
            shownKeys.insert(PanelDedupe.factKey(label: "Source", value: host))
            if let sourcePage { factLinks["Source"] = sourcePage }
        }
        facts.append(("Added", weekFooter))
        shownKeys.insert(PanelDedupe.factKey(label: "Added", value: weekFooter))

        // Chips: Subjects / Teaches / Topics / Tech stack drop chips the facts already show.
        let chipShown = [title, kindLine].compactMap { $0 } + extras + factValues

        // Sections: each row drops only when its value exactly repeats something shown above
        // (the header, the Summary, the Source page, an earlier section row).
        let headerValues = [title, kindLine, main].compactMap { $0 } + extras
        var sections: [PanelSection] = []
        var sectionShown: [String] = []
        func keptRows(_ rows: [(String, String?)]) -> [(String, String?)] {
            var kept: [(String, String?)] = []
            for (label, value) in rows {
                guard let v = value?.nilIfEmpty.map({ decoded($0) }) else { continue }
                if PanelDedupe.isSameValue(v, against: headerValues) { continue }
                if sourceURLs.contains(where: { PanelDedupe.isSameURL($0, v) }) { continue }
                guard shownKeys.insert(PanelDedupe.factKey(label: label, value: v)).inserted else { continue }
                kept.append((label, v))
                sectionShown.append(v)
            }
            return kept
        }
        for section in input.sections {
            switch section.body {
            case .facts(let rows):
                let kept = keptRows(rows)
                if !kept.isEmpty { sections.append(PanelSection(title: section.title, body: .facts(kept))) }
            case .chips(let chips, let caption):
                let values = chips.compactMap(\.nilIfEmpty)
                if !values.isEmpty || caption?.nilIfEmpty != nil {
                    sections.append(PanelSection(title: section.title, body: .chips(values, caption: caption?.nilIfEmpty)))
                    sectionShown += values
                }
            case .dedupedChips(let chips):
                let values = PanelDedupe.filterTags(chips.compactMap(\.nilIfEmpty), shown: chipShown)
                if !values.isEmpty {
                    sections.append(PanelSection(title: section.title, body: .chips(values, caption: nil)))
                    sectionShown += values
                }
            case .refs(let refs):
                let values = refs.filter { !$0.name.isEmpty }
                if !values.isEmpty {
                    sections.append(PanelSection(title: section.title, body: .refs(values)))
                    sectionShown += values.map(\.name)
                }
            case .text(let text):
                guard let t = text.nilIfEmpty.map({ decoded($0) }),
                      !PanelDedupe.isRedundant(t, against: header.texts) else { continue }
                sections.append(PanelSection(title: section.title, body: .text(t)))
                sectionShown.append(t)
            case .gallery, .faqs:
                sections.append(section)
            case .chipsAndFacts(let chips, let rows):
                let values = chips.compactMap(\.nilIfEmpty)
                let kept = keptRows(rows)
                if !values.isEmpty || !kept.isEmpty {
                    sections.append(PanelSection(title: section.title, body: .chipsAndFacts(values, kept)))
                    sectionShown += values
                }
            }
        }

        // Links: only places other than the saved / canonical page.
        let links = input.links.filter { _, value in
            guard let url = value?.nilIfEmpty else { return false }
            return !PanelDedupe.isSameURL(url, item.sourceURL) && !PanelDedupe.isSameURL(url, input.canonicalURL)
        }

        var chips = input.plainChips
        for (key, values) in input.dedupedChips {
            chips[key] = PanelDedupe.filterTags(values, shown: chipShown)
        }

        // Tags: hide (never delete) tags naming a value the panel already shows — including
        // site rows dropped above (platform, publication, provider) and the host itself.
        var tagShown = header.shownValues + factValues + input.facts.compactMap { $0.1?.nilIfEmpty }
        tagShown += input.extraShown + sectionShown
        tagShown += chips.values.flatMap { $0 }
        if hasSource { tagShown.append(host) }

        return PanelLayout(
            header: header,
            facts: facts,
            factLinks: factLinks,
            sections: sections,
            links: links,
            chips: chips,
            tagShown: tagShown,
            snippetTexts: header.texts
        )
    }

    private func decoded(_ text: String) -> String {
        CaptureService.decodeBasicEntities(text)
    }

    /// The values the sections would show before de-duplication (rows, chips, ref names, texts).
    private static func sectionValues(_ sections: [PanelSection]) -> [String] {
        sections.flatMap { section -> [String] in
            switch section.body {
            case .facts(let rows): return rows.compactMap { $0.1 }
            case .chips(let chips, _), .dedupedChips(let chips): return chips
            case .refs(let refs): return refs.map(\.name) + [names(refs)].compactMap { $0 }
            case .text(let text): return [text]
            case .gallery, .faqs: return []
            case .chipsAndFacts(let chips, let rows): return chips + rows.compactMap { $0.1 }
            }
        }
    }

    /// True when at least one ref opens an item in the store (its chip is tappable).
    private func refsResolve(_ refs: [EntityRef]) -> Bool {
        refs.contains { ref in
            guard let slug = ref.slug else { return false }
            return storeItems.contains { $0.slug == slug }
        }
    }

    private func kindPanelInput() -> KindPanelInput {
        var input = KindPanelInput()
        input.mainCandidates = [item.summary]

        switch panelKind {
        case .typeface:
            guard let meta = item.typefaceMeta() else { break }
            input.mainCandidates = [item.summary, meta.overview, meta.description]
            input.showsExtraTexts = true
            input.facts = [
                ("Release year", meta.releaseYear),
                ("License", meta.license),
                ("Price", Self.typefacePrice(meta)),
                ("Specimen link", meta.specimenLink ?? meta.specimenURL),
            ]
            input.factAliases = [("Price", "Starting price"), ("Price", "Paid / free")]
            input.sections = typefaceSections(meta)

        case .website:
            guard let meta = item.websiteMeta() else { break }
            input.mainCandidates = [meta.tagline, item.summary, meta.description]
            input.showsExtraTexts = true
            input.sections = websiteSections(meta)

        case .individual:
            guard let meta = item.individualMeta() else { break }
            input.mainCandidates = [meta.bio, item.summary]
            input.facts = [
                ("Current role", meta.currentRole),
                ("Employer", meta.currentEmployer),
                ("Location", meta.location?.name),
                ("Pronouns", meta.pronouns),
                ("Experience", meta.professionalExperience.map { "\($0) years" }),
            ]
            input.sections = individualSections(meta)

        case .studio:
            guard let meta = item.studioMeta() else { break }
            input.sections = [
                PanelSection(title: "Work", body: .refs(meta.work)),
                PanelSection(title: "Team", body: .refs(meta.team)),
            ]

        case .foundry:
            guard let meta = item.foundryMeta() else { break }
            input.mainCandidates = [meta.description, item.summary]
            input.facts = [
                ("Category", meta.category),
                ("Location", meta.geography?.name),
                ("Founded", meta.foundedYear),
                ("Price range", meta.priceRange),
            ]
            input.factAliases = [("Location", "Geography")]
            input.sections = foundrySections(meta)

        case .place:
            guard let meta = item.placeMeta() else { break }
            input.facts = [("City", meta.city), ("Country", meta.country)]

        case .music:
            guard let meta = item.musicMeta() else { break }
            let artistNames = meta.artists.map(\.name).compactMap(\.nilIfEmpty)
            // The Artists refs card when a ref opens a stored item; else a Summary row.
            let artistsRow = refsResolve(meta.artists) ? nil : Self.names(meta.artists)
            let curatorRow = meta.curator.flatMap { refsResolve([$0]) ? nil : $0.name.nilIfEmpty }
            input.identityRow = (Self.musicIdentityLabel(meta.subtype), meta.cleanTitle?.nilIfEmpty ?? item.title)
            input.facts = [
                (artistNames.count > 1 ? "Artists" : "Artist", artistsRow),
                ("Type", meta.subtype?.capitalized),
                ("Edition", meta.edition),
                ("Year", meta.releaseYear),
                ("Label", meta.label),
                ("Film", meta.film),
                ("Duration", musicDuration(meta.totalDurationSeconds)),
                ("Tracks", meta.trackList.isEmpty ? nil : String(meta.trackList.count)),
                (meta.isOwnPlaylist == true ? "Curator (you)" : "Curator", curatorRow),
                ("Platform", Self.musicPlatformLabel(meta.platform)),
                ("UPC", meta.upc),
            ]
            input.keepsSiteRows = true
            input.plainChips["genres"] = meta.genres
            input.extraShown = [meta.curator?.name, meta.platform].compactMap { $0 }
                + artistNames + [Self.names(meta.artists)].compactMap { $0 }
            // Source opens the saved page; a different canonical page is a link of its own.
            input.links = [("Canonical", meta.canonicalURL)]

        case .product:
            guard let meta = item.productMeta() else { break }
            input.identityRow = (meta.productNameIsGuess == true ? "Name (guess)" : "Name", meta.productName)
            input.facts = [
                (meta.brandIsGuess == true ? "Brand (guess)" : "Brand", meta.brand?.name),
                ("Price range", productPriceRange(meta)),
                ("Price when saved", productPriceWhenSaved(meta)),
                ("Availability", meta.availability?.capitalized),
                ("Shop", meta.shop),
                ("Category", meta.category),
            ]
            input.links = [
                ("Buy", meta.buyURL),
                ("Original post", meta.originalPostURL),
            ]
            input.extraShown = [meta.creator?.name, meta.creatorHandle].compactMap { $0 }
            input.canonicalURL = meta.canonicalURL

        case .post:
            guard let meta = item.postMeta() else { break }
            let authorLine = postAuthorLine(meta)
            if let authorLine, postTitleIsFromText(meta) {
                input.titleOverride = authorLine
            }
            input.mainCandidates = [meta.text, item.summary]
            input.showsAIArtBadge = meta.isAIArt
                && meta.aiModel?.nilIfEmpty == nil && meta.prompt?.nilIfEmpty == nil
            input.facts = [
                ("Platform", Self.postPlatformLabel(meta.platform)),
                ("Author", authorLine),
                ("Posted", meta.postedAt?.formatted(date: .abbreviated, time: .omitted)),
                ("Media", postMediaLine(meta)),
            ]
            // The author line's parts: an `item.author` equal to the name or the handle is
            // the same fact.
            input.extraShown = [meta.aiModel, meta.authorHandle, meta.author?.name].compactMap { $0 }
            input.canonicalURL = meta.canonicalURL

        case .tool:
            guard let meta = item.toolMeta() else { break }
            input.mainCandidates = [meta.tagline, item.summary]
            input.identityRow = ("Name", meta.name)
            input.facts = [
                ("Type", Self.toolSubtypeLabel(meta.subtype)),
                (meta.platformsAreGuess ? "Platforms (guess)" : "Platforms", meta.platformsLine()),
                ("Category", meta.category),
                (meta.pricingIsGuess ? "Price (guess)" : "Price", toolPriceLine(meta)),
                ("Maker", meta.maker?.name),
            ]
            input.links = [
                ("Website", toolWebsiteURL(meta)),
                ("App Store", meta.appStoreURL),
                ("Repository", meta.repoURL),
            ]
            input.dedupedChips["topics"] = meta.topics
            input.extraShown = [meta.language, meta.name].compactMap { $0 } + meta.platforms
            input.canonicalURL = meta.canonicalURL

        case .resource:
            guard let meta = item.resourceMeta() else { break }
            input.facts = [
                ("Type", Self.resourceSubtypeLabel(meta.subtype)),
                ("Works with", meta.worksWith.isEmpty ? nil : meta.worksWith.joined(separator: ", ")),
                ("Maker", meta.maker?.name),
                ("Price", meta.priceLine),
                ("Users", meta.users.map { ToolMeta.compactCount($0) }),
                ("Likes", meta.likes.map { ToolMeta.compactCount($0) }),
            ]
            input.links = [("Maker's page", meta.maker?.url)]
            input.extraShown = [meta.name].compactMap { $0 } + meta.worksWith
            input.canonicalURL = meta.canonicalURL

        case .book:
            guard let meta = item.bookMeta() else { break }
            if let bookTitle = meta.title?.nilIfEmpty,
               !PanelDedupe.isSameValue(bookTitle, against: [item.title]) {
                input.identityRow = ("Title", bookTitle)
            }
            let authorLabel = meta.authors.count > 1 ? "Authors" : "Author"
            input.facts = [
                (meta.authorsAreGuess ? "\(authorLabel) (guess)" : authorLabel, meta.authorsLine),
                ("Published", meta.publishedYear.map(String.init)),
                ("Publisher", meta.publisher),
                ("Pages", meta.pages.flatMap { $0 > 0 ? String($0) : nil }),
                ("Format", meta.formatLabel),
                ("ISBN", meta.isbnLine),
                ("Language", meta.languageLabel),
            ]
            input.links = [
                ("Open Library", meta.openLibraryURL),
                ("Goodreads", meta.goodreadsURL),
                ("Amazon", Self.bookAmazonLink(meta, sourceURL: item.sourceURL)),
            ]
            input.dedupedChips["subjects"] = meta.subjects
            input.extraShown = [meta.title].compactMap { $0 } + meta.authors.map(\.name)
            input.canonicalURL = meta.canonicalURL

        case .course:
            guard let meta = item.courseMeta() else { break }
            input.identityRow = ("Course", meta.name)
            input.facts = [
                ("Provider", meta.provider?.name),
                ("Instructor", meta.instructor?.name),
                (meta.formatIsGuess ? "Format (guess)" : "Format", meta.formatLabel),
                (meta.durationIsGuess || meta.lessonsIsGuess ? "Length (guess)" : "Length", meta.lengthLine),
                ("Level", meta.level),
                ("Price", meta.priceLine),
                ("Starts", Self.upcomingStart(meta.startsAt)),
            ]
            input.links = [("Instructor page", meta.instructor?.url)]
            input.dedupedChips["teaches"] = meta.topics
            input.extraShown = [meta.name].compactMap { $0 }
            input.canonicalURL = meta.canonicalURL

        case .article:
            guard let meta = item.articleMeta() else { break }
            // The on-device summary leads; it is marked as AI-written when it is a guess.
            input.mainCandidates = [meta.summary, item.summary]
            input.mainIsAISummary = meta.summaryIsGuess && meta.summary?.nilIfEmpty != nil
            input.facts = [
                ("Publication", meta.publication),
                ("Author", meta.author?.name),
                ("Published", meta.publishedAt?.formatted(date: .abbreviated, time: .omitted)),
                ("Reading time", meta.readingLine),
            ]
            input.links = [("Author's page", meta.author?.url)]
            if meta.isTutorial { input.dedupedChips["techStack"] = meta.techStack }
            input.canonicalURL = meta.canonicalURL

        case .link:
            break
        }
        return input
    }

    // MARK: - Shared top sub-cards

    @ViewBuilder
    private func topImagesSubCard() -> some View {
        let isTyped = itemKind != .link && item.hasRichTypedPanel
        let typedImages = item.renderableImages(matchingRoles: item.typedTopMediaRoles)

        if embedsInPanel, isTyped, !typedImages.isEmpty {
            imageGalleryCard(
                title: "Images",
                roles: item.typedTopMediaRoles,
                bleedsToTop: true,
                mainHeight: 220,
                showsThumbnails: true
            )
        } else {
            SubCard(title: embedsInPanel ? "" : "Images", bleedsToTop: embedsInPanel) {
                DetailImageStrip(item: item, bleedsToTop: embedsInPanel)
            }
            .horizontalBleed(active: embedsInPanel)
        }
    }

    /// Title, kind line, the "AI art" badge and the main text — no field labels.
    @ViewBuilder
    private func headerCard(_ header: PanelHeader) -> some View {
        SubCard(title: "") {
            VStack(alignment: .leading, spacing: 6) {
                Text(header.title)
                    .font(.karst(.title3, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let kindLine = header.kindLine {
                    Text(kindLine)
                        .font(.karst(.caption))
                        .foregroundStyle(theme.textSecondary)
                }

                if header.showsAIArtBadge {
                    Text("AI art")
                        .font(.karst(.caption2, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(theme.accentSubtle)
                        .clipShape(Capsule())
                }

                if let main = header.mainText {
                    VStack(alignment: .leading, spacing: 2) {
                        if header.mainTextIsAISummary {
                            Text("AI summary")
                                .font(.karst(.caption2, weight: .semibold))
                                .foregroundStyle(theme.textSecondary)
                        }
                        Text(main)
                            .font(.karst(.callout))
                            .foregroundStyle(theme.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, 4)
                }

                ForEach(Array(header.extraTexts.enumerated()), id: \.offset) { _, text in
                    Text(text)
                        .font(.karst(.callout))
                        .foregroundStyle(theme.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// The Summary card: the identity row and the kind's facts (exact repeats dropped), then
    /// Author, Source (tappable) and Added.
    @ViewBuilder
    private func summaryCard(_ layout: PanelLayout) -> some View {
        factsCard(title: "Summary", rows: layout.facts, links: layout.factLinks)
    }

    /// Places other than the saved / canonical page; hidden when empty.
    @ViewBuilder
    private func linksCard(_ layout: PanelLayout) -> some View {
        factsCard(title: "Links", rows: layout.links)
    }

    /// Subjects (book) / Teaches (course) / Tech stack (article), already de-duplicated.
    @ViewBuilder
    private func kindChipsCards(_ layout: PanelLayout) -> some View {
        switch panelKind {
        case .book:
            chipsCard(title: "Subjects", chips: layout.chips["subjects"] ?? [])
        case .course:
            let topicsAreGuess = item.courseMeta()?.topicsAreGuess ?? false
            chipsCard(title: topicsAreGuess ? "Teaches (guess)" : "Teaches", chips: layout.chips["teaches"] ?? [])
        case .article:
            chipsCard(title: "Tech stack", chips: layout.chips["techStack"] ?? [])
        default:
            EmptyView()
        }
    }

    // MARK: - Enrichment sub-cards

    @ViewBuilder
    private func markdownSubCard(_ text: String) -> some View {
        SubCard(title: "Notes") {
            Group {
                if let attr = try? AttributedString(markdown: text) {
                    Text(attr)
                } else {
                    Text(text)
                }
            }
            .font(.karst(.callout))
            .foregroundStyle(theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Why save?, Tags, Key snippets and Actions, for every kind. Typed panels are strictly
    /// render-if-data; the link panel keeps the snippets empty state only when the panel holds
    /// nothing else. Actions always renders so Enrich and its error line are reachable.
    @ViewBuilder
    private func enrichmentSubCards(_ layout: PanelLayout) -> some View {
        let tags = visibleTags(layout)
        let snippets = visibleSnippets(layout)

        whySavedSubCard
        tagsSubCard(tags)

        if panelKind != .post {
            if !snippets.isEmpty {
                snippetsSubCard(snippets)
            } else if panelKind == .link,
                      layout.header.mainText == nil,
                      item.bodyMarkdown?.nilIfEmpty == nil,
                      tags.isEmpty,
                      whySavedSuggestions.isEmpty {
                snippetsSubCard([])
            }
        }

        if canEnrich {
            enrichSubCard
        }
    }

    /// Tags minus those naming a value the panel already shows (never deleted from the item).
    private func visibleTags(_ layout: PanelLayout) -> [Tag] {
        let tags = sortedTags
        let kept = Set(PanelDedupe.filterTags(tags.map(\.name), shown: layout.tagShown))
        return tags.filter { kept.contains($0.name) }
    }

    /// Snippets the main text doesn't already contain, and no repeats of an earlier snippet.
    private func visibleSnippets(_ layout: PanelLayout) -> [Snippet] {
        var keptTexts: [String] = []
        var kept: [Snippet] = []
        for snippet in sortedSnippets {
            let text = snippet.text
            guard text.nilIfEmpty != nil,
                  !PanelDedupe.isRedundant(text, against: layout.snippetTexts),
                  !PanelDedupe.isRedundant(text, against: keptTexts) else { continue }
            keptTexts.append(text)
            kept.append(snippet)
        }
        return kept
    }

    @ViewBuilder
    private func snippetsSubCard(_ snippets: [Snippet]) -> some View {
        SubCard(title: "Key snippets") {
            if snippets.isEmpty {
                Text("No snippets yet.")
                    .font(.karst(.caption))
                    .foregroundStyle(theme.textSecondary)
                    .italic()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snippets, id: \.persistentModelID) { snippet in
                        HStack(alignment: .top, spacing: 8) {
                            Rectangle()
                                .fill(theme.accentColor)
                                .frame(width: 2)
                            Text(snippet.text)
                                .font(.karst(.callout))
                                .foregroundStyle(theme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                removeSnippet(snippet)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(theme.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove snippet")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(theme.borderSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var whySavedSubCard: some View {
        if !whySavedSuggestions.isEmpty {
            SubCard(title: "Why save?") {
                TagFlowLayout(spacing: 6) {
                    ForEach(whySavedSuggestions, id: \.self) { suggestion in
                        HStack(spacing: 0) {
                            Button {
                                acceptWhySavedSuggestion(suggestion)
                            } label: {
                                Text(humanizeReason(suggestion))
                                    .font(.karst(.caption))
                                    .foregroundStyle(theme.accentContrast)
                                    .padding(.leading, 12)
                                    .padding(.trailing, 8)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Accept \(humanizeReason(suggestion))")

                            Rectangle()
                                .fill(theme.accentContrast.opacity(0.25))
                                .frame(width: 1, height: 14)

                            Button(role: .destructive) {
                                dismissWhySavedSuggestion(suggestion)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(theme.accentContrast.opacity(0.85))
                                    .padding(.leading, 8)
                                    .padding(.trailing, 12)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Dismiss suggestion")
                        }
                        .background(theme.accentColor)
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tagsSubCard(_ tags: [Tag]) -> some View {
        if !tags.isEmpty {
            SubCard(title: "Tags") {
                TagFlowLayout(spacing: 6) {
                    ForEach(tags, id: \.persistentModelID) { tag in
                        HStack(spacing: 4) {
                            if tag.source == "ai" {
                                Circle()
                                    .fill(theme.accentColor)
                                    .frame(width: 5, height: 5)
                            }
                            Text(tag.name)
                                .font(.karst(.caption))
                                .foregroundStyle(theme.textPrimary)
                            if tag.source == "ai" {
                                Button {
                                    removeAITag(tag)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(theme.textSecondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove tag")
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(tag.source == "ai" ? theme.accentSubtle : theme.borderSubtle)
                        .clipShape(Capsule())
                        .opacity(max(0.55, tag.weight))
                    }
                }
            }
        }
    }

    private var enrichSubCard: some View {
        SubCard(title: "Actions") {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    enrichmentCoordinator.scheduleEnrichment(for: item, context: context, force: true)
                } label: {
                    Label("Enrich", systemImage: "sparkles")
                        .font(.karst(.callout, weight: .semibold))
                        .foregroundStyle(theme.accentContrast)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(theme.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                // Surfaced so AI failures are diagnosable in-app — the web app's PR #17
                // lesson: a swallowed enrichment error makes no-result items a forensics job.
                if let error = item.enrichmentError, !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.karst(.footnote))
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
    }

    private func humanizeReason(_ reason: String) -> String {
        reason.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    // MARK: - Mutations

    private func removeAITag(_ tag: Tag) {
        context.delete(tag)
        item.updatedAt = .now
        try? context.save()
    }

    private func removeSnippet(_ snippet: Snippet) {
        context.delete(snippet)
        item.updatedAt = .now
        try? context.save()
    }

    private func acceptWhySavedSuggestion(_ suggestion: String) {
        try? EnrichmentService.addIntentTag(name: suggestion, to: item, context: context)
    }

    private func dismissWhySavedSuggestion(_ suggestion: String) {
        try? EnrichmentService.dismissWhySavedSuggestion(name: suggestion, from: item, context: context)
    }

    // MARK: - Shared kind helpers

    /// "Ann, Bo, Cy" from the refs' names; nil when there are none.
    private static func names(_ refs: [EntityRef]) -> String? {
        let names = refs.map(\.name).compactMap(\.nilIfEmpty)
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    // MARK: - Sections (dossier kinds)

    @ViewBuilder
    private func sectionCards(_ sections: [PanelSection]) -> some View {
        ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
            sectionCard(section)
        }
    }

    @ViewBuilder
    private func sectionCard(_ section: PanelSection) -> some View {
        switch section.body {
        case .facts(let rows):
            factsCard(title: section.title, rows: rows)
        case .chips(let chips, let caption):
            chipsCard(title: section.title, chips: chips, caption: caption)
        case .dedupedChips(let chips):
            chipsCard(title: section.title, chips: chips)
        case .refs(let refs):
            refsCard(title: section.title, refs: refs)
        case .text(let text):
            textCard(title: section.title, text: text)
        case .gallery(let roles):
            imageGalleryCard(title: section.title, roles: roles)
        case .faqs(let items):
            faqCard(title: section.title, items: items)
        case .chipsAndFacts(let chips, let rows):
            let content = FactsSubCardContent(rows: rows)
            if !chips.isEmpty || content != nil {
                SubCard(title: section.title) {
                    VStack(alignment: .leading, spacing: 8) {
                        if !chips.isEmpty {
                            ChipsSubCardBody(chips: chips)
                        }
                        if let content {
                            FactsSubCardBody(content: content)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Typeface

    private func typefaceSections(_ meta: TypefaceMeta) -> [PanelSection] {
        let weightCount = meta.weightsCount ?? meta.weightCount.map(String.init)
        let styleCount = meta.stylesCount ?? meta.styleCount.map(String.init)
        let langCount = meta.languagesCount ?? meta.languageSupport.map(String.init)
        var foundryDesigner: [EntityRef] = []
        if let foundry = meta.typeFoundry { foundryDesigner.append(foundry) }
        foundryDesigner.append(contentsOf: meta.typeDesigner)
        return [
            PanelSection(title: "Classification", body: .chips(meta.classification + meta.personality, caption: nil)),
            PanelSection(title: "Weights", body: .chips(meta.weightTypes, caption: weightCount.map { "\($0) weights" })),
            PanelSection(title: "Styles", body: .chips(meta.styleTypes, caption: styleCount.map { "\($0) styles" })),
            PanelSection(title: "Languages", body: .chips(meta.languagesRegion, caption: langCount.map { "\($0) languages" })),
            PanelSection(title: "Formats & tech", body: .chipsAndFacts(meta.availableFormats, [
                ("Variable font", meta.variableFontSupport.map { $0 ? "Yes" : "No" }),
                ("OpenType features", meta.openTypeFeatures.isEmpty ? nil : meta.openTypeFeatures.joined(separator: ", ")),
            ])),
            PanelSection(title: "Licensing & pricing", body: .facts([
                ("License", meta.license),
                ("Paid / free", meta.paidOrFree),
                ("Starting price", meta.startingPrice),
                ("Trial", meta.trialAvailability.map { $0 ? "Available" : "No" }),
                ("Student discount", meta.studentDiscount.map { $0 ? "Yes" : "No" }),
            ])),
            PanelSection(title: "Distributed on", body: .refs(meta.distributedOn)),
            PanelSection(title: "Foundry & designer", body: .refs(foundryDesigner)),
            PanelSection(title: "Designer", body: .facts([("Name", meta.typeDesignerFallback)])),
            PanelSection(title: "Technical", body: .facts([
                ("Release year", meta.releaseYear),
                ("Last update", meta.lastUpdate),
                ("Version", meta.version),
                ("Family count", meta.familyCount),
                ("Family fonts", meta.familyFontNames.isEmpty ? nil : meta.familyFontNames.map(\.name).joined(separator: ", ")),
            ])),
            PanelSection(title: "Letterform graphics", body: .gallery([ItemImageRole.graphic.rawValue])),
            PanelSection(title: "Insights", body: .facts([
                ("Highlights", meta.highlights),
                ("Use case", meta.useCase),
                ("Design features", meta.designFeatures),
            ])),
            PanelSection(title: "Related fonts", body: .facts([
                ("Pairing", meta.pairingFonts),
                ("Similar", meta.similarFonts),
                ("Fork", meta.forkFonts),
            ])),
            PanelSection(title: "Previews", body: .gallery([ItemImageRole.preview.rawValue])),
            PanelSection(title: "FAQs", body: .faqs(meta.faqs)),
            PanelSection(title: "Appears in", body: .refs(meta.creatives + meta.websites)),
        ]
    }

    /// "Free" for a free family, else the starting price (else the paid / free label).
    private static func typefacePrice(_ meta: TypefaceMeta) -> String? {
        if meta.paidOrFree?.lowercased().contains("free") == true,
           meta.paidOrFree?.lowercased().contains("paid") != true {
            return "Free"
        }
        return meta.startingPrice?.nilIfEmpty ?? meta.paidOrFree
    }

    // MARK: - Website

    private func websiteSections(_ meta: WebsiteMeta) -> [PanelSection] {
        var sections: [PanelSection] = [
            PanelSection(title: "Category", body: .chips(meta.categories, caption: nil)),
            PanelSection(title: "Traits", body: .chips(meta.traits, caption: nil)),
            PanelSection(title: "Focus areas", body: .chips(meta.focusAreas, caption: nil)),
            PanelSection(title: "Review", body: .text(meta.review ?? "")),
            PanelSection(title: "Platform", body: .chips(meta.platform, caption: nil)),
            PanelSection(title: "Tech stack", body: .dedupedChips(meta.techStack)),
            PanelSection(title: "Founders", body: .refs(meta.founders)),
            PanelSection(title: "Founder", body: .facts([("Name", meta.founderName)])),
            PanelSection(title: "Branding by", body: .refs(meta.brandingMadeBy)),
            PanelSection(title: "Site designer", body: .refs(meta.siteDesignerAgency)),
        ]
        if meta.agencyName?.nilIfEmpty != nil {
            sections.append(PanelSection(title: "Agency", body: .facts([
                ("Name", meta.agencyName),
                ("URL", meta.agencyURL),
            ])))
        }
        sections += [
            PanelSection(title: "Creatives", body: .refs(meta.creatives)),
            PanelSection(title: "Typography", body: .refs(meta.typography)),
            PanelSection(title: "Typeface count", body: .facts([("Count", meta.typefaceCount)])),
            PanelSection(title: "Foundries", body: .refs(meta.typeFoundries)),
            PanelSection(title: "Web pages", body: .chips(meta.webPages, caption: meta.webPagesCount)),
            PanelSection(title: "Key components", body: .chips(meta.keyComponents, caption: meta.keyComponentsCount)),
            PanelSection(title: "Timeline", body: .facts([
                ("First published", meta.firstPublished),
                ("Date added", meta.dateAdded),
                ("Date updated", meta.dateUpdated),
            ])),
        ]
        return sections
    }

    // MARK: - Individual

    private func individualSections(_ meta: IndividualMeta) -> [PanelSection] {
        [
            PanelSection(title: "Identity", body: .facts([
                ("Pronouns", meta.pronouns),
                ("Bio", meta.bio),
                ("Location", meta.location?.name),
            ])),
            PanelSection(title: "Professions", body: .chips(meta.professions, caption: nil)),
            PanelSection(title: "Traits", body: .chips(meta.traits, caption: nil)),
            PanelSection(title: "Professional", body: .facts([
                ("Experience", meta.professionalExperience.map { "\($0) years" }),
                ("Current role", meta.currentRole),
                ("Employer", meta.currentEmployer),
                ("Notable works", meta.notableWorks),
                ("Signature style", meta.signatureStyle),
            ])),
            PanelSection(title: "Work & community", body: .facts([
                ("Own products", meta.ownProductsList),
                ("Speaking", meta.speaking),
                ("Workshops", meta.workshops),
                ("Community", meta.communityWork),
                ("Tools & stack", meta.toolsAndTechStack),
            ])),
            PanelSection(title: "Contact & social", body: .facts([
                ("Email", meta.email),
                ("X", meta.xURL),
                ("Instagram", meta.instagramURL),
                ("LinkedIn", meta.linkedInURL),
                ("Behance", meta.behanceURL),
                ("Bluesky", meta.bluesky),
                ("Mastodon", meta.mastodon),
                ("Threads", meta.threads),
                ("Blog", meta.blogLink),
                ("Shop", meta.shopLink),
            ])),
            PanelSection(title: "Personals", body: .facts([
                ("Favourite book", meta.favouriteBook),
                ("Fun fact", meta.funFact),
                ("Hobbies", meta.hobbies),
            ])),
            PanelSection(title: "Typefaces", body: .refs(meta.typefaces)),
            PanelSection(title: "Foundries", body: .refs(meta.typeFoundries)),
        ]
    }

    // MARK: - Foundry

    private func foundrySections(_ meta: FoundryMeta) -> [PanelSection] {
        [
            PanelSection(title: "About", body: .facts([
                ("Description", meta.description),
                ("Category", meta.category),
            ])),
            PanelSection(title: "Origin & team", body: .facts([
                ("Geography", meta.geography?.name),
                ("Founded", meta.foundedYear),
            ])),
            PanelSection(title: "Founders & designers", body: .refs(meta.foundersDesigners)),
            PanelSection(title: "Pricing & licensing", body: .facts([
                ("Price range", meta.priceRange),
                ("Trial fonts", meta.trialFonts.map { $0 ? "Yes" : "No" }),
                ("Student discount", meta.studentDiscount.map { $0 ? "Yes" : "No" }),
            ])),
            PanelSection(title: "Licensing types", body: .chips(meta.licensingTypes, caption: nil)),
            PanelSection(title: "Design approach", body: .facts([("Philosophy", meta.designPhilosophy)])),
            PanelSection(title: "Popular fonts", body: .chips(meta.popularFonts, caption: nil)),
            PanelSection(title: "Specialisation", body: .chips(meta.specialisation, caption: nil)),
            PanelSection(title: "Custom services", body: .chips(meta.customServices, caption: nil)),
            PanelSection(title: "Presence", body: .facts([
                ("Social", meta.social),
                ("Email", meta.email),
                ("Thoughts", meta.thoughts),
            ])),
            PanelSection(title: "Distribution", body: .chips(meta.distribution, caption: nil)),
            PanelSection(title: "Typefaces", body: .refs(meta.typefaces)),
            PanelSection(title: "Websites", body: .refs(meta.websites)),
            PanelSection(title: "Creatives", body: .refs(meta.creatives)),
        ]
    }

    // MARK: - Music

    @ViewBuilder
    private func musicCards(_ meta: MusicMeta, layout: PanelLayout) -> some View {
        // Artists / curator as refs only when a ref opens a stored item; otherwise the names
        // are Summary rows (never both).
        if refsResolve(meta.artists) {
            refsCard(title: "Artists", refs: meta.artists)
        }
        if let curator = meta.curator, refsResolve([curator]) {
            refsCard(title: meta.isOwnPlaylist == true ? "Curated by (you)" : "Curated by", refs: [curator])
        }
        chipsCard(title: "Genres", chips: layout.chips["genres"] ?? [])

        if !meta.trackList.isEmpty {
            SubCard(title: "Tracklist") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(meta.trackList.enumerated()), id: \.offset) { _, track in
                        HStack {
                            Text(track.name)
                                .font(.karst(.callout))
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            if let duration = musicDuration(track.durationSeconds) {
                                Text(duration)
                                    .font(.karst(.caption))
                                    .foregroundStyle(theme.textSecondary)
                            }
                        }
                    }
                }
            }
        }

        linksCard(layout)
    }

    /// The Summary's identity label from the subtype: Album / Track / Playlist / Artist / Mix.
    private static func musicIdentityLabel(_ subtype: String?) -> String {
        guard let subtype = subtype?.nilIfEmpty else { return "Title" }
        return subtype.prefix(1).uppercased() + String(subtype.dropFirst())
    }

    /// "Spotify", "Apple Music", "YouTube Music"…; nil for an unknown service.
    private static func musicPlatformLabel(_ platform: String?) -> String? {
        switch platform {
        case nil, "unknown": return nil
        case "spotify": return "Spotify"
        case "apple-music": return "Apple Music"
        case "youtube-music": return "YouTube Music"
        case "youtube": return "YouTube"
        case "soundcloud": return "SoundCloud"
        case "bandcamp": return "Bandcamp"
        case "tidal": return "Tidal"
        case "mixcloud": return "Mixcloud"
        case "deezer": return "Deezer"
        case let other?: return other.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }

    // MARK: - Product

    @ViewBuilder
    private func productCards(_ meta: ProductMeta, layout: PanelLayout) -> some View {
        // The shop gallery (cover + up to 7 `gallery` images, capped at capture) renders in
        // the top images sub-card via `typedTopMediaRoles`.
        if let creator = meta.creator {
            refsCard(title: "Posted by", refs: [creator])
        }

        linksCard(layout)
    }

    private func productPriceRange(_ meta: ProductMeta) -> String? {
        guard let low = ProductMeta.formattedPrice(meta.priceMin, currency: meta.currency),
              let high = ProductMeta.formattedPrice(meta.priceMax, currency: meta.currency) else { return nil }
        return "\(low) – \(high)"
    }

    /// "₹2,699 · 23 Oct 2026" — the snapshot taken at capture.
    private func productPriceWhenSaved(_ meta: ProductMeta) -> String? {
        guard let price = ProductMeta.formattedPrice(meta.price, currency: meta.currency) else { return nil }
        guard let date = meta.pricedAt else { return price }
        return "\(price) · \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    // MARK: - Post

    @ViewBuilder
    private func postCards(_ meta: PostMeta, layout: PanelLayout) -> some View {
        // The post media (cover + up to 7 `gallery` images, capped at capture) renders in the
        // top images sub-card via `typedTopMediaRoles`. The text leads the header card.
        // Model / prompt only; a flag with neither is the header's "AI art" badge.
        let model = meta.aiModel?.nilIfEmpty
        let prompt = meta.prompt?.nilIfEmpty
        if meta.isAIArt, model != nil || prompt != nil {
            SubCard(title: "AI art") {
                VStack(alignment: .leading, spacing: 8) {
                    if let model {
                        factRow(label: "Model", value: model)
                    }
                    if let prompt {
                        HStack(alignment: .top, spacing: 8) {
                            factRow(label: meta.promptIsGuess ? "Prompt (guess)" : "Prompt", value: prompt)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                copyToPasteboard(prompt)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(theme.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Copy prompt")
                            .help("Copy prompt")
                        }
                    }
                }
            }
        }
    }

    /// True when the item title was made from the post text ("@handle: first words…").
    private func postTitleIsFromText(_ meta: PostMeta) -> Bool {
        guard meta.text?.nilIfEmpty != nil else { return false }
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let generated = PostReader.postTitle(
            currentTitle: nil,
            handle: meta.authorHandle,
            authorName: meta.author?.name,
            text: meta.text
        )
        if title == generated { return true }
        if let handle = meta.authorHandle?.nilIfEmpty, title.hasPrefix("@\(handle):") { return true }
        if let name = meta.author?.name.nilIfEmpty, title.hasPrefix("\(name):") { return true }
        return false
    }

    private static func postPlatformLabel(_ platform: String?) -> String? {
        switch platform {
        case "x": return "X"
        case "instagram": return "Instagram"
        case "behance": return "Behance"
        case "dribbble": return "Dribbble"
        case "pinterest": return "Pinterest"
        default: return platform?.capitalized
        }
    }

    /// "Jane Doe · @jane", or whichever of the two is known.
    private func postAuthorLine(_ meta: PostMeta) -> String? {
        let name = meta.author?.name.nilIfEmpty
        let handle = meta.authorHandle?.nilIfEmpty.map { "@\($0)" }
        switch (name, handle) {
        case let (name?, handle?): return name == handle ? name : "\(name) · \(handle)"
        case let (name?, nil): return name
        case let (nil, handle?): return handle
        default: return nil
        }
    }

    /// "4 items" for a carousel, else "Video" / "GIF" / "Image".
    private func postMediaLine(_ meta: PostMeta) -> String? {
        switch meta.mediaType {
        case "carousel": return "\(meta.mediaCount ?? 2) items"
        case "video": return "Video"
        case "gif": return "GIF"
        case "image": return "Image"
        default: return nil
        }
    }

    // MARK: - Tool

    @ViewBuilder
    private func toolCards(_ meta: ToolMeta, layout: PanelLayout) -> some View {
        let topics = layout.chips["topics"] ?? []
        let hasRepoData = meta.stars != nil || meta.language != nil || meta.license != nil
            || meta.lastPushedAt != nil || !topics.isEmpty
        if meta.repoURL != nil, hasRepoData {
            SubCard(title: "GitHub") {
                VStack(alignment: .leading, spacing: 8) {
                    if let content = FactsSubCardContent(rows: [
                        ("Stars", meta.stars.map { "★ \(ToolMeta.compactCount($0))" }),
                        ("Language", meta.language),
                        ("Licence", meta.license),
                        ("Last update", meta.lastPushedAt?.formatted(date: .abbreviated, time: .omitted)),
                    ]) {
                        FactsSubCardBody(content: content)
                    }
                    if !topics.isEmpty {
                        ChipsSubCardBody(chips: topics)
                    }
                }
            }
        }

        linksCard(layout)
    }

    private static func toolSubtypeLabel(_ subtype: String?) -> String? {
        switch subtype {
        case "app": return "App"
        case "web app": return "Web app"
        case "library": return "Library"
        case "extension": return "Extension"
        case "AI model": return "AI model"
        default: return subtype
        }
    }

    /// "Paid · $4.99", "Freemium · from $8", "Free", "Open source".
    private func toolPriceLine(_ meta: ToolMeta) -> String? {
        let label: String?
        switch meta.pricing {
        case "free": label = "Free"
        case "paid": label = "Paid"
        case "freemium": label = "Freemium"
        case "open source": label = "Open source"
        default: label = nil
        }
        let price = ProductMeta.formattedPrice(meta.price, currency: meta.currency)
        switch (label, price) {
        case let (label?, price?): return meta.pricing == "freemium" ? "\(label) · from \(price)" : "\(label) · \(price)"
        case let (label?, nil): return label
        case let (nil, price?): return price
        default: return nil
        }
    }

    /// The tool's own site: the repo's homepage for a GitHub / App Store save; for any other
    /// save the Source row opens the canonical page, so the homepage shows only when there is
    /// no canonical page (and the links filter drops it when it is the saved URL).
    private func toolWebsiteURL(_ meta: ToolMeta) -> String? {
        let savedFromAppStore = item.sourceURL
            .flatMap { URL(string: $0) }
            .map { PageClassifier.isAppStoreAppURL($0) } ?? false
        guard meta.repoURL != nil || savedFromAppStore else {
            return meta.canonicalURL?.nilIfEmpty == nil ? meta.homepageURL : nil
        }
        return meta.homepageURL
    }

    // MARK: - Resource

    private static func resourceSubtypeLabel(_ subtype: String?) -> String? {
        guard let subtype = subtype?.nilIfEmpty else { return nil }
        return subtype.prefix(1).uppercased() + String(subtype.dropFirst())
    }

    // MARK: - Book

    /// The Amazon link unless the item was saved from Amazon (the Source row covers it; the
    /// link is normalised to /dp/<isbn10>, so it never equals the saved URL).
    private static func bookAmazonLink(_ meta: BookMeta, sourceURL: String?) -> String? {
        guard let amazon = meta.amazonURL else { return nil }
        if let source = sourceURL.flatMap({ URL(string: $0) }), BookReader.isAmazonURL(source) { return nil }
        return amazon
    }

    // MARK: - Course

    /// The cohort start date while it is still ahead; nil once it has passed.
    private static func upcomingStart(_ date: Date?) -> String? {
        guard let date, date >= .now else { return nil }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func copyToPasteboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    private func musicDuration(_ seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        let minutes = seconds / 60
        let remaining = seconds % 60
        return String(format: "%d:%02d", minutes, remaining)
    }

    // MARK: - Sub-card builders

    @ViewBuilder
    private func factRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.karst(.caption2, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
            Text(value)
                .font(.karst(.callout))
                .foregroundStyle(theme.textPrimary)
        }
    }

    /// Rows with an http(s) value — or a `links` entry for their label — open that URL.
    @ViewBuilder
    private func factsCard(title: String, rows: [(String, String?)], links: [String: String] = [:]) -> some View {
        if let content = FactsSubCardContent(rows: rows, links: links) {
            SubCard(title: title) { FactsSubCardBody(content: content) }
        }
    }

    @ViewBuilder
    private func chipsCard(title: String, chips: [String], caption: String? = nil) -> some View {
        let values = chips.filter { !$0.isEmpty }
        if !values.isEmpty || caption?.isEmpty == false {
            SubCard(title: title) {
                ChipsSubCardBody(chips: values, caption: caption)
            }
        }
    }

    @ViewBuilder
    private func refsCard(title: String, refs: [EntityRef]) -> some View {
        let values = refs.filter { !$0.name.isEmpty }
        if !values.isEmpty {
            SubCard(title: title) {
                RefsSubCardBody(refs: values, storeItems: storeItems)
            }
        }
    }

    @ViewBuilder
    private func textCard(title: String, text: String?) -> some View {
        if let text = text?.nilIfEmpty {
            SubCard(title: title) {
                Text(text)
                    .font(.karst(.callout))
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func imageGalleryCard(
        title: String,
        roles: [String],
        bleedsToTop: Bool = false,
        mainHeight: CGFloat = 140,
        showsThumbnails: Bool = false
    ) -> some View {
        let imgs = item.renderableImages(matchingRoles: roles)
        if !imgs.isEmpty {
            SubCard(title: bleedsToTop ? "" : title, bleedsToTop: bleedsToTop) {
                ImageGallerySubCardBody(
                    images: imgs,
                    mainHeight: mainHeight,
                    showsThumbnails: showsThumbnails
                )
            }
            .horizontalBleed(active: bleedsToTop && embedsInPanel)
        }
    }

    @ViewBuilder
    private func faqCard(title: String, items: [FAQItem]) -> some View {
        let valid = items.filter { !$0.question.isEmpty && !$0.answer.isEmpty }
        if !valid.isEmpty {
            SubCard(title: title) {
                FAQSubCardBody(items: valid)
            }
        }
    }
}

// MARK: - Horizontal bleed (panel cover)

private struct HorizontalBleedModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.padding(.horizontal, -16)
        } else {
            content
        }
    }
}

private extension View {
    func horizontalBleed(active: Bool) -> some View {
        modifier(HorizontalBleedModifier(active: active))
    }
}

// MARK: - SubCard primitive

struct SubCard<Content: View>: View {
    let title: String
    var bleedsToTop: Bool = false
    @ViewBuilder var content: () -> Content

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !bleedsToTop, !title.isEmpty {
                titleLabel
            }

            content()

            if bleedsToTop, !title.isEmpty {
                titleLabel
                    .padding(.horizontal, 12)
            }
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            cardOutline
        }
    }

    private var titleLabel: some View {
        Text(title)
            .font(.karst(.caption, weight: .semibold))
            .foregroundStyle(theme.textSecondary)
            .textCase(.uppercase)
            .kerning(0.5)
    }

    private var cardPadding: EdgeInsets {
        if bleedsToTop {
            EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0)
        } else {
            EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        }
    }

    @ViewBuilder
    private var cardOutline: some View {
        if bleedsToTop {
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 0,
                    bottomLeading: 10,
                    bottomTrailing: 10,
                    topTrailing: 0
                ),
                style: .continuous
            )
            .stroke(theme.border, lineWidth: 1)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        }
    }
}

// MARK: - Facts

struct FactsSubCardContent {
    let rows: [(label: String, value: String, url: URL?)]

    /// Empty values are dropped (nil when nothing is left). A row opens `links[label]` when
    /// given, else its own value when that is an http(s) URL.
    init?(rows: [(String, String?)], links: [String: String] = [:]) {
        let filled = rows.compactMap { label, value -> (String, String, URL?)? in
            guard let v = value?.nilIfEmpty else { return nil }
            return (label, v, Self.webURL(links[label] ?? v))
        }
        guard !filled.isEmpty else { return nil }
        self.rows = filled
    }

    static func webURL(_ string: String) -> URL? {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return nil }
        return url
    }
}

struct FactsSubCardBody: View {
    let content: FactsSubCardContent

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(content.rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .font(.karst(.caption2, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                    if let url = row.url {
                        Link(destination: url) {
                            Text(row.value)
                                .font(.karst(.callout))
                                .foregroundStyle(theme.accentColor)
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                        .help(url.absoluteString)
                    } else {
                        Text(row.value)
                            .font(.karst(.callout))
                            .foregroundStyle(theme.textPrimary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}

// MARK: - Chips

struct ChipsSubCardBody: View {
    let chips: [String]
    var caption: String?

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let caption = caption?.nilIfEmpty {
                Text(caption)
                    .font(.karst(.caption))
                    .foregroundStyle(theme.textSecondary)
            }
            if !chips.isEmpty {
                TagFlowLayout(spacing: 6) {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip)
                            .font(.karst(.caption))
                            .foregroundStyle(theme.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(theme.borderSubtle.opacity(0.55))
                            .clipShape(Capsule())
                            .overlay {
                                Capsule().stroke(theme.border, lineWidth: 1)
                            }
                    }
                }
            }
        }
    }
}

// MARK: - Entity refs

struct RefsSubCardBody: View {
    let refs: [EntityRef]
    let storeItems: [Item]

    @Environment(\.appTheme) private var theme
    @Environment(\.detailOpenItem) private var openItem

    var body: some View {
        TagFlowLayout(spacing: 6) {
            ForEach(Array(refs.enumerated()), id: \.offset) { _, ref in
                refChip(ref)
            }
        }
    }

    @ViewBuilder
    private func refChip(_ ref: EntityRef) -> some View {
        let matched = ref.slug.flatMap { slug in
            storeItems.first { $0.slug == slug }
        }
        if let matched, let openItem {
            Button {
                openItem(matched)
            } label: {
                chipLabel(ref.name)
            }
            .buttonStyle(.plain)
        } else {
            chipLabel(ref.name)
        }
    }

    private func chipLabel(_ name: String) -> some View {
        Text(name)
            .font(.karst(.caption))
            .foregroundStyle(theme.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(theme.accentSubtle.opacity(0.35))
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(theme.border, lineWidth: 1)
            }
    }
}

// MARK: - Image gallery

struct ImageGallerySubCardBody: View {
    let images: [ItemImage]
    var mainHeight: CGFloat = 140
    var showsThumbnails: Bool = false

    @Environment(\.appTheme) private var theme
    @State private var previewID: PersistentIdentifier?

    private var displayed: ItemImage? {
        if let id = previewID,
           let match = images.first(where: { $0.persistentModelID == id }) {
            return match
        }
        return images.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let img = displayed, let data = img.data, let platform = platformImage(from: data) {
                platform
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: mainHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if showsThumbnails, images.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(images, id: \.persistentModelID) { image in
                            thumbnail(for: image)
                        }
                    }
                }
            }
        }
    }

    private func thumbnail(for image: ItemImage) -> some View {
        let selected = displayed?.persistentModelID == image.persistentModelID
        return Button {
            previewID = image.persistentModelID
        } label: {
            Group {
                if let data = image.data, let img = platformImage(from: data) {
                    img.resizable().aspectRatio(contentMode: .fill)
                } else {
                    theme.borderSubtle
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(selected ? theme.accentColor : theme.border, lineWidth: selected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func platformImage(from data: Data) -> Image? {
        #if os(macOS)
        guard let ns = NSImage(data: data) else { return nil }
        return Image(nsImage: ns)
        #else
        guard let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
        #endif
    }
}

// MARK: - FAQ

struct FAQSubCardBody: View {
    let items: [FAQItem]

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, faq in
                DisclosureGroup {
                    Text(faq.answer)
                        .font(.karst(.callout))
                        .foregroundStyle(theme.textSecondary)
                        .padding(.top, 4)
                } label: {
                    Text(faq.question)
                        .font(.karst(.callout, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                }
            }
        }
    }
}

// MARK: - Item helpers

extension Item {
    func renderableImages(matchingRoles roles: [String]) -> [ItemImage] {
        (images ?? []).filter { roles.contains($0.role) && $0.hasRenderableCoverData }
    }

    var hasRichTypedPanel: Bool {
        switch ItemKind(rawValue: kind) ?? .link {
        case .typeface: return typefaceMeta() != nil
        case .website: return websiteMeta() != nil
        case .individual: return individualMeta() != nil
        case .studio: return studioMeta() != nil
        case .foundry: return foundryMeta() != nil
        case .place: return placeMeta() != nil
        case .music: return musicMeta() != nil
        case .product: return productMeta() != nil
        case .post: return postMeta() != nil
        case .tool: return toolMeta() != nil
        case .resource: return resourceMeta() != nil
        case .book: return bookMeta() != nil
        case .course: return courseMeta() != nil
        case .article: return articleMeta() != nil
        case .link: return false
        }
    }

    /// The grid card's one-line kind summary under the hover title (nil = no line).
    var cardKindLine: String? {
        switch ItemKind(rawValue: kind) ?? .link {
        case .product: return productMeta()?.cardKindLine
        case .post: return postMeta()?.cardKindLine
        case .tool: return toolMeta()?.cardKindLine
        case .resource: return resourceMeta()?.cardKindLine
        case .book: return bookMeta()?.cardKindLine
        case .course: return courseMeta()?.cardKindLine
        case .article: return articleMeta()?.cardKindLine
        default: return nil
        }
    }

    var typedTopMediaRoles: [String] {
        switch ItemKind(rawValue: kind) ?? .link {
        case .typeface:
            return [ItemImageRole.specimen.rawValue, ItemImageRole.cover.rawValue]
        case .website, .product, .post:
            return [ItemImageRole.cover.rawValue, ItemImageRole.gallery.rawValue]
        default:
            return [ItemImageRole.cover.rawValue]
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

private extension Array where Element == String {
    var nilIfEmpty: [String]? { isEmpty ? nil : self }
}
