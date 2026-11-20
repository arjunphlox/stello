import Foundation
import CoreGraphics
import Observation

/// The open canvas: a local copy on disk plus the shared copy on the Worker
/// (`/api/projects/:id`), the same doc the web canvas edits. Saves are whole-doc
/// with a rev check, 1.2 s after the last change (as on the web); a stale rev
/// adopts the server copy. Offline or signed out, the local copy keeps working
/// and is pushed on the next change once signed in.
@Observable
@MainActor
final class CanvasStore {
    static let shared = CanvasStore()

    private(set) var currentID: String
    private(set) var doc = CanvasDoc()
    private(set) var rev = 0
    /// Set when another device's copy replaced ours; the view shows it once.
    var notice: String?

    /// Grid, Split or Canvas (web `stello.view`). Phones treat Split as Canvas.
    var viewMode: CanvasViewMode {
        didSet {
            // Screenshot runs share the real app's settings; they must not change them.
            guard !currentID.hasPrefix("local-screenshot") else { return }
            UserDefaults.standard.set(viewMode.rawValue, forKey: Self.viewKey)
        }
    }
    /// The canvas camera. Only the canvas and its zoom pill read it.
    var camera = CanvasCamera()
    /// The camera has been placed for the current canvas (fit once on first show).
    var cameraPlaced = false
    /// You panned or zoomed; until then a resize refits the canvas.
    @ObservationIgnored var cameraMoved = false
    /// Card to frame and select the next time the canvas shows ("Show on Canvas").
    var focusSlug: String?
    /// Selected card on the canvas.
    var selected: String?
    /// Visible canvas size, so menu actions can drop at the centre of the view.
    @ObservationIgnored var viewportSize: CGSize = .zero

    @ObservationIgnored private var undoStack: [CanvasDoc] = []
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var pushing = false

    private static let currentKey = "stello.canvas.current"
    private static let viewKey = "stello.view"
    static let libraryID = "library"

