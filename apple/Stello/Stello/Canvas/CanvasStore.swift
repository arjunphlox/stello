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
    /// Selected card (or note id) on the canvas.
    var selected: String?
    /// Picking a link's second end or a region note's spot (Layer 2).
    var pick: CanvasPick?
    /// Canvases for the doc menu: this account's, plus device-only ones.
    private(set) var canvases: [CanvasListEntry] = []
    /// Bumped by the export button; the canvas view builds the Package and saves it.
    var exportRequest = 0
    /// Bumped by the zoom pill's Fit; the canvas view frames every card.
    var fitRequest = 0
    /// What the canvas draws: the Similarity and "Intent, time & gaps" menus (web
    /// `layers`). Kept on this device, as the web keeps it in the browser.
    var layers: CanvasLayers = .load() {
        didSet {
            guard !isShot, layers != oldValue else { return }
            layers.save()
        }
    }
    /// Visible canvas size, so menu actions can drop at the centre of the view.
    @ObservationIgnored var viewportSize: CGSize = .zero

    @ObservationIgnored private var undoStack: [CanvasDoc] = []
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var pushing = false

    private let isShot: Bool

    private static let currentKey = "stello.canvas.current"
    private static let listKey = "stello.canvas.list"
    /// Not "stello.view": an early test run left a stale value under that name in
    /// the real app's settings, so the shipped key starts clean.
    private static let viewKey = "stello.viewMode"
    static let libraryID = "library"

    private init() {
        // Screenshot / demo runs use a throwaway local canvas: never the real doc,
        // never pushed to the server, and they start in Grid.
        let isShot = ProcessInfo.processInfo.arguments.contains("-screenshotCleanStore")
        self.isShot = isShot
        currentID = isShot ? "local-screenshot"
            : UserDefaults.standard.string(forKey: Self.currentKey) ?? Self.libraryID
        viewMode = isShot ? .grid
            : UserDefaults.standard.string(forKey: Self.viewKey).flatMap(CanvasViewMode.init(rawValue:)) ?? .grid
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

    private var localURL: URL { Self.localURL(for: currentID) }

    private static func localURL(for id: String) -> URL {
        let safe = id.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return folder.appending(path: "\(safe.isEmpty ? libraryID : safe).json")
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

    /// Move a card and settle its group in the same undo step (web `acceptSuggest` /
    /// `refamily`). With `join`, it joins that group or starts one with `join.members`;
    /// with `leave`, it leaves the group it was in. Groups under two cards go away.
    func move(_ slug: String, to p: CGPoint, join: CanvasGroupSuggestion?, leave: Bool) {
        change { d in
            guard let i = d.cards.firstIndex(where: { $0.slug == slug }) else { return }
            d.cards[i].x = Double(p.x.rounded())
            d.cards[i].y = Double(p.y.rounded())
            if let join {
                for g in d.groups.indices where d.groups[g].id != join.groupID {
                    d.groups[g].slugs.removeAll { $0 == slug }
                }
                if let id = join.groupID, let g = d.groups.firstIndex(where: { $0.id == id }) {
                    if !d.groups[g].slugs.contains(slug) { d.groups[g].slugs.append(slug) }
                } else {
                    // A new group takes its members out of any group they were in.
                    let members = join.members.filter { $0 != slug } + [slug]
                    for g in d.groups.indices { d.groups[g].slugs.removeAll { members.contains($0) } }
                    d.groups.append(.init(id: CanvasDoc.newID(), name: join.name, slugs: members))
                }
            } else if leave {
                for g in d.groups.indices { d.groups[g].slugs.removeAll { $0 == slug } }
            }
            d.groups.removeAll { $0.slugs.count < 2 }
        }
    }

    /// Take a card out of your group, leaving it where it is.
    func leaveGroup(_ slug: String) {
        change { d in
            for g in d.groups.indices { d.groups[g].slugs.removeAll { $0 == slug } }
            d.groups.removeAll { $0.slugs.count < 2 }
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

    // MARK: - Layer 2: marks, links, notes

    /// Use / Rejected; picking the same mark again clears it and its reason.
    func setMark(_ slug: String, _ mark: CanvasMark) {
        change { d in
            guard let i = d.cards.firstIndex(where: { $0.slug == slug }) else { return }
            if d.cards[i].state == mark.rawValue {
                d.cards[i].state = nil
                d.cards[i].note = nil
            } else {
                d.cards[i].state = mark.rawValue
            }
        }
    }

    func setReason(_ slug: String, _ reason: String) {
        let r = String(reason.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        change { d in
            guard let i = d.cards.firstIndex(where: { $0.slug == slug }) else { return }
            d.cards[i].note = r.isEmpty ? nil : r
        }
    }

    /// A link between two cards or notes; an existing one of the same kind is reused.
    @discardableResult
    func addLink(_ a: String, _ b: String, kind: L2Kind, label: String? = nil, source: String = "mac") -> String? {
        guard a != b else { return nil }
        if let dup = doc.links.first(where: {
            $0.kind == kind.rawValue && (($0.a == a && $0.b == b) || ($0.a == b && $0.b == a))
        }) { return dup.id }
        let id = CanvasDoc.newID()
        change { $0.links.append(.init(id: id, a: a, b: b, kind: kind.rawValue, label: label, source: source)) }
        return id
    }

    /// "Not related" on a group's "+ Maybe" pill: never offer that save again here.
    func dismissMaybe(_ slug: String) {
        guard !doc.dismissed.contains(slug) else { return }
        change { $0.dismissed.append(slug) }
    }

    func setLinkLabel(_ id: String, _ label: String) {
        let l = String(label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(50))
        change { d in
            guard let i = d.links.firstIndex(where: { $0.id == id }) else { return }
            d.links[i].label = l.isEmpty ? nil : l
        }
    }

    func removeLink(_ id: String) {
        change { $0.links.removeAll { $0.id == id } }
    }

    @discardableResult
    func addNote(_ kind: CanvasNoteKind, at p: CGPoint, slug: String? = nil,
                 rx: Double? = nil, ry: Double? = nil) -> String {
        let id = CanvasDoc.newID()
        change {
            $0.notes.append(.init(id: id, kind: kind.rawValue, text: "", x: Double(p.x.rounded()),
                                  y: Double(p.y.rounded()), near: nil, slug: slug, rx: rx, ry: ry, slugs: nil))
        }
        return id
    }

    /// Note text is committed when you finish typing, so one edit is one undo step.
    func setNoteText(_ id: String, _ text: String) {
        change { d in
            guard let i = d.notes.firstIndex(where: { $0.id == id }) else { return }
            d.notes[i].text = text
        }
    }

    func moveNote(_ id: String, to p: CGPoint) {
        change { d in
            guard let i = d.notes.firstIndex(where: { $0.id == id }) else { return }
            d.notes[i].x = Double(p.x.rounded())
            d.notes[i].y = Double(p.y.rounded())
        }
    }

    /// A note goes with every link that touches it (web).
    func removeNote(_ id: String) {
        change { d in
            d.notes.removeAll { $0.id == id }
            d.links.removeAll { $0.a == id || $0.b == id }
        }
        if selected == id { selected = nil }
    }

    // MARK: - Named canvases

    /// Known canvases: the server list when signed in, plus device-only ones,
    /// so the menu works offline too (web `listCanvases`).
    func refreshList() async {
        var list = known
        if !isShot, let api = CanvasAPI.current, let remote = try? await api.list() {
            let local = list.filter { $0.id.hasPrefix("local-") }
            list = remote.map {
                CanvasListEntry(id: $0.id, name: $0.name ?? ($0.id == Self.libraryID ? "Library canvas" : "Untitled canvas"),
                                cards: $0.cards)
            } + local
            saveKnown(list)
        }
        if !list.contains(where: { $0.id == Self.libraryID }) {
            list.append(.init(id: Self.libraryID, name: currentID == Self.libraryID ? doc.name : "Library canvas"))
        }
        if let i = list.firstIndex(where: { $0.id == currentID }) {
            list[i].name = doc.name
        } else {
            list.insert(.init(id: currentID, name: doc.name), at: 0)
        }
        canvases = list
        publishForSafari()
    }

    /// Safari's menu, drop shelf and popup (and the share sheet) offer these canvases:
    /// the open one first, then the rest in list order. Screenshot runs share nothing.
    func publishForSafari() {
        guard !isShot else { return }
        var list = canvases.filter { !$0.id.hasPrefix("local-screenshot") }
        if let i = list.firstIndex(where: { $0.id == currentID }) { list.insert(list.remove(at: i), at: 0) }
        SafariSaveInbox.publishCanvases(list.map { .init(id: $0.id, name: $0.name.isEmpty ? "Untitled canvas" : $0.name) })
    }

    // MARK: - Saves from Safari

    /// Put saved items on a canvas without opening it: `id` is a canvas id, or "new" to
    /// make one called `newName`. They land together, to the right of what's there, in up
    /// to four columns, and two or more become one group named `groupName`. Items already
    /// on that canvas stay where they are. Returns the canvas id and name, or nil if it failed.
    func place(_ slugs: [String], in id: String, newName: String?, groupName: String?,
               height: @escaping (String) -> CGFloat) async -> (id: String, name: String)? {
        var target = id
        if id == "new" {
            var fresh = CanvasDoc(name: Self.cleanName(newName) ?? "Untitled canvas")
            fresh.v = CanvasDoc.version
            var newID = "local-" + CanvasDoc.newID()
            var newRev = 0
            if !isShot, let api = CanvasAPI.current, let project = try? await api.create(fresh) {
                newID = project.id
                newRev = project.rev
            }
            if let data = try? JSONEncoder().encode(Local(rev: newRev, doc: fresh)) {
                try? data.write(to: Self.localURL(for: newID), options: .atomic)
            }
            remember(newID, fresh.name)
            target = newID
        }
        if target == currentID {
            change { Self.lay(slugs, in: &$0, groupName: groupName, height: height) }
            await refreshList()
            return (target, doc.name)
        }
        // Another canvas: edit its local copy and the server copy, leave the open one alone.
        let url = Self.localURL(for: target)
        var local = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Local.self, from: $0) }
        if !target.hasPrefix("local-"), let api = CanvasAPI.current {
            for _ in 0..<2 {
                var base = local ?? Local(rev: 0, doc: CanvasDoc(name: Self.cleanName(newName) ?? "Untitled canvas"))
                if let server = try? await api.get(target), server.rev >= base.rev, let d = server.doc {
                    base = Local(rev: server.rev, doc: d)
                }
                Self.lay(slugs, in: &base.doc, groupName: groupName, height: height)
                base.doc.v = CanvasDoc.version
                guard let result = try? await api.save(target, doc: base.doc, rev: base.rev) else {
                    local = base  // offline: keep it here; the next open pushes it
                    break
                }
                if case .saved(let project) = result {
                    base.rev = project.rev
                    local = base
                    break
                }
                // Changed elsewhere meanwhile: start again from that copy.
                if case .conflict(let project) = result { local = Local(rev: project.rev, doc: project.doc ?? CanvasDoc()) }
            }
        } else {
            var base = local ?? Local(rev: 0, doc: CanvasDoc(name: "Untitled canvas"))
            Self.lay(slugs, in: &base.doc, groupName: groupName, height: height)
            local = base
        }
        guard let local, let data = try? JSONEncoder().encode(local) else { return nil }
        try? data.write(to: url, options: .atomic)
        remember(target, local.doc.name)
        await refreshList()
        return (target, local.doc.name)
    }

    private static func cleanName(_ name: String?) -> String? {
        let n = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? nil : String(n.prefix(80))
    }

    /// The layout for a batch from Safari: shortest-column masonry, right of the canvas.
    static func lay(_ slugs: [String], in d: inout CanvasDoc, groupName: String?,
                    height: (String) -> CGFloat) {
        let fresh = slugs.reduce(into: [String]()) { out, s in
            if !d.contains(s) && !out.contains(s) { out.append(s) }
        }
        guard !fresh.isEmpty else { return }
        let w = CanvasMetrics.cardWidth, gap = CanvasMetrics.cardGap
        var left: CGFloat = 0, top: CGFloat = 0
        if !d.cards.isEmpty {
            left = CGFloat(d.cards.map { $0.x }.max() ?? 0) + w + 160
            top = CGFloat(d.cards.map { $0.y }.min() ?? 0)
        }
        let columns = min(4, fresh.count)
        var bottoms = [CGFloat](repeating: top, count: columns)
        for slug in fresh {
            let col = bottoms.indices.min { bottoms[$0] < bottoms[$1] } ?? 0
            let x = (left + CGFloat(col) * (w + gap)).rounded()
            d.cards.append(.init(slug: slug, x: Double(x), y: Double(bottoms[col].rounded())))
            bottoms[col] += height(slug) + gap
        }
        if fresh.count >= 2 {
            let name = cleanName(groupName) ?? "From Safari"
            d.groups.append(.init(id: CanvasDoc.newID(), name: String(name.prefix(40)), slugs: fresh))
        }
    }

    /// Open another canvas. Pending edits to this one are saved first.
    func switchTo(_ id: String) async {
        guard id != currentID else { return }
        await flush()
        currentID = id
        if !isShot { UserDefaults.standard.set(id, forKey: Self.currentKey) }
        undoStack = []
        dirty = false
        selected = nil
        pick = nil
        focusSlug = nil
        cameraMoved = false
        loadLocal()
        cameraPlaced = false
        let hadCards = !doc.cards.isEmpty
        await pull()
        // The server copy brought the cards: frame them once.
        if !hadCards && !doc.cards.isEmpty && !cameraMoved { cameraPlaced = false }
        if let i = canvases.firstIndex(where: { $0.id == id }) { canvases[i].name = doc.name }
        publishForSafari()
    }

    /// A new empty canvas, or a copy of this one ("Save as a new canvas").
    func newCanvas(copy: Bool) async {
        await flush()
        var fresh = copy ? doc : CanvasDoc(name: "Untitled canvas")
        fresh.name = copy ? "\(doc.name.isEmpty ? "Canvas" : doc.name) copy" : "Untitled canvas"
        fresh.v = CanvasDoc.version
        var id = "local-" + CanvasDoc.newID()
        var newRev = 0
        if !isShot, let api = CanvasAPI.current, let project = try? await api.create(fresh) {
            id = project.id
            newRev = project.rev
        }
        if let data = try? JSONEncoder().encode(Local(rev: newRev, doc: fresh)) {
            try? data.write(to: Self.localURL(for: id), options: .atomic)
        }
        remember(id, fresh.name)
        await switchTo(id)
        notice = copy ? "Saved as a new canvas" : nil
        await refreshList()
    }

    func rename(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, n != doc.name else { return }
        change { $0.name = n }
        remember(currentID, n)
        if let i = canvases.firstIndex(where: { $0.id == currentID }) { canvases[i].name = n }
        publishForSafari()
    }

    /// Delete this canvas (never the library one) and go back to the library canvas.
    func deleteCurrent() async {
        guard currentID != Self.libraryID else { return }
        let id = currentID
        pushTask?.cancel()
        dirty = false
        if !id.hasPrefix("local-"), let api = CanvasAPI.current { try? await api.delete(id) }
        try? FileManager.default.removeItem(at: Self.localURL(for: id))
        remember(id, nil, drop: true)
        await switchTo(Self.libraryID)
        notice = "Canvas deleted"
        await refreshList()
    }

    private func flush() async {
        guard dirty else { return }
        pushTask?.cancel()
        await push()
    }

    private var known: [CanvasListEntry] {
        guard let data = UserDefaults.standard.data(forKey: Self.listKey) else { return [] }
        return (try? JSONDecoder().decode([CanvasListEntry].self, from: data)) ?? []
    }

    private func saveKnown(_ list: [CanvasListEntry]) {
        guard !isShot else { return }
        let slim = list.prefix(100).map { CanvasListEntry(id: $0.id, name: $0.name) }
        if let data = try? JSONEncoder().encode(Array(slim)) { UserDefaults.standard.set(data, forKey: Self.listKey) }
    }

    private func remember(_ id: String, _ name: String?, drop: Bool = false) {
        var list = known.filter { $0.id != id }
        if !drop { list.insert(.init(id: id, name: name ?? "Untitled canvas"), at: 0) }
        saveKnown(list)
        if drop { canvases.removeAll { $0.id == id } }
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

/// One canvas in the doc menu.
nonisolated struct CanvasListEntry: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var cards: Int? = nil
}


/// Canvas layer switches, the web's `layers` (canvas.js): Layer 1 similarity
/// (on, always show lines, one switch per kind) and the insight parts the Apple
/// canvas draws (marks, notes).
nonisolated struct CanvasLayers: Codable, Equatable, Sendable {
    var simOn = true
    var alwaysLines = false
    var kinds: Set<String> = Set(SimKind.allCases.map(\.rawValue))
    var marks = true
    var notes = true
    /// "Gaps: maybe related, empty spots": the dashed "+ Maybe" pill on a group.
    var gaps = true
    /// "Revisits: glow and fade": cards opened in the last 14 days glow, cards not
    /// opened for 120 days fade.
    var glow = true

    init() {}

    /// Missing keys keep their defaults, so settings saved before a part existed load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CanvasLayers()
        simOn = try c.decodeIfPresent(Bool.self, forKey: .simOn) ?? d.simOn
        alwaysLines = try c.decodeIfPresent(Bool.self, forKey: .alwaysLines) ?? d.alwaysLines
        kinds = try c.decodeIfPresent(Set<String>.self, forKey: .kinds) ?? d.kinds
        marks = try c.decodeIfPresent(Bool.self, forKey: .marks) ?? d.marks
        notes = try c.decodeIfPresent(Bool.self, forKey: .notes) ?? d.notes
        gaps = try c.decodeIfPresent(Bool.self, forKey: .gaps) ?? d.gaps
        glow = try c.decodeIfPresent(Bool.self, forKey: .glow) ?? d.glow
    }

    func shows(_ kind: SimKind) -> Bool { simOn && kinds.contains(kind.rawValue) }

    private static let key = "stello.canvas.layers"

    static func load() -> CanvasLayers {
        guard !ProcessInfo.processInfo.arguments.contains("-screenshotCleanStore"),
              let data = UserDefaults.standard.data(forKey: key),
              let layers = try? JSONDecoder().decode(CanvasLayers.self, from: data) else { return CanvasLayers() }
        return layers
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}
