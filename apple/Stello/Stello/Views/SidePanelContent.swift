import Foundation

/// Mutually exclusive side-panel content — mirrors web `PanelManager` (`slug` OR `tool`).
enum SidePanelContent: Equatable {
    case none
    case itemDetail
    case filters
    case `import`
    case settings

    var title: String {
        switch self {
        case .none:       "Panel"
        case .itemDetail: "Detail"
        case .filters:    "Filters"
        case .import:     "Import"
        case .settings:   "User Preferences"
        }
    }

    /// Panel width as a fraction of viewport, clamped 25%–50%.
    static func width(for viewportWidth: CGFloat, fraction: Double) -> CGFloat {
        let clamped = min(0.5, max(0.25, fraction))
        return (viewportWidth * clamped).rounded()
    }
}
