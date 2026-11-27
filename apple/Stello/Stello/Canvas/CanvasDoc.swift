import Foundation
import CoreGraphics

/// Grid, Split (grid left, canvas right) or Canvas. Web `stello.view`.
/// Phones show Grid and Canvas only; Split falls back to Canvas there.
enum CanvasViewMode: String, CaseIterable, Identifiable, Sendable {
    case grid, split, canvas
    var id: String { rawValue }
    var label: String {
        switch self {
        case .grid: "Grid"
        case .split: "Split"
        case .canvas: "Canvas"
        }
    }
    var symbol: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .split: "rectangle.split.2x1"
        case .canvas: "point.3.connected.trianglepath.dotted"
        }
    }
}

/// A canvas doc, the same shape the web canvas and `/api/projects/:id` use
/// (`src/lib/projects.js`). World units match the web: a card is 274 wide, so a
/// card placed on the Mac sits in the same spot on the web, and back.
nonisolated struct CanvasDoc: Codable, Equatable, Sendable {
    /// 2 = starts empty, items only by drag-in (web `DOC_V`).
    static let version = 2

    struct Card: Codable, Equatable, Sendable {
        var slug: String
        var x: Double
        var y: Double
        var note: String?
        var state: String?
    }
    struct Link: Codable, Equatable, Sendable {
        var id: String
        var a: String
        var b: String
        var kind: String
        var label: String?
        var source: String?
    }
    struct Group: Codable, Equatable, Sendable {
        var id: String
        var name: String
        var slugs: [String]
    }
    struct Note: Codable, Equatable, Sendable {
        var id: String
        var kind: String
        var text: String
        var x: Double?
        var y: Double?
        var near: String?
        var slug: String?
        var rx: Double?
        var ry: Double?
        var slugs: [String]?
    }

    var v: Int? = CanvasDoc.version
    var name: String = "Library canvas"
    var groupBy: String? = "kind"
    var cards: [Card] = []
    var links: [Link] = []
    var groups: [Group] = []
    var notes: [Note] = []
    var dismissed: [String] = []

    init(name: String = "Library canvas") { self.name = name }

    // Lenient decode: the server drops unknown keys and may omit empty arrays.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decodeIfPresent(Int.self, forKey: .v)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Library canvas"
        groupBy = try c.decodeIfPresent(String.self, forKey: .groupBy)
        cards = try c.decodeIfPresent([Card].self, forKey: .cards) ?? []
        links = try c.decodeIfPresent([Link].self, forKey: .links) ?? []
        groups = try c.decodeIfPresent([Group].self, forKey: .groups) ?? []
        notes = try c.decodeIfPresent([Note].self, forKey: .notes) ?? []
        dismissed = try c.decodeIfPresent([String].self, forKey: .dismissed) ?? []
    }

    func card(_ slug: String) -> Card? { cards.first { $0.slug == slug } }
    func contains(_ slug: String) -> Bool { cards.contains { $0.slug == slug } }

    static func newID() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16))
    }
}

/// One saved canvas as `/api/projects` returns it.
nonisolated struct CanvasProject: Codable, Sendable {
    var id: String
    var name: String?
    var rev: Int
    var doc: CanvasDoc?
}

/// Web layout constants (canvas.js) so cards sit at the same world spots.
enum CanvasMetrics {
    /// Card width in world units (web `W`).
    static let cardWidth: CGFloat = 274
    /// Gap between cards placed side by side or stacked (web `F_COL` / `F_ROW`).
    static let cardGap: CGFloat = 16
    /// A drop this close to a card snaps beside it (web `SNAP_GAP`).
    static let snapGap: CGFloat = 56
    static let minZoom: CGFloat = 0.02
    static let maxZoom: CGFloat = 2.0
    /// Zoom steps for +/- (web: 2%…200%).
    static let zoomSteps: [CGFloat] = [0.02, 0.03, 0.05, 0.08, 0.125, 0.25, 0.5, 1, 2]

    /// Cover height for a card: the web's `coverRatio`, clamped 0.5…1.3.
    static func cardHeight(imageWidth: Int?, imageHeight: Int?, hasImage: Bool) -> CGFloat {
        if let w = imageWidth, let h = imageHeight, w > 0, h > 0 {
            return (cardWidth * min(1.3, max(0.5, CGFloat(h) / CGFloat(w)))).rounded()
        }
        return (cardWidth * (hasImage ? 0.6 : 0.62)).rounded()
    }
}

/// Camera: world point `p` shows at screen `p * k + (x, y)`.
struct CanvasCamera: Equatable {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var k: CGFloat = 0.5

    func toWorld(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - x) / k, y: (p.y - y) / k) }
    func toScreen(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * k + x, y: p.y * k + y) }

    /// Zoom to `newK`, keeping the world point under `anchor` (screen) still.
    mutating func zoom(to newK: CGFloat, anchor: CGPoint) {
        let k2 = min(CanvasMetrics.maxZoom, max(CanvasMetrics.minZoom, newK))
        let w = toWorld(anchor)
        k = k2
        x = anchor.x - w.x * k2
        y = anchor.y - w.y * k2
    }

    mutating func pan(by d: CGSize) { x += d.width; y += d.height }

    /// Frame `box` (world) in a viewport of `size`, with `pad` screen points around it.
    static func fit(_ box: CGRect, in size: CGSize, pad: CGFloat = 48, maxK: CGFloat = 1) -> CanvasCamera {
        guard box.width > 0, box.height > 0, size.width > 0, size.height > 0 else {
            return CanvasCamera(x: size.width / 2, y: size.height / 2, k: 0.5)
        }
        let k = min(maxK, max(CanvasMetrics.minZoom,
                              min((size.width - 2 * pad) / box.width, (size.height - 2 * pad) / box.height)))
        return CanvasCamera(x: size.width / 2 - box.midX * k, y: size.height / 2 - box.midY * k, k: k)
    }

    func nextStep(up: Bool) -> CGFloat {
        let steps = CanvasMetrics.zoomSteps
        if up { return steps.first { $0 > k + 0.001 } ?? CanvasMetrics.maxZoom }
        return steps.last { $0 < k - 0.001 } ?? CanvasMetrics.minZoom
    }
}
