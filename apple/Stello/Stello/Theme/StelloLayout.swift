import CoreGraphics

/// Shared layout constants — mirrors web `.content-inner` / `.header` from `style.css`.
enum StelloLayout {
    /// Uniform side inset — leading, trailing, panel vertical (no bottom; content bleeds to window edge).
    static let windowInset: CGFloat = 12
    /// macOS: gap above the inset header card inside the transparent title-bar container.
    /// 8pt (not 12pt) keeps native traffic lights (~14pt from window top) on the card body
    /// without straddling the top edge; sides stay 12pt.
    static let macHeaderCardTopInset: CGFloat = 8
    /// macOS: horizontal inset for the floating header card (matches content column).
    static let macHeaderCardSideInset: CGFloat = windowInset
    /// Web `.content-inner { gap: 16px }` between header, search, and grid.
    static let sectionGap: CGFloat = 16
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
    /// Top scroll inset when the header floats over the grid (header + gap + mac card top inset).
    static var headerOverlayScrollInset: CGFloat {
        headerHeight + sectionGap + macHeaderCardTopInset
    }
    /// Header / toolbar icon buttons — fixed capsule footprint + symbol metrics.
    static let iconButtonFootprint: CGFloat = 36
    static let iconButtonSymbolSize: CGFloat = 16
}
