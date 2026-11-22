import CoreGraphics
#if os(iOS)
import UIKit
#endif

/// Shared layout constants — mirrors web `.content-inner` / `.header` from `style.css`.
enum StelloLayout {
    /// Edge gutter for the current window width — the web's `--gutter` (24 above
    /// 768pt, 16 above 500pt, 12 on phones; Arjun's pick, parity pass Nov 22 2026).
    /// `ContentView` sets it from the window width before laying anything out.
    static var gutter: CGFloat = 12
    static func gutter(forWidth width: CGFloat) -> CGFloat {
        width > 768 ? 24 : width > 500 ? 16 : 12
    }
    /// Gap between grid cards — the web's masonry gap (24 above 768pt, else 12).
    static var cardGap: CGFloat = 12
    static func cardGap(forWidth width: CGFloat) -> CGFloat { width > 768 ? 24 : 12 }
    /// Sets both for a window width; call before layout reads them.
    static func applyWidth(_ width: CGFloat) {
        let g = gutter(forWidth: width), c = cardGap(forWidth: width)
        if gutter != g { gutter = g }
        if cardGap != c { cardGap = c }
    }

    /// Window edge inset — every outer edge (header, content, panel, bottom bar).
    static var windowInset: CGFloat { gutter }
    /// Gap below the header before scroll content begins.
    static let sectionGap: CGFloat = 12
    /// Web `.header { border-radius: 12px }`.
    static let headerCornerRadius: CGFloat = 12
    static let panelCornerRadius: CGFloat = 12
    static let columnGap: CGFloat = 12
    /// Horizontal clip slack around the grid so the 4pt outset selection ring on
    /// edge cards stays visible while the cards sit flush with the header edges.
    static let gridRingClipOutset: CGFloat = 6
    /// Web `.header { min-height: 120px }` — fixed card height on native (do not grow with window).
    static let headerMinHeight: CGFloat = 120
    static let headerHeight: CGFloat = 120
    /// Web `.header { padding: 12px }` on all sides.
    static let headerPadding: CGFloat = 12
    /// Web `.header h1 { font-size: 3rem }` → 48pt.
    static let headerTitleSize: CGFloat = 48
    /// Web `.header-count { font-size: 0.85rem }` → ~13.6pt at 16px root.
    static let headerCountSize: CGFloat = 13.6
    /// Web `.header-count { padding-left: 4px }`.
    static let headerCountSpacing: CGFloat = 4
    /// Superscript lift for the item tally (web `<sup>` above cap-height).
    static let headerCountBaselineOffset: CGFloat = 14
    /// macOS: leading gutter inside accent header so wordmark clears native traffic lights.
    static let macTitleBarLeadingInset: CGFloat = 78
    /// Scroll distance (pt) over which the header transitions opaque → glass.
    static let headerScrollFadeDistance: CGFloat = 48
    /// Floating Liquid Glass control bar — search field height, glass fill, and insets.
    static let floatingSearchBarHeight: CGFloat = 40
    /// Bottom control bar icon buttons — 40×40 circles on Mac and iPad.
    static let controlBarButtonSize: CGFloat = 40
    /// iPhone: 44pt controls (the web phone bar and Apple's minimum touch target).
    static let compactControlBarHeight: CGFloat = 44
    static let compactControlBarButtonSize: CGFloat = 44
    static let compactControlBarSymbolSize: CGFloat = 18
    /// iPhone: gap between Dynamic Island / notch and the sticky header card.
    /// The top is the one edge that adds gutter + safe area (as on the web).
    static var compactHeaderBelowSafeAreaGap: CGFloat { windowInset }
    /// Reduced tint so Liquid Glass occlusion reads through the control cluster.
    static let controlBarGlassFillOpacity: CGFloat = 0.62
    static let controlBarSpacing: CGFloat = 8

    // MARK: Edge gaps (web `--gap-*`, PR #95)
    // One gap per side: the gutter, or the device's safe-area inset where that is
    // larger. Never both added together, so the bottom controls sit as far from the
    // screen edge as the header and grid sit from theirs.

    /// The gap for one edge: `max(gutter, safe-area inset)`.
    static func edgeGap(safeInset: CGFloat) -> CGFloat {
        max(windowInset, safeInset)
    }

    /// The window's real safe-area insets. Views that ignore the bottom safe area
    /// (so the grid scrolls under the home indicator) read 0 from their own
    /// GeometryProxy, which put the iPhone control bar under the screen edge.
    #if os(iOS)
    @MainActor static var windowSafeArea: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        return (windows.first(where: \.isKeyWindow) ?? windows.first)?.safeAreaInsets ?? .zero
    }
    #endif

    /// Bottom edge gap for the floating control bar and the side panel.
    @MainActor static func bottomEdgeGap(proxySafeBottom: CGFloat = 0) -> CGFloat {
        #if os(iOS)
        edgeGap(safeInset: max(proxySafeBottom, windowSafeArea.bottom))
        #else
        edgeGap(safeInset: proxySafeBottom)
        #endif
    }

    /// Control bar height for the current layout width.
    static func controlBarHeight(compactPhone: Bool) -> CGFloat {
        compactPhone ? compactControlBarHeight : floatingSearchBarHeight
    }
    static func controlBarButtonDiameter(compactPhone: Bool) -> CGFloat {
        compactPhone ? compactControlBarButtonSize : controlBarButtonSize
    }
    static func controlBarSymbolSize(compactPhone: Bool) -> CGFloat {
        compactPhone ? compactControlBarSymbolSize : iconButtonSymbolSize
    }
    /// Scroll padding so the last grid cards clear the floating control bar:
    /// bar + its edge gap + one section gap.
    static func floatingSearchScrollInset(compactPhone: Bool, bottomGap: CGFloat) -> CGFloat {
        controlBarHeight(compactPhone: compactPhone) + bottomGap + sectionGap
    }
    /// Top scroll inset when the sticky header floats over the grid on iPhone.
    static func compactHeaderScrollInset(safeTop: CGFloat) -> CGFloat {
        safeTop + compactHeaderBelowSafeAreaGap + headerHeight + sectionGap
    }
    /// Top scroll inset when the header floats over the grid (header + gap + top inset).
    static var headerOverlayScrollInset: CGFloat {
        headerHeight + sectionGap + windowInset
    }
    /// Header / toolbar icon buttons — web `.header-btn` (32×32, 8pt radius).
    static let iconButtonFootprint: CGFloat = 32
    static let iconButtonCornerRadius: CGFloat = 8
    static let iconButtonSymbolSize: CGFloat = 16
}
