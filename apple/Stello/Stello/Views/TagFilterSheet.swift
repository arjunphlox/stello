import SwiftUI

struct TagFilterSheet: View {
    let allItems: [Item]
    @Binding var selectedTagNames: Set<String>
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    private let categories = ["format", "domain", "style", "subject", "tool", "location", "mood", "color", "intent"]

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

    var body: some View {
        NavigationStack {
            List {
                ForEach(categories, id: \.self) { category in
                    let rows = tags(in: category)
                    if !rows.isEmpty {
                        Section(category.capitalized) {
                            ForEach(rows, id: \.name) { row in
                                tagRow(row)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filter by Tag")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(theme.accentColor)
                }
                if !selectedTagNames.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Clear") { selectedTagNames.removeAll() }
                    }
                }
            }
        }
    }

    private func tagRow(_ row: (name: String, count: Int)) -> some View {
        Button {
            if selectedTagNames.contains(row.name) { selectedTagNames.remove(row.name) }
            else { selectedTagNames.insert(row.name) }
        } label: {
            HStack {
                Text(row.name)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text("\(row.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.textSecondary)
                if selectedTagNames.contains(row.name) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.accentColor)
                }
            }
        }
    }
}

#Preview {
    TagFilterSheet(allItems: [], selectedTagNames: .constant([]))
        .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
        .preferredColorScheme(.dark)
}
