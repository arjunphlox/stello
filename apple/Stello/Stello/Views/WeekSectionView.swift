import SwiftUI
import SwiftData

struct WeekSectionView: View {
    let group: WeekGroup
    let isExpanded: Bool
    let onToggle: () -> Void
    /// When provided (regular width: iPad/Mac), tapping a card opens the side panel.
    var selectedItem: Item? = nil
    var panelContent: SidePanelContent = .none
    var onCardTap: ((Item) -> Void)? = nil

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
        if let onCardTap {
            Button {
                onCardTap(item)
            } label: {
                ItemCardView(
                    item: item,
                    isSelected: selectedItem?.persistentModelID == item.persistentModelID
                        && panelContent == .itemDetail
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
