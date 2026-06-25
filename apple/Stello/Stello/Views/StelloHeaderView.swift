import SwiftUI

/// Accent header — Stello wordmark, item tally, and icon buttons (Filters / Add / Settings).
/// macOS: extends to the window top so native traffic lights sit on the accent color;
/// scroll progress drives opaque → glass transition.
struct StelloHeaderView: View {
    let itemCount: Int
    var hasActiveFilters: Bool = false
    var activePanel: SidePanelContent = .none
    /// When true (macOS), reserve leading inset for native traffic lights and square the top edge.
    var integratesMacTitleBar: Bool = false
    /// 0 = at scroll top (fully opaque accent); 1 = scrolled (accent-tinted glass).
    var scrollProgress: CGFloat = 0
    var onFilters: () -> Void
    var onImport: () -> Void
    var onSettings: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var isCompact: Bool { hSizeClass == .compact }
    private var buttonClusterSpacing: CGFloat { isCompact ? 6 : 8 }
    private var macLeadingInset: CGFloat { integratesMacTitleBar ? StelloLayout.macTitleBarLeadingInset : 0 }
    private var clampedScroll: CGFloat { min(max(scrollProgress, 0), 1) }

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: isCompact ? 8 : 12) {
                wordmark
                    .allowsHitTesting(false)

                Spacer(minLength: isCompact ? 4 : 8)
                    .allowsHitTesting(false)

                buttonCluster
                    .layoutPriority(0)
            }
            .padding(.leading, StelloLayout.headerPadding + macLeadingInset)
            .padding(.trailing, StelloLayout.headerPadding)
            .padding(.bottom, StelloLayout.headerPadding)
            .padding(.top, integratesMacTitleBar ? StelloLayout.macHeaderTopPadding : StelloLayout.headerPadding)
        }
        .frame(height: StelloLayout.headerHeight)
        .frame(maxWidth: .infinity)
        .background { headerBackground }
        .modifier(HeaderClipShape(integratesMacTitleBar: integratesMacTitleBar))
        #if os(macOS)
        .background {
            if integratesMacTitleBar {
                theme.accentColor
                    .opacity(1 - clampedScroll * 0.55)
                    .ignoresSafeArea(edges: .top)
            }
        }
        #endif
    }

    private var buttonCluster: some View {
        GlassEffectContainer(spacing: buttonClusterSpacing) {
            HStack(spacing: buttonClusterSpacing) {
                StelloGlassIconButton(
                    systemName: hasActiveFilters || activePanel == .filters
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease",
                    isActive: activePanel == .filters,
                    label: "Filters",
                    action: onFilters
                )
                StelloGlassIconButton(
                    systemName: "plus",
                    isActive: activePanel == .import,
                    label: "Import",
                    action: onImport
                )
                StelloGlassIconButton(
                    systemName: "gearshape",
                    isActive: activePanel == .settings,
                    label: "Settings",
                    action: onSettings
                )
            }
        }
    }

    @ViewBuilder
    private var headerBackground: some View {
        if integratesMacTitleBar {
            accentHeaderBackground
        } else {
            RoundedRectangle(cornerRadius: StelloLayout.headerCornerRadius, style: .continuous)
                .fill(theme.accentColor.opacity(1 - clampedScroll * 0.35))
                .glassEffect(
                    .regular.tint(theme.accentColor.opacity(0.45 * clampedScroll)),
                    in: .rect(cornerRadius: StelloLayout.headerCornerRadius)
                )
        }
    }

    @ViewBuilder
    private var accentHeaderBackground: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: StelloLayout.headerCornerRadius,
            bottomTrailingRadius: StelloLayout.headerCornerRadius,
            topTrailingRadius: 0,
            style: .continuous
        )
        if clampedScroll < 0.01 {
            shape.fill(theme.accentColor)
        } else {
            shape
                .fill(theme.accentColor.opacity(0.72))
                .glassEffect(.regular.tint(theme.accentColor.opacity(0.55)), in: shape)
        }
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

// MARK: - Clip shape

private struct HeaderClipShape: ViewModifier {
    let integratesMacTitleBar: Bool

    func body(content: Content) -> some View {
        if integratesMacTitleBar {
            content.clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: StelloLayout.headerCornerRadius,
                    bottomTrailingRadius: StelloLayout.headerCornerRadius,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )
        } else {
            content.clipShape(RoundedRectangle(cornerRadius: StelloLayout.headerCornerRadius, style: .continuous))
        }
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
