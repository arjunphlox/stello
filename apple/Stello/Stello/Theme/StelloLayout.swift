import CoreGraphics

/// Shared layout constants — mirrors web `.content-inner` / `.header` from `style.css`.
enum StelloLayout {
    /// Uniform inset — every edge and every gap (header, content, panel, column).
    static let windowInset: CGFloat = 12
    /// Gap below the header before scroll content begins.
    static let sectionGap: CGFloat = 12
    /// Web `.header { border-radius: 12px }`.
    static let headerCornerRadius: CGFloat = 12
    static let panelCornerRadius: CGFloat = 12
    static let columnGap: CGFloat = 12
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
    /// Floating Liquid Glass search bar — height, bottom margin, and scroll content inset.
    static let floatingSearchBarHeight: CGFloat = 48
    static let floatingSearchBarBottomMargin: CGFloat = 12
    static let floatingSearchBarMaxWidth: CGFloat = 420
    /// Scroll padding so last grid cards clear the floating search overlay.
    static var floatingSearchScrollInset: CGFloat {
        floatingSearchBarHeight + floatingSearchBarBottomMargin
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
