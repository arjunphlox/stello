import CoreGraphics

/// Shared layout constants — window inset matches web `.main-content` padding rhythm.
enum StelloLayout {
    static let windowInset: CGFloat = 12
    static let headerCornerRadius: CGFloat = 12
    static let panelCornerRadius: CGFloat = 12
    static let columnGap: CGFloat = 12
    /// macOS header band height (traffic-light vertical center target).
    static let macHeaderHeight: CGFloat = 80
    /// Leading space inside the accent header card for traffic lights + wordmark breathing room.
    static let macTrafficLightLeadingPadding: CGFloat = 12
}
