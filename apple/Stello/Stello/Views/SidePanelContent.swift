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
        case .settings:   "Settings"
        }
    }

    /// Web PanelManager: 25% of viewport, clamped [360, 480].
    static func width(for viewportWidth: CGFloat) -> CGFloat {
        let raw = (viewportWidth * 0.25).rounded()
        return min(480, max(360, raw))
    }
}
