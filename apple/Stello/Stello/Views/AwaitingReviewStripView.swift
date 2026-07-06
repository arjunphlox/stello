import SwiftUI
import SwiftData

struct AwaitingReviewStripView: View {
    let items: [Item]
    var selectedItem: Item? = nil
    var panelContent: SidePanelContent = .none
    var onCardTap: ((Item) -> Void)? = nil
    var onDismiss: (Item) -> Void

    @Environment(\.appTheme) private var theme

    private static let thumbSize: CGFloat = 48
    private static let thumbCornerRadius: CGFloat = 6
    private static let cardCornerRadius: CGFloat = StelloLayout.headerCornerRadius

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: StelloLayout.sectionGap) {
                ForEach(items) { item in
                    card(for: item)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier("awaitingReviewStrip")
    }

    @ViewBuilder
    private func card(for item: Item) -> some View {
        let isSelected = selectedItem?.persistentModelID == item.persistentModelID
            && panelContent == .itemDetail

        cardButton(for: item) {
            HStack(spacing: 10) {
                coverThumb(for: item)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.karst(.subheadline, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Text(AwaitingReviewFilter.suggestionsLabel(for: item))
                        .font(.karst(.caption))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: 168, alignment: .leading)

                Button {
                    onDismiss(item)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss review")
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 8)
            .background(theme.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
                        .stroke(theme.accentColor, lineWidth: 1)
                }
            }
        }
    }

    @ViewBuilder
    private func cardButton(for item: Item, @ViewBuilder label: () -> some View) -> some View {
        if let onCardTap {
            Button {
                onCardTap(item)
            } label: {
                label()
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: item) {
                label()
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func coverThumb(for item: Item) -> some View {
        let cacheKey = "\(item.persistentModelID)-\(item.coverImage?.data?.count ?? 0)"
        Group {
            if let data = item.coverImage?.data,
               let image = ItemCardView.platformImage(data, cacheKey: cacheKey) {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: Self.thumbCornerRadius, style: .continuous)
                    .fill(theme.borderSubtle)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
            }
        }
        .frame(width: Self.thumbSize, height: Self.thumbSize)
        .clipShape(RoundedRectangle(cornerRadius: Self.thumbCornerRadius, style: .continuous))
    }
}
