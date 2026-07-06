import SwiftUI

/// Tag filter panel — mirrors web `#tpl-filters`: search field + collapsible category chips.
struct TagFilterContent: View {
    let allItems: [Item]
    @Binding var selectedTagNames: Set<String>
    @Environment(\.appTheme) private var theme

    @State private var searchText = ""
    @State private var expandedCategories: Set<String> = ["intent"]

    private let categories = ["intent", "format", "domain", "style", "subject", "tool", "location", "mood", "color"]

    private func categoryLabel(_ category: String) -> String {
        switch category {
        case "intent": "Why saved"
        default: category.capitalized
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func tags(in category: String) -> [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in allItems {
            for tag in (item.tags ?? []) where tag.category == category {
                counts[tag.name, default: 0] += 1
            }
        }
        return counts
            .map { (name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }

    private func filteredTags(in category: String) -> [(name: String, count: Int)] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rows = tags(in: category)
        guard !query.isEmpty else { return rows }
        return rows.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Search tags…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.karst(.subheadline))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(theme.background)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(theme.border, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                if !selectedTagNames.isEmpty {
                    Button("Clear all") { selectedTagNames.removeAll() }
                        .font(.karst(.subheadline))
                        .foregroundStyle(theme.accentColor)
                }

                ForEach(categories, id: \.self) { category in
                    let rows = filteredTags(in: category)
                    if !rows.isEmpty {
                        categorySection(category: category, rows: rows)
                    }
                }
            }
            .padding(16)
        }
    }

    private func categorySection(category: String, rows: [(name: String, count: Int)]) -> some View {
        let isExpanded = isSearching || expandedCategories.contains(category)
        let totalCount = rows.reduce(0) { $0 + $1.count }

        return VStack(alignment: .leading, spacing: isExpanded ? 8 : 0) {
            Button {
                toggleCategory(category)
            } label: {
                HStack(spacing: 8) {
                    Text(categoryLabel(category))
                        .font(.karst(.footnote, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                    Spacer(minLength: 4)
                    Text("\(totalCount)")
                        .font(.karst(.caption))
                        .foregroundStyle(theme.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                FlowLayout(spacing: 5) {
                    ForEach(rows, id: \.name) { row in
                        tagChip(row)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
        }
    }

    private func toggleCategory(_ category: String) {
        if expandedCategories.contains(category) {
            expandedCategories.remove(category)
        } else {
            expandedCategories.insert(category)
        }
    }

    private func tagChip(_ row: (name: String, count: Int)) -> some View {
        let isActive = selectedTagNames.contains(row.name)
        return Button {
            if isActive { selectedTagNames.remove(row.name) }
            else { selectedTagNames.insert(row.name) }
        } label: {
            HStack(spacing: 4) {
                Text(row.name)
                    .font(.karst(.footnote, weight: .medium))
                Text("\(row.count)")
                    .font(.karst(.caption2))
                    .opacity(0.6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(theme.textPrimary)
            .background(isActive ? theme.accentSubtle : theme.backgroundSubtle)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(isActive ? theme.textPrimary : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Simple wrapping layout for tag chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

struct TagFilterSheet: View {
    let allItems: [Item]
    @Binding var selectedTagNames: Set<String>
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    var body: some View {
        NavigationStack {
            TagFilterContent(allItems: allItems, selectedTagNames: $selectedTagNames)
                .navigationTitle("Filter by Tag")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .foregroundStyle(theme.accentColor)
                    }
                }
                #if os(iOS)
                .presentationDetents(
                    ProcessInfo.processInfo.arguments.contains("-screenshotFilterSheet")
                        ? [.medium, .large] : [.large]
                )
                #endif
        }
    }
}

#Preview {
    TagFilterSheet(allItems: [], selectedTagNames: .constant([]))
        .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
        .preferredColorScheme(.dark)
}
