import SwiftUI

/// Accent header — Stello wordmark, item tally, and icon buttons (Filters / Add / Settings).
/// macOS: inset rounded card confined to the content column; native traffic lights sit in the
/// card's top-left (positioned by `MacWindowConfigurator`). Scroll progress drives glass intensity.
struct StelloHeaderView: View {
    let itemCount: Int
    var hasActiveFilters: Bool = false
    var activePanel: SidePanelContent = .none
    /// True on macOS; traffic lights sit top-left (via `MacWindowConfigurator`) so the
    /// bottom-left title needs no extra gutter and keeps the uniform 12pt header padding.
    var integratesMacTitleBar: Bool = false
    /// 0 = at scroll top; 1 = scrolled (more translucent glass).
    var scrollProgress: CGFloat = 0
    var onFilters: () -> Void
    var onImport: () -> Void
    var onSettings: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var isCompact: Bool { hSizeClass == .compact }
    private var buttonClusterSpacing: CGFloat { isCompact ? 6 : 8 }
    private var clampedScroll: CGFloat { min(max(scrollProgress, 0), 1) }

    private var screenshotHoverFilters: Bool {
        ProcessInfo.processInfo.arguments.contains("-screenshotHeaderHover")
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: isCompact ? 8 : 12) {
                wordmark
                    .allowsHitTesting(false)

                Spacer(minLength: isCompact ? 4 : 8)
                    .allowsHitTesting(false)

                buttonCluster
                    .layoutPriority(0)
            }
        }
        .padding(.leading, StelloLayout.headerPadding)
        .padding(.trailing, StelloLayout.headerPadding)
        .padding(.bottom, StelloLayout.headerPadding)
        .frame(height: StelloLayout.headerHeight)
        .frame(maxWidth: .infinity)
        .background { headerBackground }
        .clipShape(RoundedRectangle(cornerRadius: StelloLayout.headerCornerRadius, style: .continuous))
    }

    private var buttonCluster: some View {
        HStack(spacing: buttonClusterSpacing) {
            StelloGlassIconButton(
                systemName: "line.3.horizontal.decrease",
                isActive: activePanel == .filters || hasActiveFilters,
                contrastForeground: true,
                forceHover: screenshotHoverFilters,
                label: "Filters",
                action: onFilters
            )
            StelloGlassIconButton(
                systemName: "plus",
                isActive: activePanel == .import,
                contrastForeground: true,
                label: "Import",
                action: onImport
            )
            StelloGlassIconButton(
                systemName: "gearshape",
                isActive: activePanel == .settings,
                contrastForeground: true,
                label: "Settings",
                action: onSettings
            )
        }
    }

    @ViewBuilder
    private var headerBackground: some View {
        let shape = RoundedRectangle(cornerRadius: StelloLayout.headerCornerRadius, style: .continuous)
        let baseOpacity = 0.82 - (0.18 * clampedScroll)
        let tintOpacity = 0.42 + (0.18 * clampedScroll)
        shape
            .fill(theme.accentColor.opacity(baseOpacity))
            .glassEffect(.regular.tint(theme.accentColor.opacity(tintOpacity)), in: shape)
    }

    private var wordmark: some View {
        HStack(alignment: .firstTextBaseline, spacing: StelloLayout.headerCountSpacing) {
            Text("Stello")
                .font(.system(size: isCompact ? 42 : StelloLayout.headerTitleSize, weight: .regular))
                .tracking(isCompact ? -1.26 : -1.44)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if itemCount > 0 {
                Text("\(itemCount)")
                    .font(.system(size: StelloLayout.headerCountSize, weight: .regular))
                    .foregroundStyle(theme.accentContrast.opacity(0.55))
                    .baselineOffset(StelloLayout.headerCountBaselineOffset)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .foregroundStyle(theme.accentContrast)
        .layoutPriority(1)
    }
}

#Preview {
    StelloHeaderView(
        itemCount: 19,
        hasActiveFilters: true,
        activePanel: .filters,
        integratesMacTitleBar: true,
        onFilters: {},
        onImport: {},
        onSettings: {}
    )
    .padding(StelloLayout.windowInset)
    .background(Color(hex: "#111110"))
    .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
}

#Preview("iPhone compact") {
    StelloHeaderView(
        itemCount: 19,
        hasActiveFilters: false,
        onFilters: {},
        onImport: {},
        onSettings: {}
    )
    .padding(StelloLayout.windowInset)
    .background(Color(hex: "#111110"))
    .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
    .environment(\.horizontalSizeClass, .compact)
    .frame(width: 393)
}
