import SwiftUI

/// Centered capsule Liquid Glass search field — floats over scrolling content near the bottom edge.
struct FloatingSearchBar: View {
    @Binding var text: String

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: StelloLayout.iconButtonSymbolSize, weight: .medium))
                .foregroundStyle(theme.textSecondary)
            TextField("Search items…", text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(theme.textPrimary)
        }
        .padding(.horizontal, 16)
        .frame(height: StelloLayout.floatingSearchBarHeight)
        .frame(maxWidth: StelloLayout.floatingSearchBarMaxWidth)
        .glassEffect(.regular, in: .capsule)
    }
}
