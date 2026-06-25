import SwiftUI

/// Accent-tinted floating Liquid Glass header — Stello wordmark, item tally,
/// and pill-shaped icon buttons (Filters → Import → Settings).
struct StelloHeaderView: View {
    let itemCount: Int
    var hasActiveFilters: Bool = false
    var activePanel: SidePanelContent = .none
    /// When true (macOS), reserve leading inset for traffic lights inside the header card.
    var integratesMacTitleBar: Bool = false
    var onFilters: () -> Void
    var onImport: () -> Void
    var onSettings: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var isCompact: Bool { hSizeClass == .compact }
    private var buttonClusterSpacing: CGFloat { isCompact ? 6 : 8 }

    var body: some View {
        ZStack(alignment: .bottom) {
            if integratesMacTitleBar {
                #if os(macOS)
                HStack(spacing: 0) {
                    MacTrafficLightCluster()
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)
                }
                .padding(StelloLayout.headerPadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                #endif
            }

            HStack(alignment: .bottom, spacing: isCompact ? 8 : 12) {
                wordmark
                    .allowsHitTesting(false)

                Spacer(minLength: isCompact ? 4 : 8)
                    .allowsHitTesting(false)

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
                .layoutPriority(0)
            }
            .padding(StelloLayout.headerPadding)
        }
        .frame(height: StelloLayout.headerHeight)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: StelloLayout.headerCornerRadius, style: .continuous)
                .fill(theme.accentColor.opacity(0.55))
        }
        .glassEffect(.regular.tint(theme.accentColor.opacity(0.45)), in: .rect(cornerRadius: StelloLayout.headerCornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: StelloLayout.headerCornerRadius, style: .continuous))
    }

    private var wordmark: some View {
        HStack(alignment: .firstTextBaseline, spacing: StelloLayout.headerCountSpacing) {
            Text("Stello")
                .font(.system(size: isCompact ? 42 : StelloLayout.headerTitleSize, weight: .regular))
                .tracking(isCompact ? -1.26 : -1.44) // web letter-spacing: -0.03em
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
