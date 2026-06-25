import SwiftUI
import SwiftData

struct WeekSectionView: View {
    let group: WeekGroup
    let isExpanded: Bool
    let onToggle: () -> Void
    /// When provided (regular width: iPad/Mac), tapping a card sets the inspector
    /// selection. When nil (compact width: iPhone), cards push via NavigationLink.
    var selection: Binding<Item?>? = nil

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — tap to collapse/expand
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Text(group.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isExpanded ? theme.accentColor : theme.textSecondary)
                    Spacer()
                    Text("\(group.items.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(theme.textSecondary)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(theme.textSecondary)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                MasonryLayout(spacing: 12) {
                    ForEach(group.items) { item in
                        card(for: item)
                    }
                }
                .padding(.bottom, 12)
            }

            Divider()
                .overlay(theme.border)
        }
    }

    @ViewBuilder
    private func card(for item: Item) -> some View {
        if let selection {
            Button {
                selection.wrappedValue = item
            } label: {
                ItemCardView(
                    item: item,
                    isSelected: selection.wrappedValue?.persistentModelID == item.persistentModelID
                )
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: item) {
                ItemCardView(item: item)
            }
            .buttonStyle(.plain)
        }
    }
}
