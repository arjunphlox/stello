import SwiftUI

/// Accent header — Stello wordmark and item tally only.
/// macOS: inset rounded card confined to the content column; native traffic lights sit in the
/// card's top-left (positioned by `MacWindowConfigurator`). Scroll progress drives glass intensity.
struct StelloHeaderView: View {
    let itemCount: Int
    /// True on macOS; traffic lights sit top-left (via `MacWindowConfigurator`) so the
    /// bottom-left title needs no extra gutter and keeps the uniform 12pt header padding.
    var integratesMacTitleBar: Bool = false
    /// 0 = at scroll top; 1 = scrolled (more translucent glass).
    var scrollProgress: CGFloat = 0
    /// True while a file drag hovers over the window drop target.
    var isDropTargeted: Bool = false

    @Environment(\.appTheme) private var theme
    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var isCompact: Bool { hSizeClass == .compact }
    private var clampedScroll: CGFloat { min(max(scrollProgress, 0), 1) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            wordmarkGroup
                .alignmentGuide(.bottom) { $0[.lastTextBaseline] }
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
        }
        .padding(.leading, StelloLayout.headerPadding)
        .padding(.trailing, StelloLayout.headerPadding)
        .padding(.bottom, StelloLayout.headerPadding)
        .frame(height: StelloLayout.headerHeight)
        .frame(maxWidth: .infinity)
        .background { headerBackground }
        .clipShape(RoundedRectangle(cornerRadius: StelloLayout.headerCornerRadius, style: .continuous))
        .animation(.smooth(duration: 0.25), value: isDropTargeted)
    }

    @ViewBuilder
    private var headerBackground: some View {
        let shape = RoundedRectangle(cornerRadius: StelloLayout.headerCornerRadius, style: .continuous)
        if isDropTargeted {
            shape
                .fill(theme.accentColor.opacity(0.35))
                .overlay {
                    shape
                        .strokeBorder(
                            theme.accentContrast,
                            style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                        )
                }
                .glassEffect(.regular.tint(theme.accentColor.opacity(0.25)), in: shape)
        } else {
            let baseOpacity = 0.82 - (0.18 * clampedScroll)
            let tintOpacity = 0.42 + (0.18 * clampedScroll)
            shape
                .fill(theme.accentColor.opacity(baseOpacity))
                .glassEffect(.regular.tint(theme.accentColor.opacity(tintOpacity)), in: shape)
        }
    }

    private var wordmarkTitleSize: CGFloat { isCompact ? 42 : StelloLayout.headerTitleSize }

    @ViewBuilder
    private var wordmarkGroup: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if isDropTargeted {
                Text("Drop to capture and save")
                    .font(.karst(size: isCompact ? 22 : 26, weight: .medium))
                    .tracking(isCompact ? -0.6 : -0.72)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(theme.accentContrast)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                Text("Stello")
                    .font(.karst(size: wordmarkTitleSize, weight: .regular))
                    .tracking(isCompact ? -1.26 : -1.44)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(theme.accentContrast)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))

                if itemCount > 0 {
                    Text("\(itemCount)")
                        .font(.karst(size: StelloLayout.headerCountSize, weight: .regular))
                        .foregroundStyle(theme.accentContrast.opacity(0.55))
                        .baselineOffset(StelloLayout.headerCountBaselineOffset)
                        .padding(.leading, StelloLayout.headerCountSpacing)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
    }
}

#Preview("Drop targeted") {
    StelloHeaderView(
        itemCount: 19,
        integratesMacTitleBar: true,
        isDropTargeted: true
    )
    .padding(StelloLayout.windowInset)
    .background(Color(hex: "#111110"))
    .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
}

#Preview("iPhone compact") {
    StelloHeaderView(itemCount: 19)
        .padding(StelloLayout.windowInset)
        .background(Color(hex: "#111110"))
        .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
        .environment(\.horizontalSizeClass, .compact)
        .frame(width: 393)
}
