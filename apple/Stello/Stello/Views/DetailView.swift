import SwiftUI
import SwiftData

struct DetailView: View {
    @Bindable var item: Item
    var embedsInPanel: Bool = false

    @Environment(\.appTheme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.enrichmentCoordinator) private var enrichmentCoordinator

    @State private var contentWidth: CGFloat = 300

    private static let twoColumnThreshold: CGFloat = 520

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

    private var usesTwoColumns: Bool {
        embedsInPanel && contentWidth >= Self.twoColumnThreshold
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
        ScrollView {
            Group {
                if item.hasRichTypedPanel {
                    typedPanelContent
                } else {
                    genericPanelContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(embedsInPanel ? Color.clear : theme.background)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { _, newWidth in
            contentWidth = newWidth
        }
    }

    // MARK: - Typed rich panel

    @ViewBuilder
    private var typedPanelContent: some View {
        if embedsInPanel {
            if item.renderableImages(matchingRoles: item.typedTopMediaRoles).isEmpty {
                DetailImageStrip(item: item, bleedsToTop: true)
            } else {
                TypedTopMedia(item: item, roles: item.typedTopMediaRoles)
            }
        } else {
            DetailImageStrip(item: item, bleedsToTop: false)
        }

        VStack(alignment: .leading, spacing: 16) {
            metaSection

            if let summary = item.summary, !summary.isEmpty {
                Text(summary)
                    .font(.karst(.body))
                    .foregroundStyle(theme.textSecondary)
            }

            CardSubcards(item: item)
        }
        .padding(.horizontal, 16)
        .padding(.top, embedsInPanel ? 12 : 16)
        .padding(.bottom, 24)
    }

    // MARK: - Generic link panel (web parity)

    @ViewBuilder
    private var genericPanelContent: some View {
        DetailImageStrip(item: item, bleedsToTop: embedsInPanel)

        VStack(alignment: .leading, spacing: 20) {
            metaSection

            if let summary = item.summary, !summary.isEmpty {
                Text(summary)
                    .font(.karst(.body))
                    .foregroundStyle(theme.textSecondary)
            }

            lowerSections
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    // MARK: - Lower sections (multi-column when panel is wide)

    @ViewBuilder
    private var lowerSections: some View {
        let columns = usesTwoColumns
            ? [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)]
            : [GridItem(.flexible(), alignment: .top)]

        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
            if let md = item.bodyMarkdown, !md.isEmpty {
                markdownSection(md)
            }

            snippetsSection
            whySavedSection
            tagSection

            if canEnrich {
                enrichButton
            }
        }
    }

    // MARK: - Sections

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title.isEmpty ? "Untitled" : item.title)
                .font(.karst(.title2, weight: .semibold))
                .foregroundStyle(theme.textPrimary)

            HStack(spacing: 6) {
                let linkLabel = item.displayLink
                if !linkLabel.isEmpty {
                    Text(linkLabel)
                        .font(.karst(.caption, weight: .semibold))
                        .foregroundStyle(theme.accentColor)
                }
                if let author = item.author, !author.isEmpty {
                    Text("·").foregroundStyle(theme.border)
                    Text(author).font(.karst(.caption)).foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Text(weekFooter)
                    .font(.karst(.caption).monospacedDigit())
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private func markdownSection(_ text: String) -> some View {
        Group {
            if let attr = try? AttributedString(markdown: text) {
                Text(attr)
            } else {
                Text(text)
            }
        }
        .font(.karst(.callout))
        .foregroundStyle(theme.textSecondary)
    }

    @ViewBuilder
    private var snippetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Key snippets")

            if sortedSnippets.isEmpty {
                Text("No snippets yet.")
                    .font(.karst(.caption))
                    .foregroundStyle(theme.textSecondary)
                    .italic()
            } else {
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

    @ViewBuilder
    private var whySavedSection: some View {
        if !whySavedSuggestions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Why save?")
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
    private var tagSection: some View {
        if !sortedTags.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Tags")
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

    private var enrichButton: some View {
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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.karst(.caption, weight: .semibold))
            .foregroundStyle(theme.textSecondary)
            .textCase(.uppercase)
            .kerning(0.5)
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
}

// MARK: - Flow layout for tag chips

struct TagFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sub in subviews {
            let sz = sub.sizeThatFits(.unspecified)
            if x + sz.width > width, x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for sub in subviews {
            let sz = sub.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            sub.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        DetailView(item: SeedData.enrichedSampleItem)
    }
    .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
    .preferredColorScheme(.dark)
}
