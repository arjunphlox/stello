import SwiftUI

/// Bottom control row — Add + Filter + search field + avatar — floats over the grid.
struct GridBottomControlBar: View {
    @Binding var searchText: String
    var hasActiveFilters: Bool = false
    var isFilterPanelOpen: Bool = false
    var isImportPanelOpen: Bool = false
    var isSettingsPanelOpen: Bool = false
    var forceFilterHover: Bool = false
    /// iPhone compact — 60pt controls lifted from the bottom edge.
    var compactPhone: Bool = false
    let onAdd: () -> Void
    let onFilter: () -> Void
    let onSettings: () -> Void

    @Environment(UserProfileStore.self) private var profile

    private var buttonSize: CGFloat {
        StelloLayout.controlBarButtonDiameter(compactPhone: compactPhone)
    }

    private var symbolSize: CGFloat {
        StelloLayout.controlBarSymbolSize(compactPhone: compactPhone)
    }

    var body: some View {
        HStack(spacing: StelloLayout.controlBarSpacing) {
            StelloGlassIconButton(
                systemName: "plus",
                style: .controlBar,
                isActive: isImportPanelOpen,
                controlBarDiameter: buttonSize,
                controlBarSymbolSize: symbolSize,
                label: "Add",
                action: onAdd
            )
            StelloGlassIconButton(
                systemName: "line.3.horizontal.decrease",
                style: .controlBar,
                isActive: isFilterPanelOpen || hasActiveFilters,
                forceHover: forceFilterHover,
                controlBarDiameter: buttonSize,
                controlBarSymbolSize: symbolSize,
                label: "Filters",
                action: onFilter
            )
            FloatingSearchField(text: $searchText, compactPhone: compactPhone)
            StelloGlassIconButton(
                systemName: "person.crop.circle.fill",
                style: .controlBarAvatar,
                isActive: isSettingsPanelOpen,
                avatarImage: profile.avatarImage(),
                controlBarDiameter: buttonSize,
                controlBarSymbolSize: symbolSize,
                label: "User Preferences",
                action: onSettings
            )
            .id(profile.avatarRevision)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Capsule Liquid Glass search field — shares material with the bottom control bar buttons.
struct FloatingSearchField: View {
    @Binding var text: String
    var compactPhone: Bool = false

    @Environment(\.appTheme) private var theme

    private var barHeight: CGFloat {
        StelloLayout.controlBarHeight(compactPhone: compactPhone)
    }

    private var symbolSize: CGFloat {
        StelloLayout.controlBarSymbolSize(compactPhone: compactPhone)
    }

    var body: some View {
        ZStack {
            Capsule()
                .fill(theme.surfaceRaised.opacity(StelloLayout.controlBarGlassFillOpacity))
            Capsule()
                .stroke(theme.border, lineWidth: 1)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: symbolSize, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                TextField(
                    "",
                    text: $text,
                    prompt: Text("Search items…").foregroundStyle(theme.textSecondary)
                )
                .textFieldStyle(.plain)
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, compactPhone ? 18 : 16)
        }
        .frame(height: barHeight)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

/// Legacy alias — use `GridBottomControlBar` for the full row.
struct FloatingSearchBar: View {
    @Binding var text: String

    var body: some View {
        FloatingSearchField(text: $text)
    }
}
