import SwiftUI

/// Bottom control row — account, view switch, search, Filter, Add (web order, PR #99) — floats over the grid.
struct GridBottomControlBar: View {
    @Binding var searchText: String
    var hasActiveFilters: Bool = false
    var isFilterPanelOpen: Bool = false
    var isImportPanelOpen: Bool = false
    var isSettingsPanelOpen: Bool = false
    var forceFilterHover: Bool = false
    /// iPhone compact — 44pt controls.
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
        // Narrow grid column (Split, small windows): the view switch folds into one
        // button so the search field keeps room for its prompt.
        ViewThatFits(in: .horizontal) {
            row(collapsedSwitch: false)
            row(collapsedSwitch: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(collapsedSwitch: Bool) -> some View {
        HStack(spacing: StelloLayout.controlBarSpacing) {
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
            CanvasModeSwitch(compactPhone: compactPhone, collapsed: collapsedSwitch)
            FloatingSearchField(text: $searchText, compactPhone: compactPhone)
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
            StelloGlassIconButton(
                systemName: "plus",
                style: .controlBar,
                isActive: isImportPanelOpen,
                controlBarDiameter: buttonSize,
                controlBarSymbolSize: symbolSize,
                label: "Add",
                action: onAdd
            )
        }
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
                    prompt: Text("Search").foregroundStyle(theme.textSecondary)
                )
                .textFieldStyle(.plain)
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, compactPhone ? 18 : 16)
        }
        .frame(height: barHeight)
        // Room for the prompt; ViewThatFits in the bar folds the view switch first.
        .frame(minWidth: 120, maxWidth: .infinity)
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
