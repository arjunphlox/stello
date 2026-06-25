import CoreGraphics

/// Shared layout constants — mirrors web `.content-inner` / `.header` from `style.css`.
enum StelloLayout {
    /// Web `.content-inner { padding: 24px 24px 0 }` — uniform window edge inset.
    static let windowInset: CGFloat = 24
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
    /// macOS: leading gutter inside accent header for traffic-light cluster.
    static let macTrafficLightLeadingPadding: CGFloat = 12
    /// macOS: reserved width for close + miniaturize + zoom inside the header card.
    static let macTrafficLightReservedWidth: CGFloat = 68
    /// macOS: horizontal spacing between standard window buttons.
    static let macTrafficLightSpacing: CGFloat = 20
    /// When a side panel is open, web halves the grid-column right inset (24 → 12).
    static let windowInsetPanelOpenTrailing: CGFloat = 12
}
