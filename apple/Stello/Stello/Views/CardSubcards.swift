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

    private var itemKind: ItemKind {
        ItemKind(rawValue: item.kind) ?? .link
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

    private var canEnrich: Bool {
        item.enrichmentStatus == "text_done"
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
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            topImagesSubCard()
                .gridCellColumns(columns.count)

            panelSummaryCard()
                .gridCellColumns(columns.count)

            if item.hasRichTypedPanel {
                switch itemKind {
                case .typeface:
                    if let meta = item.typefaceMeta() { typefaceCards(meta) }
                case .website:
                    if let meta = item.websiteMeta() { websiteCards(meta) }
                case .individual:
                    if let meta = item.individualMeta() { individualCards(meta) }
                case .studio:
                    if let meta = item.studioMeta() { studioCards(meta) }
                case .foundry:
                    if let meta = item.foundryMeta() { foundryCards(meta) }
                case .place:
                    if let meta = item.placeMeta() { placeCards(meta) }
                case .link:
                    EmptyView()
                }
            } else {
                genericSubCards()
            }
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

    @ViewBuilder
    private func panelSummaryCard() -> some View {
        let kindRows = kindSpecificSummaryRows()
        summaryCard(title: "Summary", rows: mergedSummaryRows(kindSpecific: kindRows))
    }

    private func mergedSummaryRows(kindSpecific: [(String, String?)]) -> [(String, String?)] {
        var rows: [(String, String?)] = [
            ("Title", item.title.nilIfEmpty ?? "Untitled"),
        ]

        let metaTexts = Set(kindSpecific.compactMap { $0.1?.nilIfEmpty?.lowercased() })
        if let summary = item.summary?.nilIfEmpty,
           !metaTexts.contains(summary.lowercased()) {
            rows.append(("Overview", summary))
        }

        rows.append(contentsOf: kindSpecific)

        if let author = item.author?.nilIfEmpty {
            rows.append(("Author", author))
        }

        let linkLabel = item.displayLink
        if !linkLabel.isEmpty, linkLabel != "local" {
            rows.append(("Link", linkLabel))
        }
        if let url = item.sourceURL?.nilIfEmpty {
            rows.append(("URL", url))
        }
        rows.append(("Added", weekFooter))

        return rows
    }

    private func kindSpecificSummaryRows() -> [(String, String?)] {
        switch itemKind {
        case .typeface:
            guard let meta = item.typefaceMeta() else { return [] }
            return [
                ("Overview", meta.overview),
                ("Description", meta.description),
                ("Specimen link", meta.specimenLink ?? meta.specimenURL),
            ]
        case .website:
            guard let meta = item.websiteMeta() else { return [] }
            return [
                ("Tagline", meta.tagline),
                ("Description", meta.description),
            ]
        default:
            return []
        }
    }

    // MARK: - Generic link sub-cards

    @ViewBuilder
    private func genericSubCards() -> some View {
        if let md = item.bodyMarkdown, !md.isEmpty {
            markdownSubCard(md)
        }

        snippetsSubCard
        whySavedSubCard
        tagsSubCard

        if canEnrich {
            enrichSubCard
        }
    }

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

    @ViewBuilder
    private var snippetsSubCard: some View {
        SubCard(title: "Key snippets") {
            if sortedSnippets.isEmpty {
                Text("No snippets yet.")
                    .font(.karst(.caption))
                    .foregroundStyle(theme.textSecondary)
                    .italic()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(sortedSnippets, id: \.persistentModelID) { snippet in
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
                        Button {
                            acceptWhySavedSuggestion(suggestion)
                        } label: {
                            Text(humanizeReason(suggestion))
                                .font(.karst(.caption))
                                .foregroundStyle(theme.accentContrast)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(theme.accentColor)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tagsSubCard: some View {
        if !sortedTags.isEmpty {
            SubCard(title: "Tags") {
                TagFlowLayout(spacing: 6) {
                    ForEach(sortedTags, id: \.persistentModelID) { tag in
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
            Button {
                enrichmentCoordinator.scheduleEnrichment(for: item, context: context)
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

    // MARK: - Typeface

    @ViewBuilder
    private func typefaceCards(_ meta: TypefaceMeta) -> some View {
        chipsCard(title: "Classification", chips: meta.classification + meta.personality)

        let weightCount = meta.weightsCount ?? meta.weightCount.map(String.init)
        chipsCard(
            title: "Weights",
            chips: meta.weightTypes,
            caption: weightCount.map { "\($0) weights" }
        )

        let styleCount = meta.stylesCount ?? meta.styleCount.map(String.init)
        chipsCard(
            title: "Styles",
            chips: meta.styleTypes,
            caption: styleCount.map { "\($0) styles" }
        )

        let langCount = meta.languagesCount ?? meta.languageSupport.map(String.init)
        chipsCard(
            title: "Languages",
            chips: meta.languagesRegion,
            caption: langCount.map { "\($0) languages" }
        )

        formatsTechCard(meta)

        factsCard(title: "Licensing & pricing", rows: [
            ("License", meta.license),
            ("Paid / free", meta.paidOrFree),
            ("Starting price", meta.startingPrice),
            ("Trial", meta.trialAvailability.map { $0 ? "Available" : "No" }),
            ("Student discount", meta.studentDiscount.map { $0 ? "Yes" : "No" }),
        ])
        refsCard(title: "Distributed on", refs: meta.distributedOn)

        refsCard(title: "Foundry & designer", refs: foundryDesignerRefs(from: meta))
        if let fallback = meta.typeDesignerFallback?.nilIfEmpty {
            factsCard(title: "Designer", rows: [("Name", fallback)])
        }

        factsCard(title: "Technical", rows: [
            ("Release year", meta.releaseYear),
            ("Last update", meta.lastUpdate),
            ("Version", meta.version),
            ("Family count", meta.familyCount),
            ("Family fonts", meta.familyFontNames.isEmpty ? nil : meta.familyFontNames.map(\.name).joined(separator: ", ")),
        ])

        imageGalleryCard(title: "Letterform graphics", roles: [ItemImageRole.graphic.rawValue])

        factsCard(title: "Insights", rows: [
            ("Highlights", meta.highlights),
            ("Use case", meta.useCase),
            ("Design features", meta.designFeatures),
        ])

        factsCard(title: "Related fonts", rows: [
            ("Pairing", meta.pairingFonts),
            ("Similar", meta.similarFonts),
            ("Fork", meta.forkFonts),
        ])
        imageGalleryCard(title: "Previews", roles: [ItemImageRole.preview.rawValue])

        faqCard(title: "FAQs", items: meta.faqs)
        refsCard(title: "Appears in", refs: meta.creatives + meta.websites)
    }

    // MARK: - Website

    @ViewBuilder
    private func websiteCards(_ meta: WebsiteMeta) -> some View {
        chipsCard(title: "Category", chips: meta.categories)
        chipsCard(title: "Traits", chips: meta.traits)
        chipsCard(title: "Focus areas", chips: meta.focusAreas)

        textCard(title: "Review", text: meta.review)

        chipsCard(title: "Platform", chips: meta.platform)
        chipsCard(title: "Tech stack", chips: meta.techStack)

        refsCard(title: "Founders", refs: meta.founders)
        if let name = meta.founderName?.nilIfEmpty {
            factsCard(title: "Founder", rows: [("Name", name)])
        }
        refsCard(title: "Branding by", refs: meta.brandingMadeBy)
        refsCard(title: "Site designer", refs: meta.siteDesignerAgency)
        if let agency = meta.agencyName?.nilIfEmpty {
            factsCard(title: "Agency", rows: [
                ("Name", agency),
                ("URL", meta.agencyURL),
            ])
        }
        refsCard(title: "Creatives", refs: meta.creatives)

        refsCard(title: "Typography", refs: meta.typography)
        if let count = meta.typefaceCount?.nilIfEmpty {
            factsCard(title: "Typeface count", rows: [("Count", count)])
        }
        refsCard(title: "Foundries", refs: meta.typeFoundries)

        chipsCard(title: "Web pages", chips: meta.webPages, caption: meta.webPagesCount)
        chipsCard(title: "Key components", chips: meta.keyComponents, caption: meta.keyComponentsCount)

        factsCard(title: "Timeline", rows: [
            ("First published", meta.firstPublished),
            ("Date added", meta.dateAdded),
            ("Date updated", meta.dateUpdated),
        ])
    }

    // MARK: - Individual

    @ViewBuilder
    private func individualCards(_ meta: IndividualMeta) -> some View {
        factsCard(title: "Identity", rows: [
            ("Pronouns", meta.pronouns),
            ("Bio", meta.bio),
            ("Location", meta.location?.name),
        ])

        chipsCard(title: "Professions", chips: meta.professions)
        chipsCard(title: "Traits", chips: meta.traits)
        factsCard(title: "Professional", rows: [
            ("Experience", meta.professionalExperience.map { "\($0) years" }),
            ("Current role", meta.currentRole),
            ("Employer", meta.currentEmployer),
            ("Notable works", meta.notableWorks),
            ("Signature style", meta.signatureStyle),
        ])

        factsCard(title: "Work & community", rows: [
            ("Own products", meta.ownProductsList),
            ("Speaking", meta.speaking),
            ("Workshops", meta.workshops),
            ("Community", meta.communityWork),
            ("Tools & stack", meta.toolsAndTechStack),
        ])

        factsCard(title: "Contact & social", rows: [
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
        ])

        factsCard(title: "Personals", rows: [
            ("Favourite book", meta.favouriteBook),
            ("Fun fact", meta.funFact),
            ("Hobbies", meta.hobbies),
        ])

        refsCard(title: "Typefaces", refs: meta.typefaces)
        refsCard(title: "Foundries", refs: meta.typeFoundries)
    }

    // MARK: - Studio

    @ViewBuilder
    private func studioCards(_ meta: StudioMeta) -> some View {
        refsCard(title: "Work", refs: meta.work)
        refsCard(title: "Team", refs: meta.team)
    }

    // MARK: - Foundry

    @ViewBuilder
    private func foundryCards(_ meta: FoundryMeta) -> some View {
        factsCard(title: "About", rows: [
            ("Description", meta.description),
            ("Category", meta.category),
        ])

        factsCard(title: "Origin & team", rows: [
            ("Geography", meta.geography?.name),
            ("Founded", meta.foundedYear),
        ])
        refsCard(title: "Founders & designers", refs: meta.foundersDesigners)

        factsCard(title: "Pricing & licensing", rows: [
            ("Price range", meta.priceRange),
            ("Trial fonts", meta.trialFonts.map { $0 ? "Yes" : "No" }),
            ("Student discount", meta.studentDiscount.map { $0 ? "Yes" : "No" }),
        ])
        chipsCard(title: "Licensing types", chips: meta.licensingTypes)

        factsCard(title: "Design approach", rows: [
            ("Philosophy", meta.designPhilosophy),
        ])
        chipsCard(title: "Popular fonts", chips: meta.popularFonts)
        chipsCard(title: "Specialisation", chips: meta.specialisation)
        chipsCard(title: "Custom services", chips: meta.customServices)

        factsCard(title: "Presence", rows: [
            ("Social", meta.social),
            ("Email", meta.email),
            ("Thoughts", meta.thoughts),
        ])
        chipsCard(title: "Distribution", chips: meta.distribution)

        refsCard(title: "Typefaces", refs: meta.typefaces)
        refsCard(title: "Websites", refs: meta.websites)
        refsCard(title: "Creatives", refs: meta.creatives)
    }

    // MARK: - Place

    @ViewBuilder
    private func placeCards(_ meta: PlaceMeta) -> some View {
        factsCard(title: "Location", rows: [
            ("City", meta.city),
            ("Country", meta.country),
        ])
    }

    // MARK: - Sub-card builders

    private func foundryDesignerRefs(from meta: TypefaceMeta) -> [EntityRef] {
        var refs: [EntityRef] = []
        if let foundry = meta.typeFoundry { refs.append(foundry) }
        refs.append(contentsOf: meta.typeDesigner)
        return refs
    }

    @ViewBuilder
    private func formatsTechCard(_ meta: TypefaceMeta) -> some View {
        let featureText = meta.openTypeFeatures.nilIfEmpty?.joined(separator: ", ")
        let hasContent = !meta.availableFormats.isEmpty
            || meta.variableFontSupport != nil
            || featureText != nil
        if hasContent {
            SubCard(title: "Formats & tech") {
                VStack(alignment: .leading, spacing: 8) {
                    if !meta.availableFormats.isEmpty {
                        ChipsSubCardBody(chips: meta.availableFormats)
                    }
                    if let vfs = meta.variableFontSupport {
                        factRow(label: "Variable font", value: vfs ? "Yes" : "No")
                    }
                    if let featureText {
                        factRow(label: "OpenType features", value: featureText)
                    }
                }
            }
        }
    }

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

    @ViewBuilder
    private func summaryCard(title: String, rows: [(String, String?)]) -> some View {
        if let content = FactsSubCardContent(rows: rows) {
            SubCard(title: title) { FactsSubCardBody(content: content) }
        }
    }

    @ViewBuilder
    private func factsCard(title: String, rows: [(String, String?)]) -> some View {
        if let content = FactsSubCardContent(rows: rows) {
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
    let rows: [(label: String, value: String)]

    init?(rows: [(String, String?)]) {
        let filled = rows.compactMap { label, value -> (String, String)? in
            guard let v = value?.nilIfEmpty else { return nil }
            return (label, v)
        }
        guard !filled.isEmpty else { return nil }
        self.rows = filled
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
                    Text(row.value)
                        .font(.karst(.callout))
                        .foregroundStyle(theme.textPrimary)
                        .textSelection(.enabled)
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
        case .link: return false
        }
    }

    var typedTopMediaRoles: [String] {
        switch ItemKind(rawValue: kind) ?? .link {
        case .typeface:
            return [ItemImageRole.specimen.rawValue, ItemImageRole.cover.rawValue]
        case .website:
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
