import SwiftUI

/// Accent-colored header mirroring the web app's `.header` — Stello wordmark, item tally,
/// and action buttons (Filters → Import → Settings) with Liquid Glass icon buttons.
struct StelloHeaderView: View {
    let itemCount: Int
    var hasActiveFilters: Bool = false
    var activePanel: SidePanelContent = .none
    /// When true (macOS), reserve leading inset for traffic lights and extend to window top.
    var integratesMacTitleBar: Bool = false
    var onFilters: () -> Void
    var onImport: () -> Void
    var onSettings: () -> Void

    @Environment(\.appTheme) private var theme

    private var macLeadingInset: CGFloat { integratesMacTitleBar ? 78 : 0 }
    /// Top inset: traffic-light vertical center + breathing room for wordmark baseline alignment.
    private var topPadding: CGFloat { integratesMacTitleBar ? 8 : 12 }

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
        .padding(.leading, 12 + macLeadingInset)
        .padding(.trailing, 12)
        .padding(.bottom, 12)
        .padding(.top, topPadding)
        .frame(minHeight: integratesMacTitleBar ? 80 : 72, alignment: .bottom)
        .frame(maxWidth: .infinity)
        .background(theme.accentColor)
        .modifier(HeaderClipShape(integratesMacTitleBar: integratesMacTitleBar))
        #if os(macOS)
        .background(theme.accentColor.ignoresSafeArea(edges: .top))
        #endif
    }
}

private struct HeaderClipShape: ViewModifier {
    let integratesMacTitleBar: Bool

    func body(content: Content) -> some View {
        if integratesMacTitleBar {
            content.clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 12,
                    bottomTrailingRadius: 12,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )
        } else {
            content.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
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
                .frame(width: 32, height: 32)
                .foregroundStyle(theme.accentContrast.opacity(isActive ? 1 : 0.82))
        }
        .buttonStyle(.glass)
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
    .padding()
    .background(Color(hex: "#111110"))
    .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
}
