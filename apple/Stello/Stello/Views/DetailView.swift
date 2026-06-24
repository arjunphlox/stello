import SwiftUI

struct DetailView: View {
    let item: Item
    @Environment(\.appTheme) private var theme

    private static let placeholderHues: [Double] = [18, 80, 38, 140, 25, 45, 12, 100]

    private var coverImage: ItemImage? {
        item.images?.first(where: \.isPrimary) ?? item.images?.first
    }

    private var sortedTags: [Tag] {
        (item.tags ?? []).sorted { $0.weight > $1.weight }
    }

    private var placeholderHue: Double {
        let idx = abs(item.slug.hashValue) % Self.placeholderHues.count
        return Self.placeholderHues[idx] / 360.0
    }

    /// Panel footer label "Wnn YYYY" per BUILD_SPEC.
    private var weekFooter: String {
        let key = WeekGroup.isoWeekKey(for: item.addedAt)
        guard key != "undated" else { return "Undated" }
        let parts = key.split(separator: "-")
        guard parts.count == 2 else { return key }
        return "\(parts[1]) \(parts[0])"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                coverSection
                VStack(alignment: .leading, spacing: 16) {
                    metaSection
                    if let summary = item.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.body)
                            .foregroundStyle(theme.textSecondary)
                    }
                    if let md = item.bodyMarkdown, !md.isEmpty {
                        markdownSection(md)
                    }
                    if !sortedTags.isEmpty {
                        tagSection
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
        }
        .background(theme.background)
        .navigationTitle(item.title.isEmpty ? "Untitled" : item.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Sections

    @ViewBuilder
    private var coverSection: some View {
        if let data = coverImage?.data, let img = platformImage(from: data) {
            img
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .clipped()
        } else {
            Color(hue: placeholderHue,
                  saturation: 0.4,
                  brightness: theme.mode == .dark ? 0.26 : 0.88)
                .frame(height: 180)
        }
    }

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title.isEmpty ? "Untitled" : item.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(theme.textPrimary)

            HStack(spacing: 6) {
                if let domain = item.domain, !domain.isEmpty {
                    Text(domain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.accentColor)
                }
                if let author = item.author, !author.isEmpty {
                    Text("·").foregroundStyle(theme.border)
                    Text(author).font(.caption).foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Text(weekFooter)
                    .font(.caption.monospacedDigit())
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
        .font(.callout)
        .foregroundStyle(theme.textSecondary)
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.textSecondary)
                .textCase(.uppercase)
                .kerning(0.5)

            TagFlowLayout(spacing: 6) {
                ForEach(sortedTags, id: \.name) { tag in
                    Text(tag.name)
                        .font(.caption)
                        .foregroundStyle(theme.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(theme.borderSubtle)
                        .clipShape(Capsule())
                        .opacity(max(0.55, tag.weight))
                }
            }
        }
    }

    // MARK: - Platform image helper

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
    NavigationStack {
        DetailView(item: SeedData.sampleItem)
    }
    .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
    .preferredColorScheme(.dark)
}