    private init() {
        currentID = UserDefaults.standard.string(forKey: Self.currentKey) ?? Self.libraryID
        // Screenshot / demo runs use a throwaway local canvas: never the real doc,
        // never pushed to the server.
        if ProcessInfo.processInfo.arguments.contains("-screenshotCleanStore") {
            currentID = "local-screenshot"
        }
        viewMode = UserDefaults.standard.string(forKey: Self.viewKey)
            .flatMap(CanvasViewMode.init(rawValue:)) ?? .grid
        if currentID == "local-screenshot" { try? FileManager.default.removeItem(at: localURL) }
        loadLocal()
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var slugs: Set<String> { Set(doc.cards.map(\.slug)) }

    // MARK: - Local copy

    private static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appending(path: "Canvas", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private struct Local: Codable { var rev: Int; var doc: CanvasDoc }

    private var localURL: URL {
        let safe = currentID.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return Self.folder.appending(path: "\(safe.isEmpty ? Self.libraryID : safe).json")
    }

    private func loadLocal() {
        if let data = try? Data(contentsOf: localURL),
           let local = try? JSONDecoder().decode(Local.self, from: data) {
            doc = local.doc
            rev = local.rev
        } else {
            doc = CanvasDoc()
            rev = 0
        }
    }

    private func saveLocal() {
        guard let data = try? JSONEncoder().encode(Local(rev: rev, doc: doc)) else { return }
        try? data.write(to: localURL, options: .atomic)
    }

    // MARK: - Server copy

    /// Fetch the server copy. Newer and no local edits pending: adopt it.
    /// Ours is newer or the server is empty: push ours.
    func pull() async {
        guard !currentID.hasPrefix("local-"), let api = CanvasAPI.current else { return }
        do {
            let project = try await api.get(currentID)
            if project.rev > rev && !dirty {
                adopt(project)
            } else if project.rev == rev, project.doc?.v != CanvasDoc.version {
                adopt(project)
            } else if project.rev < rev || (project.rev == 0 && !doc.cards.isEmpty) {
                rev = project.rev
                queuePush()
            }
        } catch {
            // Offline or not found: keep the local copy.
        }
    }

    private func adopt(_ project: CanvasProject) {
        rev = project.rev
        var next = project.doc ?? CanvasDoc()
        // Library docs older than v2 were auto-filled with the whole library; the
        // web clears them once (cards, groups, free notes) and writes back.
        if next.v != CanvasDoc.version {
            next.v = CanvasDoc.version
            if currentID == Self.libraryID {
                next.cards = []; next.groups = []; next.notes = []
                queuePush()
            }
        }
        doc = next
        saveLocal()
    }

    private func queuePush() {
        guard CanvasAPI.current != nil, !currentID.hasPrefix("local-") else { return }
        dirty = true
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            await self?.push()
        }
    }

    private func push() async {
        guard !currentID.hasPrefix("local-"), let api = CanvasAPI.current else { return }
        if pushing { queuePush(); return }
        pushing = true
        dirty = false
        defer { pushing = false }
        var out = doc
        out.v = CanvasDoc.version
        for i in out.links.indices where out.links[i].source == nil { out.links[i].source = "mac" }
        do {
            switch try await api.save(currentID, doc: out, rev: rev) {
            case .saved(let project):
                rev = project.rev
                saveLocal()
            case .conflict(let project):
                adopt(project)
                notice = "Canvas changed on another device; showing the latest copy"
            }
        } catch {
            dirty = true
        }
    }

    // MARK: - Edits

    /// Every edit goes through here: one undo step, saved locally, pushed soon.
    func change(_ edit: (inout CanvasDoc) -> Void) {
        let before = doc
        edit(&doc)
        guard doc != before else { return }
        undoStack.append(before)
        if undoStack.count > 50 { undoStack.removeFirst() }
        saveLocal()
        queuePush()
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        doc = prev
        saveLocal()
        queuePush()
    }

    /// Drop items at world point `at`. Dropped on or right next to a card, they
    /// line up beside it; otherwise they land centred on the drop point. Nothing
    /// already on the canvas moves (web `addToCanvas`).
    @discardableResult
    func add(_ slugs: [String], at: CGPoint, height: (String) -> CGFloat) -> [String] {
        let fresh = slugs.reduce(into: [String]()) { out, s in
            if !doc.contains(s) && !out.contains(s) { out.append(s) }
        }
        guard !fresh.isEmpty else { return [] }
        let w = CanvasMetrics.cardWidth, gap = CanvasMetrics.cardGap
        change { d in
            let near = Self.nearest(in: d, to: at, within: CanvasMetrics.snapGap, height: height)
            var y: CGFloat?
            for slug in fresh {
                let h = height(slug)
                let x: CGFloat
                if let near {
                    x = at.x > near.x + w / 2 ? near.x + w + gap : near.x - w - gap
                    if y == nil { y = near.y }
                } else {
                    x = (at.x - w / 2).rounded()
                    if y == nil { y = (at.y - h / 2).rounded() }
                }
                let spot = Self.freeSpot(in: d, x: x, y: y ?? 0, h: h, height: height)
                d.cards.append(.init(slug: slug, x: Double(spot.x), y: Double(spot.y)))
                y = spot.y + h + gap
            }
        }
        return fresh
    }

    func move(_ slug: String, to p: CGPoint) {
        change { d in
            guard let i = d.cards.firstIndex(where: { $0.slug == slug }) else { return }
            d.cards[i].x = Double(p.x.rounded())
            d.cards[i].y = Double(p.y.rounded())
        }
    }

    func remove(_ slugs: Set<String>) {
        change { d in
            d.cards.removeAll { slugs.contains($0.slug) }
            for i in d.groups.indices { d.groups[i].slugs.removeAll { slugs.contains($0) } }
            d.groups.removeAll { $0.slugs.count < 2 }
        }
    }

    /// World point at the centre of what the canvas shows now.
    var viewCenter: CGPoint {
        let size = viewportSize == .zero ? CGSize(width: 800, height: 600) : viewportSize
        return camera.toWorld(CGPoint(x: size.width / 2, y: size.height / 2))
    }

    /// Card menu "Add to Canvas": drop at the centre of the view, then show it.
    func addFromMenu(_ slug: String, height: CGFloat) {
        add([slug], at: viewCenter, height: { _ in height })
        showOnCanvas(slug)
    }

    /// Card menu "Show on Canvas": switch to the canvas (Split keeps the grid)
    /// and frame the card.
    func showOnCanvas(_ slug: String) {
        focusSlug = slug
        if viewMode == .grid { viewMode = .canvas }
    }

    /// World bounds of everything on the canvas.
    func bounds(height: (String) -> CGFloat) -> CGRect? {
        guard !doc.cards.isEmpty else { return nil }
        return doc.cards.reduce(CGRect.null) { box, c in
            box.union(CGRect(x: c.x, y: c.y, width: CanvasMetrics.cardWidth, height: height(c.slug)))
        }
    }

    // MARK: - Placement helpers

    private struct Near { let x: CGFloat; let y: CGFloat }

    private static func nearest(in d: CanvasDoc, to p: CGPoint, within gap: CGFloat,
                                height: (String) -> CGFloat) -> Near? {
        var best: (Near, CGFloat)?
        for c in d.cards {
            let x = CGFloat(c.x), y = CGFloat(c.y), h = height(c.slug)
            let dx = max(0, x - p.x, p.x - (x + CanvasMetrics.cardWidth))
            let dy = max(0, y - p.y, p.y - (y + h))
            let dist = hypot(dx, dy)
            if dist <= gap, best == nil || dist < best!.1 { best = (Near(x: x, y: y), dist) }
        }
        return best?.0
    }

    /// Step down past any card in the way (web `freeSpot`).
    private static func freeSpot(in d: CanvasDoc, x: CGFloat, y: CGFloat, h: CGFloat,
                                 height: (String) -> CGFloat) -> CGPoint {
        var y = y
        let w = CanvasMetrics.cardWidth
        for _ in 0..<40 {
            let probe = CGRect(x: x - 10, y: y - 10, width: w + 20, height: h + 20)
            let hits = d.cards.filter {
                probe.intersects(CGRect(x: $0.x, y: $0.y, width: w, height: height($0.slug)))
            }
            guard !hits.isEmpty else { return CGPoint(x: x, y: y) }
            y = hits.map { CGFloat($0.y) + height($0.slug) }.max()! + CanvasMetrics.cardGap
        }
        return CGPoint(x: x, y: y)
    }
}
