import SwiftUI

/// Accent-colored header mirroring the web app's `.header` — Stello wordmark, item tally,
/// and pill-shaped Liquid Glass icon buttons (Filters → Import → Settings).
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

    private var macLeadingInset: CGFloat {
        integratesMacTitleBar ? 78 : 0
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Stello")
                    .font(.system(size: 48, weight: .regular))
                    .tracking(-1.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if itemCount > 0 {
                    Text("\(itemCount)")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(theme.accentContrast.opacity(0.55))
                }
            }
            .foregroundStyle(theme.accentContrast)

            Spacer(minLength: 8)

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    glassHeaderButton(
                        systemName: hasActiveFilters || activePanel == .filters
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease",
                        isActive: activePanel == .filters,
                        label: "Filters",
                        action: onFilters
                    )
                    glassHeaderButton(
                        systemName: "plus",
                        isActive: activePanel == .import,
                        label: "Import",
                        action: onImport
                    )
                    glassHeaderButton(
                        systemName: "gear",
                        isActive: activePanel == .settings,
                        label: "Settings",
                        action: onSettings
                    )
                }
            }
        }
        .padding(.leading, StelloLayout.windowInset + macLeadingInset)
        .padding(.trailing, StelloLayout.windowInset)
        .padding(.bottom, StelloLayout.windowInset)
        .padding(.top, StelloLayout.windowInset)
        .frame(minHeight: integratesMacTitleBar ? StelloLayout.macHeaderHeight : 72, alignment: .bottom)
        .frame(maxWidth: .infinity)
        .background(theme.accentColor)
        .clipShape(RoundedRectangle(cornerRadius: StelloLayout.headerCornerRadius, style: .continuous))
    }
}

extension StelloHeaderView {
    private func glassHeaderButton(
        systemName: String,
        isActive: Bool,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 36, height: 28)
                .foregroundStyle(theme.accentContrast.opacity(isActive ? 1 : 0.82))
        }
        .buttonStyle(.glass)
        .clipShape(Capsule())
        .accessibilityLabel(label)
        .help(label)
    }
}

#Preview {
    StelloHeaderView(
        itemCount: 19,
        hasActiveFilters: true,
        activePanel: .filters,
        onFilters: {},
        onImport: {},
        onSettings: {}
    )
    .padding(StelloLayout.windowInset)
    .background(Color(hex: "#111110"))
    .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
}
