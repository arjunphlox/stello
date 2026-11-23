import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The canvas: an empty, zoomable surface you fill by dragging items in from the
/// grid (web canvas v2, PRs #94–#97). Cards sit at the same world spots as on the
/// web, because the doc is shared through `/api/projects`.
///
/// Rendering follows the web's rules: one world layer moved by a transform, and
/// only cards in view are built (the rest of the library is never touched).
/// Camera: trackpad scroll pans and pinch zooms at the pointer; ⌘-scroll zooms on
/// a mouse; + / - step, 0 is 100%, ⇧1 fits. Touch: drag pans, pinch zooms.
struct CanvasView: View {
    /// Inset panel (Split) instead of the full view.
    var isPanel = false
    /// Show the zoom pill inside the canvas (Split; Canvas mode puts it in the bar).
    var showsZoom = true
    /// Extra top space for overlays when the canvas runs under the status bar (iPhone).
    var topInset: CGFloat = 0
    var onOpen: (Item) -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.enrichmentCoordinator) private var enrichmentCoordinator

    @State private var index: [String: Item] = [:]
    @State private var dragSlug: String?
    @State private var dragDelta: CGSize = .zero
    @State private var panStart: CanvasCamera?
    @State private var pinchStart: CanvasCamera?
    @State private var dropTargeted = false
    // Layer 1 (stage 3): features of the canvas items, families, and what the
    // lines follow (dragged ?? selected ?? hovered card).
    @State private var features: [String: [SimFeature]] = [:]
    @State private var inverted: [String: [String]] = [:]
    @State private var families: [CanvasFamily] = []
    @State private var hoverSlug: String?
    @State private var openDetails: Set<String> = []
    @State private var suggestion: CanvasGroupSuggestion?
    @State private var nearLinks: [SimNear] = []
    /// Gaps: the "+ Maybe" save for each group, by family id.
    @State private var maybes: [String: MaybePick] = [:]
    // Layer 2 (stage 4): note drags, the label / reason prompts, the pointer for
    // "add a note here", and the Package export.
    @State private var noteDragID: String?
    @State private var noteDragDelta: CGSize = .zero
    @State private var labelLinkID: String?
    @State private var labelKind: L2Kind = .influence
    @State private var labelText = ""
    @State private var reasonSlug: String?
    @State private var reasonText = ""
    @State private var pointer: CGPoint?
    @State private var exportDoc: CanvasPackageDocument?
    @State private var exporting = false
    @FocusState private var focused: Bool
    @FocusState private var noteFocus: String?

    private var store: CanvasStore { .shared }
    private var layers: CanvasLayers { store.layers }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                dotGrid(store.camera)
                    .contentShape(Rectangle())
                    .gesture(panGesture)
                    .onTapGesture(coordinateSpace: .named("canvas")) { loc in backgroundTap(at: loc) }
                    .contextMenu { backgroundMenu }

                annotations(size: geo.size, over: false)

                world(size: geo.size)

                familyPills(size: geo.size)

                annotations(size: geo.size, over: true)

                if store.doc.cards.isEmpty {
                    emptyState.frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .coordinateSpace(name: "canvas")
            .simultaneousGesture(pinchGesture)
            .onContinuousHover(coordinateSpace: .named("canvas")) { phase in
                if case .active(let p) = phase { pointer = p } else { pointer = nil }
            }
            .overlay(alignment: .top) { pickHint }
            .overlay(alignment: menusAlignment) {
                CanvasLayerMenus()
                    .padding(.top, menusAtBottom ? 0 : StelloLayout.windowInset + topInset)
                    .padding(.bottom, menusAtBottom ? menusBottomInset : 0)
                    .padding(.horizontal, StelloLayout.windowInset)
            }
            .overlay(alignment: .bottomLeading) {
                if isPanel { CanvasDocBox().padding(StelloLayout.windowInset) }
            }
            .overlay(alignment: .bottomTrailing) {
                if showsZoom {
                    CanvasZoomPill(viewport: geo.size).padding(StelloLayout.windowInset)
                }
            }
            .overlay(alignment: .top) {
                if let notice = store.notice {
                    Text(notice)
                        .font(.karst(.caption, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, StelloLayout.windowInset + topInset)
                        .task { try? await Task.sleep(for: .seconds(3)); store.notice = nil }
                }
            }
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: isPanel ? StelloLayout.panelCornerRadius : 0)
                        .stroke(theme.accentColor.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: CanvasDragItem.self) { dropped, location in
                drop(dropped.map(\.slug), at: location)
            } isTargeted: { dropTargeted = $0 }
            #if os(macOS)
            .background(CanvasScrollMonitor(onScroll: handleScroll))
            #endif
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onKeyPress(phases: .down, action: handleKey)
            .onAppear {
                store.viewportSize = geo.size
                refreshIndex()
                placeCamera(size: geo.size)
                focusIfAsked(size: geo.size)
            }
            .onChange(of: geo.size) { _, size in
                store.viewportSize = size
                // Until you move the camera, keep the opening fit centred as the
                // window or the split settles.
                if !store.cameraMoved && !store.doc.cards.isEmpty { fitAll(size: size, animated: false) }
            }
            .onChange(of: store.cameraPlaced) { _, placed in if !placed { placeCamera(size: geo.size) } }
            .onChange(of: store.slugs) { _, _ in refreshIndex() }
            .onChange(of: store.doc) { _, _ in refreshFamilies() }
            .onChange(of: store.layers) { _, _ in refreshFeatures() }
            .onChange(of: store.focusSlug) { _, _ in focusIfAsked(size: geo.size) }
            .onChange(of: store.exportRequest) { _, _ in exportPackage() }
            .onChange(of: store.fitRequest) { _, _ in fitAll(size: geo.size, animated: true) }
            .task { await store.pull(); refreshIndex() }
            .task(id: maybeKey) { await refreshMaybes() }
        }
        .background(isPanel ? theme.backgroundSubtle : theme.background)
        .clipShape(RoundedRectangle(cornerRadius: isPanel ? StelloLayout.panelCornerRadius : 0, style: .continuous))
        .overlay {
            if isPanel {
                RoundedRectangle(cornerRadius: StelloLayout.panelCornerRadius, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            }
        }
        .alert(labelKind.labelPrompt, isPresented: Binding(get: { labelLinkID != nil },
                                                          set: { if !$0 { labelLinkID = nil } })) {
            TextField("Optional", text: $labelText)
            Button("Save") {
                if let id = labelLinkID { store.setLinkLabel(id, labelText) }
                labelLinkID = nil
            }
            Button("Skip", role: .cancel) { labelLinkID = nil }
        }
        .alert("Why? (optional)", isPresented: Binding(get: { reasonSlug != nil },
                                                      set: { if !$0 { reasonSlug = nil } })) {
            TextField("A few words", text: $reasonText)
            Button("Save") {
                if let s = reasonSlug { store.setReason(s, reasonText) }
                reasonSlug = nil
            }
            Button("Skip", role: .cancel) { reasonSlug = nil }
        }
        .fileExporter(isPresented: $exporting, document: exportDoc, contentType: .zip,
                      defaultFilename: CanvasPackageExporter.slugName(store.doc.name) + ".zip") { result in
            if case .failure = result { store.notice = "Couldn’t save the Package" }
            exportDoc = nil
        }
    }

    // MARK: - Layer menus placement

    /// Phones put the menus above the bottom bar, as the web phone does; wider
    /// layouts put them top right.
    private var menusAtBottom: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }
    private var menusAlignment: Alignment { menusAtBottom ? .bottomLeading : .topTrailing }
    private var menusBottomInset: CGFloat {
        #if os(iOS)
        StelloLayout.bottomEdgeGap() + StelloLayout.compactControlBarHeight + StelloLayout.controlBarSpacing
        #else
        0
        #endif
    }

    // MARK: - Layers

    /// Dot grid in screen space, spaced by zoom so it reads as a surface.
    private func dotGrid(_ cam: CanvasCamera) -> some View {
        Canvas { ctx, size in
            var step: CGFloat = 32 * cam.k
            while step < 14 { step *= 4 }
            let ox = cam.x.truncatingRemainder(dividingBy: step)
            let oy = cam.y.truncatingRemainder(dividingBy: step)
            let dot = Path(ellipseIn: CGRect(x: -0.75, y: -0.75, width: 1.5, height: 1.5))
            var y = oy - step
            while y < size.height + step {
                var x = ox - step
                while x < size.width + step {
                    ctx.fill(dot.offsetBy(dx: x, dy: y), with: .color(theme.border.opacity(0.9)))
                    x += step
                }
                y += step
            }
        }
    }

    /// The selected card and what Layer 1 links it to; the rest dim (web `is-dim`).
    private var linked: Set<String>? {
        guard let s = store.selected, features[s] != nil else { return nil }
        let links = dragSlug == s
            ? nearLinks.map(\.b)
            : CanvasSimilarity.neighbours(of: s, features: features, inverted: inverted).map(\.b)
        return links.isEmpty ? nil : Set(links + [s])
    }

    /// Web: a dimmed card 0.22, a faded (not revisited) card 0.5, both 0.18.
    static func cardOpacity(dim: Bool, fade: Bool) -> Double {
        switch (dim, fade) {
        case (true, true): 0.18
        case (true, false): 0.22
        case (false, true): 0.5
        case (false, false): 1
        }
    }

    private func world(size: CGSize) -> some View {
        let cam = store.camera
        let linked = linked
        let view = CGRect(origin: .zero, size: size).insetBy(dx: -120, dy: -120)
        let visible = store.doc.cards.filter { c in
            guard let item = index[c.slug] else { return false }
            let r = CGRect(x: c.x * cam.k + cam.x, y: c.y * cam.k + cam.y,
                           width: CanvasMetrics.cardWidth * cam.k, height: height(item) * cam.k)
            return r.intersects(view)
        }
        return ZStack(alignment: .topLeading) {
            ForEach(visible, id: \.slug) { c in
                if let item = index[c.slug] {
                    let moving = dragSlug == c.slug
                    let open = openDetails.contains(c.slug)
                    let visit = layers.glow ? CanvasVisit.of(lastOpened: item.lastOpenedAt, count: item.openCount) : nil
                    CanvasCardView(item: item, height: height(item),
                                   isSelected: store.selected == c.slug,
                                   counterScale: 1 / cam.k,
                                   detailsOpen: open,
                                   onDetails: { toggleDetails(c.slug, size: size) },
                                   mark: layers.marks ? c.state.flatMap(CanvasMark.init(rawValue:)) : nil,
                                   reason: layers.marks ? c.note : nil,
                                   visit: visit)
                        .opacity(Self.cardOpacity(dim: !(linked?.contains(c.slug) ?? true), fade: visit != nil && visit?.isGlow == false))
                        .shadow(color: .black.opacity(moving ? 0.28 : 0), radius: 12, y: 6)
                        .offset(x: c.x + (moving ? dragDelta.width : 0),
                                y: c.y + (moving ? dragDelta.height : 0))
                        .gesture(cardDrag(c.slug))
                        .onTapGesture(count: 2) { onOpen(item) }
                        .onTapGesture(coordinateSpace: .named("canvas")) { loc in cardTap(c.slug, at: loc, height: height(item), size: size) }
                        .onHover { inside in
                            if inside { hoverSlug = c.slug } else if hoverSlug == c.slug { hoverSlug = nil }
                        }
                        .contextMenu {
                            // The grid card's menu, with the canvas actions slotted in
                            // (web: the same menu on right-click / press and hold).
                            Button("Open", systemImage: "arrow.up.right") { onOpen(item) }
                            Button(open ? "Hide Details" : "Show Details") { toggleDetails(c.slug, size: size) }
                            Button("Enrich", systemImage: "sparkles") {
                                enrichmentCoordinator.scheduleEnrichment(for: item, context: context, force: true)
                            }
                            if let s = item.sourceURL, !s.isEmpty, let url = URL(string: s) {
                                ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                                Button("Copy Link", systemImage: "link") { copyText(url.absoluteString) }
                            }
                            Button("Copy Title", systemImage: "textformat") { copyText(item.title) }
                            Divider()
                            cardLayer2Menu(c)
                            Divider()
                            if store.doc.groups.contains(where: { $0.slugs.contains(c.slug) }) {
                                Button("Remove from Group") { store.leaveGroup(c.slug) }
                            }
                            Button("Remove from Canvas", role: .destructive) { store.remove([c.slug]) }
                        }
                        .zIndex(moving ? 2 : open ? 1 : 0)
                }
            }
            ForEach(store.doc.notes, id: \.id) { note in
                if layers.notes, let x = note.x, let y = note.y {
                    let moving = noteDragID == note.id
                    CanvasNoteView(note: note, isSelected: store.selected == note.id, focus: $noteFocus,
                                   onCommit: { store.setNoteText(note.id, $0) },
                                   onDelete: { store.removeNote(note.id) })
                        .offset(x: x + (moving ? noteDragDelta.width : 0), y: y + (moving ? noteDragDelta.height : 0))
                        .gesture(noteDrag(note.id))
                        .onTapGesture { noteTap(note.id) }
                        .contextMenu {
                            Menu("Link") {
                                ForEach(L2Kind.allCases, id: \.self) { k in
                                    Button(k.action) { store.selected = note.id; store.pick = .link(from: note.id, kind: k) }
                                }
                            }
                            Button("Delete Note", role: .destructive) { store.removeNote(note.id) }
                        }
                        .zIndex(moving ? 4 : 3)
                }
            }
        }
        .scaleEffect(cam.k, anchor: .topLeading)
        .offset(x: cam.x, y: cam.y)
    }

    /// Drawn in screen space, as the web does: family tints and line strokes under
    /// the cards (`over` false), with cards that don't link dimmed so the lines
    /// read through them; line labels and the "Drop to group" box over the cards.
    /// Lines show only for the card you drag, select or hover.
    private func annotations(size: CGSize, over: Bool) -> some View {
        let cam = store.camera
        let live = rects()
        let view = CGRect(origin: .zero, size: size).insetBy(dx: -200, dy: -200)
        let text = theme.textPrimary
        let accent = theme.accentColor
        let surface = theme.surfaceRaised
        let focus = dragSlug ?? store.selected ?? hoverSlug
        let lines: [(a: String, b: String, kind: SimKind, label: String?, alpha: Double, width: CGFloat)]
        if let d = dragSlug {
            lines = nearLinks.map { n in
                let a = max(0.3, 1 - Double(n.distance) / 720)
                return (d, n.b, n.kind, n.distance < 720 * 0.65 ? n.label : nil, a, CGFloat(1.4 + a))
            }
        } else if let f = focus, features[f] != nil {
            lines = CanvasSimilarity.neighbours(of: f, features: features, inverted: inverted)
                .map { ($0.a, $0.b, $0.kind, cam.k >= 0.25 ? $0.label : nil, 0.95, 2) }
        } else if layers.alwaysLines {
            // "Always show lines": every pair once, quieter than a focused card's lines.
            var seen = Set<String>()
            var all: [(a: String, b: String, kind: SimKind, label: String?, alpha: Double, width: CGFloat)] = []
            for c in store.doc.cards {
                for n in CanvasSimilarity.neighbours(of: c.slug, features: features, inverted: inverted) {
                    let key = n.a < n.b ? n.a + "|" + n.b : n.b + "|" + n.a
                    if seen.insert(key).inserted { all.append((n.a, n.b, n.kind, nil, 0.5, 1.4)) }
                }
            }
            lines = all
        } else {
            lines = []
        }
        let fams = families
        let sug = suggestion
        let dragging = dragSlug
        let ends = live.merging(noteRects()) { a, _ in a }
        let l2 = store.doc.links.compactMap { l -> (a: CGRect, b: CGRect, kind: L2Kind, label: String?, color: Color)? in
            guard let kind = L2Kind(rawValue: l.kind), let ra = ends[l.a], let rb = ends[l.b] else { return nil }
            if kind == .question || kind == .partOf ? !layers.notes : (!layers.marks && kind != .maybe) { return nil }
            return (ra, rb, kind, kind.text(l.label), kind.color)
        }
        let amber = Color(hex: "#f0a23a")
        let regions = store.doc.notes.compactMap { n -> (note: CGRect, spot: CGPoint)? in
            guard layers.notes, n.kind == CanvasNoteKind.region.rawValue, let s = n.slug, let r = live[s],
                  let nr = ends[n.id] else { return nil }
            let spot = CGPoint(x: r.minX + CGFloat(min(1, max(0, n.rx ?? 0.5))) * r.width,
                               y: r.minY + CGFloat(min(1, max(0, n.ry ?? 0.5))) * r.height)
            return (nr, spot)
        }
        return Canvas { ctx, _ in
            func screen(_ r: CGRect) -> CGRect {
                CGRect(x: r.minX * cam.k + cam.x, y: r.minY * cam.k + cam.y, width: r.width * cam.k, height: r.height * cam.k)
            }
            func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * cam.k + cam.x, y: p.y * cam.k + cam.y) }
            func pill(_ label: String, at p: CGPoint, color: Color, anchor: UnitPoint, filled: Bool = false) -> CGRect {
                let t = ctx.resolve(Text(label).font(.karst(size: 11, weight: .medium))
                    .foregroundColor(filled ? .white : color))
                let m = t.measure(in: CGSize(width: 320, height: 30))
                let w = m.width + 14, h = m.height + 6
                let r = CGRect(x: p.x - w * anchor.x, y: p.y - h * anchor.y, width: w, height: h)
                let shape = Path(roundedRect: r, cornerRadius: h / 2)
                ctx.fill(shape, with: .color(filled ? color : surface))
                if !filled { ctx.stroke(shape, with: .color(color.opacity(0.35)), lineWidth: 1) }
                ctx.draw(t, at: CGPoint(x: r.midX, y: r.midY), anchor: .center)
                return r
            }

            // Families: a soft tint behind the members, pills naming what they share.
            for fam in fams where !over {
                let members = fam.slugs.filter { $0 != dragging || fam.slugs.count == 1 }.compactMap { live[$0] }
                guard let first = members.first else { continue }
                let box = screen(members.dropFirst().reduce(first) { $0.union($1) }.insetBy(dx: -18, dy: -18))
                guard box.intersects(view) else { continue }
                let color = fam.groupID != nil ? accent : (fam.kind?.color(text: text) ?? text)
                let shape = Path(roundedRect: box, cornerRadius: max(6, 20 * cam.k))
                ctx.fill(shape, with: .color(color.opacity(0.07)))
                ctx.stroke(shape, with: .color(color.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: fam.groupID != nil ? [] : [4, 4]))
                // The pills above the box are views (`familyPills`), so "+ Maybe" can be tapped.
            }

            // Layer 1 lines: right-angle runs, a dot at each end, the shared trait midway.
            // Strokes go under the cards (cards that don't link dim, as on the web);
            // labels go over them.
            for l in lines {
                guard let ra = live[l.a], let rb = live[l.b] else { continue }
                let pts = CanvasSimilarity.route(from: ra, to: rb).map(pt)
                guard pts.count >= 2 else { continue }
                let color = l.kind.color(text: text).opacity(l.alpha)
                var path = Path()
                path.move(to: pts[0])
                if pts.count > 2 {
                    for i in 1..<(pts.count - 1) {
                        let r = min(10, hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y) / 2,
                                    hypot(pts[i + 1].x - pts[i].x, pts[i + 1].y - pts[i].y) / 2)
                        path.addArc(tangent1End: pts[i], tangent2End: pts[i + 1], radius: r)
                    }
                }
                path.addLine(to: pts[pts.count - 1])
                let run = zip(pts, pts.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
                if over {
                    // Skip labels on short runs, where they would sit on a card's edge.
                    if let label = l.label, run >= 90 {
                        let mid = pts.count == 4
                            ? CGPoint(x: (pts[1].x + pts[2].x) / 2, y: (pts[1].y + pts[2].y) / 2)
                            : CGPoint(x: (pts[0].x + pts[pts.count - 1].x) / 2, y: (pts[0].y + pts[pts.count - 1].y) / 2)
                        _ = pill(CanvasSimilarity.cap(label), at: mid, color: l.kind.color(text: text), anchor: .center)
                    }
                    continue
                }
                ctx.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: l.width, lineCap: .round, dash: l.kind.dashed ? [6, 5] : []))
                for e in [pts[0], pts[pts.count - 1]] {
                    ctx.fill(Path(ellipseIn: CGRect(x: e.x - 3.2, y: e.y - 3.2, width: 6.4, height: 6.4)), with: .color(color))
                }
            }

            // Layer 2 links (yours): the kind's colour and dash, arrow heads, the label midway.
            for l in l2 {
                let pts = CanvasSimilarity.route(from: l.a, to: l.b).map(pt)
                guard pts.count >= 2 else { continue }
                let color = l.color
                if over {
                    let run = zip(pts, pts.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
                    if let label = l.label, run >= 90 {
                        let mid = pts.count == 4
                            ? CGPoint(x: (pts[1].x + pts[2].x) / 2, y: (pts[1].y + pts[2].y) / 2)
                            : CGPoint(x: (pts[0].x + pts[pts.count - 1].x) / 2, y: (pts[0].y + pts[pts.count - 1].y) / 2)
                        _ = pill(label, at: mid, color: color, anchor: .center)
                    }
                    continue
                }
                var path = Path()
                path.addLines(pts)
                ctx.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: l.kind.dash))
                func arrow(at tip: CGPoint, from tail: CGPoint) {
                    let a = atan2(tip.y - tail.y, tip.x - tail.x), size: CGFloat = 9
                    var head = Path()
                    head.move(to: tip)
                    head.addLine(to: CGPoint(x: tip.x - size * cos(a - 0.45), y: tip.y - size * sin(a - 0.45)))
                    head.addLine(to: CGPoint(x: tip.x - size * cos(a + 0.45), y: tip.y - size * sin(a + 0.45)))
                    head.closeSubpath()
                    ctx.fill(head, with: .color(color))
                }
                if l.kind.arrowEnd { arrow(at: pts[pts.count - 1], from: pts[pts.count - 2]) }
                if l.kind.arrowStart { arrow(at: pts[0], from: pts[1]) }
            }

            // Region notes: a line from the note to its spot on the image, a ring on the spot.
            if over {
                for r in regions {
                    let spot = pt(r.spot)
                    let from = pt(CanvasSimilarity.edgePoint(r.note, toward: r.spot))
                    var line = Path()
                    line.move(to: from)
                    line.addLine(to: spot)
                    ctx.stroke(line, with: .color(amber), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    let ring = Path(ellipseIn: CGRect(x: spot.x - 10, y: spot.y - 10, width: 20, height: 20))
                    ctx.fill(ring, with: .color(amber.opacity(0.25)))
                    ctx.stroke(ring, with: .color(.white), lineWidth: 3)
                    ctx.stroke(ring, with: .color(amber), lineWidth: 1.5)
                }
            }

            // "Drop to group": a dotted box around what dropping would group.
            if over, let sug {
                let box = screen(sug.box).insetBy(dx: -16 * cam.k, dy: -16 * cam.k)
                let shape = Path(roundedRect: box, cornerRadius: max(6, 20 * cam.k))
                ctx.fill(shape, with: .color(accent.opacity(0.06)))
                ctx.stroke(shape, with: .color(accent), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                _ = pill(sug.label, at: CGPoint(x: box.midX, y: box.minY - 6), color: accent, anchor: .bottom, filled: true)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Family pills and Gaps

    /// A family's box on screen (members' union, 18 out), the dragged card left out.
    private func familyBox(_ fam: CanvasFamily, rects live: [String: CGRect], cam: CanvasCamera) -> CGRect? {
        let members = fam.slugs.filter { $0 != dragSlug || fam.slugs.count == 1 }.compactMap { live[$0] }
        guard let first = members.first else { return nil }
        let r = members.dropFirst().reduce(first) { $0.union($1) }.insetBy(dx: -18, dy: -18)
        return CGRect(x: r.minX * cam.k + cam.x, y: r.minY * cam.k + cam.y, width: r.width * cam.k, height: r.height * cam.k)
    }

    /// Pills on the top-left of each family: its name, the traits every member shares,
    /// and (Gaps on) a dashed "+ Maybe: …" save from the library with a ✕ for "Not
    /// related" (web `.lc-fam`). Screen sized; only the maybe pills take taps.
    private func familyPills(size: CGSize) -> some View {
        let cam = store.camera
        let live = rects()
        let view = CGRect(origin: .zero, size: size).insetBy(dx: -200, dy: -200)
        let text = theme.textPrimary
        let accent = theme.accentColor
        return ZStack(alignment: .topLeading) {
            ForEach(families) { fam in
                if let box = familyBox(fam, rects: live, cam: cam), box.intersects(view), box.width >= 90 {
                    let color = fam.groupID != nil ? accent : (fam.kind?.color(text: text) ?? text)
                    // Looks-alike families use the text colour: their filled pill needs dark text.
                    let ink: Color = fam.groupID == nil && (fam.kind == nil || fam.kind?.hex == nil) ? theme.background : .white
                    let traits = HStack(spacing: 4) {
                        ForEach(Array(fam.pills.enumerated()), id: \.offset) { i, p in
                            familyPill(p, color: color, ink: ink, filled: i == 0)
                        }
                    }
                    let maybe = layers.gaps && dragSlug == nil ? maybes[fam.id] : nil
                    // Web `.lc-fam`: up to the box width + 160 (at least 120), wrapping
                    // upwards, so a long "+ Maybe" goes on a row above, not off screen.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 4) {
                            traits
                            if let maybe { maybeButtons(maybe, in: fam) }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            if let maybe { HStack(spacing: 4) { maybeButtons(maybe, in: fam) } }
                            traits
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(width: max(120, box.width + 160), alignment: .bottomLeading)
                    // Bottom-left of the row sits 6pt above the box's top-left corner.
                    .frame(width: 0, height: 0, alignment: .bottomLeading)
                    .offset(x: box.minX, y: box.minY - 6)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    @ViewBuilder private func maybeButtons(_ m: MaybePick, in fam: CanvasFamily) -> some View {
        Button { acceptMaybe(m, in: fam) } label: {
            maybePill { Text("+ Maybe: \(CanvasSimilarity.shortTitle(m.title))") }
        }
        .help("Maybe related: shares \(m.shared.joined(separator: ", ")). Click to add.")
        Button { store.dismissMaybe(m.slug) } label: {
            maybePill { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }
        }
        .help("Not related")
        .accessibilityLabel("Not related")
    }

    private func familyPill(_ label: String, color: Color, ink: Color, filled: Bool) -> some View {
        Text(label)
            .font(.karst(size: 11, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(filled ? ink : color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(filled ? color : theme.surfaceRaised, in: Capsule())
            .overlay { if !filled { Capsule().stroke(color.opacity(0.35), lineWidth: 1) } }
            .allowsHitTesting(false)
    }

    /// Web `.lc-pill.is-maybe`: dashed outline, dim text, no fill.
    private func maybePill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.karst(size: 11, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(theme.textDim)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(minWidth: 20)
            .background(theme.background.opacity(0.001), in: Capsule())
            .overlay(Capsule().stroke(theme.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            .contentShape(Capsule())
    }

    /// "+ Maybe": keep the pair as an Accepted link and drop the save beside the group's
    /// last card (web `data-maybe`).
    private func acceptMaybe(_ m: MaybePick, in fam: CanvasFamily) {
        guard let anchor = fam.slugs.last, let an = store.doc.card(anchor) else { return }
        for item in fetch([m.slug]) { index[item.slug] = item }
        store.addLink(anchor, m.slug, kind: .maybe, label: m.shared.first ?? "", source: "maybe")
        let at = CGPoint(x: an.x + CanvasMetrics.cardWidth + 10, y: an.y + 10)
        store.add([m.slug], at: at, height: { height(slug: $0) })
    }

    /// Changes whenever a group's maybe could change: its members, what's on the
    /// canvas, what you dismissed, the Gaps toggle, or a rebuilt library scan.
    private var maybeKey: String {
        guard layers.gaps else { return "off" }
        return families.filter { $0.slugs.count >= 2 }.map { $0.id + "=" + $0.slugs.joined(separator: ",") }
            .joined(separator: ";") + "|\(store.doc.cards.count)|\(store.doc.dismissed.count)|\(CanvasMaybeLibrary.shared.version)"
    }

    /// One library scan per change, off the main actor (web scans with a per-frame
    /// budget). The library's features are read once and kept (`CanvasMaybeLibrary`).
    private func refreshMaybes() async {
        guard layers.gaps else { maybes = [:]; return }
        let fams = families.filter { $0.slugs.count >= 2 }.map { (id: $0.id, slugs: $0.slugs) }
        guard !fams.isEmpty else { maybes = [:]; return }
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        let library = CanvasMaybeLibrary.shared
        await library.refresh(context: context)
        guard !Task.isCancelled else { return }
        let entries = library.entries
        let exclude = Set(store.doc.cards.map(\.slug)).union(store.doc.dismissed)
        let next = await Task.detached(priority: .utility) { () -> [String: MaybePick] in
            var bySlug: [String: [SimFeature]] = [:]
            for e in entries { bySlug[e.slug] = e.features }
            var out: [String: MaybePick] = [:]
            for f in fams {
                let members = f.slugs.compactMap { bySlug[$0] }
                if let m = CanvasSimilarity.maybe(members: members, memberCount: f.slugs.count,
                                                  library: entries, exclude: exclude) { out[f.id] = m }
            }
            return out
        }.value
        guard !Task.isCancelled else { return }
        maybes = next
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Your canvas is empty")
                .font(.karst(.title3, weight: .medium))
                .foregroundStyle(theme.textPrimary)
            Text(emptyHint)
                .font(.karst(.callout))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if store.viewMode == .canvas && !isPhone {
                Button("Show the grid beside it") { store.viewMode = .split }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .allowsHitTesting(store.viewMode == .canvas && !isPhone)
    }

    private var emptyHint: String {
        isPhone
            ? "In the grid, press and hold an item and choose Add to Canvas."
            : "Drag items here from the grid. Drop one next to another to line them up."
    }

    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("canvas"))
            .onChanged { v in
                if pinchStart != nil { return }
                let start = panStart ?? store.camera
                panStart = start
                store.cameraMoved = true
                var cam = start
                cam.pan(by: v.translation)
                store.camera = cam
            }
            .onEnded { _ in panStart = nil }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                let start = pinchStart ?? store.camera
                pinchStart = start
                panStart = nil
                store.cameraMoved = true
                var cam = start
                cam.zoom(to: start.k * v.magnification, anchor: v.startLocation)
                store.camera = cam
            }
            .onEnded { _ in pinchStart = nil }
    }

    private func cardDrag(_ slug: String) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("canvas"))
            .onChanged { v in
                if dragSlug != slug { dragSlug = slug; store.selected = slug }
                let k = store.camera.k
                dragDelta = CGSize(width: v.translation.width / k, height: v.translation.height / k)
                let all = rects()
                if let r = all[slug] {
                    var others = all
                    others[slug] = nil
                    suggestion = CanvasSimilarity.suggestion(for: slug, at: r, rects: others,
                                                             families: families, features: features)
                    nearLinks = CanvasSimilarity.near(slug, at: r, rects: others, features: features)
                }
            }
            .onEnded { _ in
                if let c = store.doc.card(slug) {
                    let to = CGPoint(x: c.x + dragDelta.width, y: c.y + dragDelta.height)
                    let r = CGRect(origin: to, size: CGSize(width: CanvasMetrics.cardWidth, height: height(slug: slug)))
                    let all = rects()
                    let group = store.doc.groups.first { $0.slugs.contains(slug) }
                    let leave = suggestion == nil && group.map { g in
                        CanvasSimilarity.leaves(r, others: g.slugs.filter { $0 != slug }.compactMap { all[$0] })
                    } == true
                    let joined = suggestion
                    store.move(slug, to: to, join: joined, leave: leave)
                    if let joined { store.notice = joined.joining ? "Added to \(joined.name)" : "Grouped as \(joined.name)" }
                }
                dragSlug = nil
                dragDelta = .zero
                suggestion = nil
                nearLinks = []
            }
    }

    #if os(macOS)
    /// Trackpad: two-finger scroll pans. Mouse wheel pans too; ⌘ or ⌃ + wheel zooms
    /// at the pointer (pinch comes through `MagnifyGesture`).
    private func handleScroll(_ e: NSEvent, at p: CGPoint) {
        store.cameraMoved = true
        var cam = store.camera
        if e.modifierFlags.contains(.command) || e.modifierFlags.contains(.control) {
            let dy = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.scrollingDeltaY * 8
            cam.zoom(to: cam.k * exp(dy * 0.01), anchor: p)
        } else {
            let m: CGFloat = e.hasPreciseScrollingDeltas ? 1 : 10
            cam.pan(by: CGSize(width: e.scrollingDeltaX * m, height: e.scrollingDeltaY * m))
        }
        store.camera = cam
    }
    #endif

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // Typing in a note: the keys are the note's.
        if noteFocus != nil { return .ignored }
        if press.key == .escape {
            if store.pick != nil { store.pick = nil; return .handled }
            if store.selected != nil { store.selected = nil; return .handled }
            return .ignored
        }
        let size = store.viewportSize
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        if press.modifiers.contains(.command) {
            if press.characters == "z" { store.undo(); return .handled }
            return .ignored
        }
        switch press.characters {
        case "+", "=":
            animateCamera { $0.zoom(to: $0.nextStep(up: true), anchor: centre) }
        case "-", "_":
            animateCamera { $0.zoom(to: $0.nextStep(up: false), anchor: centre) }
        case "0":
            animateCamera { $0.zoom(to: 1, anchor: centre) }
        case "!":
            fitAll(size: size, animated: true)
        case "@":
            if let s = store.selected, let item = index[s], let c = store.doc.card(s) {
                let box = CGRect(x: c.x, y: c.y, width: CanvasMetrics.cardWidth, height: height(item))
                animateCamera { $0 = CanvasCamera.fit(box, in: size, pad: 96, maxK: 1) }
            }
        default:
            if press.key == .delete || press.key == .deleteForward, let s = store.selected {
                if store.doc.notes.contains(where: { $0.id == s }) { store.removeNote(s); return .handled }
                store.remove([s]); store.selected = nil
                return .handled
            }
            let step: CGFloat = 80
            switch press.key {
            case .leftArrow: animateCamera { $0.pan(by: CGSize(width: step, height: 0)) }
            case .rightArrow: animateCamera { $0.pan(by: CGSize(width: -step, height: 0)) }
            case .upArrow: animateCamera { $0.pan(by: CGSize(width: 0, height: step)) }
            case .downArrow: animateCamera { $0.pan(by: CGSize(width: 0, height: -step)) }
            default: return .ignored
            }
        }
        return .handled
    }

    private func animateCamera(_ edit: (inout CanvasCamera) -> Void) {
        store.cameraMoved = true
        var cam = store.camera
        edit(&cam)
        withAnimation(.smooth(duration: 0.22)) { store.camera = cam }
    }

    // MARK: - Layer 2

    /// "Choose the item it inspired" while picking, with Cancel (web `lc-hint`).
    @ViewBuilder private var pickHint: some View {
        if let pick = store.pick {
            HStack(spacing: 10) {
                Text(pick.hint)
                    .font(.karst(.caption, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                Button("Cancel") { store.pick = nil }
                    .font(.karst(.caption, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.accentColor)
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(theme.border, lineWidth: 1))
            .padding(.top, StelloLayout.windowInset + topInset + (store.notice == nil ? 0 : 40))
        }
    }

    /// Use / Rejected, Why…, the link kinds, a note on the image, and your links.
    @ViewBuilder private func cardLayer2Menu(_ c: CanvasDoc.Card) -> some View {
        Toggle("Use", isOn: Binding(get: { c.state == CanvasMark.use.rawValue },
                                    set: { _ in mark(c.slug, .use) }))
        Toggle("Rejected", isOn: Binding(get: { c.state == CanvasMark.rejected.rawValue },
                                         set: { _ in mark(c.slug, .rejected) }))
        if c.state != nil {
            Button("Why…") { reasonText = c.note ?? ""; reasonSlug = c.slug }
        }
        Menu("Link") {
            ForEach(L2Kind.allCases, id: \.self) { k in
                Button(k.action) { store.selected = c.slug; store.pick = .link(from: c.slug, kind: k) }
            }
        }
        Button("Note on Image…") { store.selected = c.slug; store.pick = .region(slug: c.slug) }
        let mine = store.doc.links.filter { $0.a == c.slug || $0.b == c.slug }
        if !mine.isEmpty {
            Menu("Remove Link") {
                ForEach(mine, id: \.id) { l in
                    let other = l.a == c.slug ? l.b : l.a
                    let kind = L2Kind(rawValue: l.kind)?.label ?? l.kind
                    Button("\(kind) · \(endName(other))") { store.removeLink(l.id) }
                }
            }
        }
    }

    /// Add a question, note or set where you right-clicked (or mid-view on touch).
    @ViewBuilder private var backgroundMenu: some View {
        ForEach([CanvasNoteKind.question, .note, .set], id: \.self) { kind in
            Button("Add \(kind.label)") {
                let at = pointer.map { store.camera.toWorld($0) } ?? store.viewCenter
                newNote(kind, centredAt: at)
            }
        }
        if store.pick != nil {
            Divider()
            Button("Cancel Linking") { store.pick = nil }
        }
    }

    private func endName(_ id: String) -> String {
        if let item = index[id] { return item.title.isEmpty ? (item.domain ?? "Untitled") : item.title }
        if let n = store.doc.notes.first(where: { $0.id == id }) {
            let label = CanvasNoteKind(rawValue: n.kind)?.label ?? "Note"
            return n.text.isEmpty ? label : "\(label): \(n.text.prefix(30))"
        }
        return "Removed item"
    }

    private func mark(_ slug: String, _ m: CanvasMark) {
        let wasOn = store.doc.card(slug)?.state == m.rawValue
        store.setMark(slug, m)
        // Marking asks why, as the web does; clearing a mark asks nothing.
        if !wasOn { reasonText = store.doc.card(slug)?.note ?? ""; reasonSlug = slug }
    }

    @discardableResult
    private func newNote(_ kind: CanvasNoteKind, centredAt p: CGPoint) -> String {
        let id = store.addNote(kind, at: CGPoint(x: p.x - kind.width / 2, y: p.y - CanvasNoteKind.height / 2))
        store.selected = id
        focusNote(id)
        return id
    }

    /// Focus a new note once its field exists.
    private func focusNote(_ id: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            noteFocus = id
        }
    }

    private func backgroundTap(at loc: CGPoint) {
        noteFocus = nil
        if let pick = store.pick {
            // Part of / Ask on empty canvas make the set or question and link to it.
            if case .link(let from, let kind) = pick, let raw = kind.noteOnEmpty,
               let noteKind = CanvasNoteKind(rawValue: raw) {
                let id = newNote(noteKind, centredAt: store.camera.toWorld(loc))
                store.addLink(from, id, kind: kind)
            }
            store.pick = nil
            return
        }
        store.selected = nil
        openDetails = []
        focused = true
    }

    private func cardTap(_ slug: String, at loc: CGPoint, height h: CGFloat, size: CGSize) {
        noteFocus = nil
        focused = true
        switch store.pick {
        case .link(let from, let kind)?:
            completeLink(from: from, to: slug, kind: kind)
        case .region(let target)? where target == slug:
            if let c = store.doc.card(slug) {
                let w = store.camera.toWorld(loc)
                let rx = min(1, max(0, (w.x - c.x) / CanvasMetrics.cardWidth))
                let ry = min(1, max(0, (w.y - c.y) / h))
                let at = CGPoint(x: c.x + CanvasMetrics.cardWidth + 40, y: c.y + ry * h - 20)
                let id = store.addNote(.region, at: at, slug: slug, rx: Double(rx), ry: Double(ry))
                store.selected = id
                focusNote(id)
            }
            store.pick = nil
        case .region?:
            store.pick = nil
            store.selected = slug
        case nil:
            // A tap opens the card in place to show its details; again closes it.
            toggleDetails(slug, size: size)
        }
    }

    private func noteTap(_ id: String) {
        if case .link(let from, let kind)? = store.pick {
            completeLink(from: from, to: id, kind: kind)
            return
        }
        store.pick = nil
        store.selected = id
        focused = true
    }

    private func completeLink(from: String, to: String, kind: L2Kind) {
        store.pick = nil
        guard from != to, let id = store.addLink(from, to, kind: kind) else { store.selected = to; return }
        store.selected = from
        if kind.asksLabel {
            labelKind = kind
            labelText = store.doc.links.first { $0.id == id }?.label ?? ""
            labelLinkID = id
        }
    }

    private func noteDrag(_ id: String) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("canvas"))
            .onChanged { v in
                if noteDragID != id { noteDragID = id; store.selected = id }
                let k = store.camera.k
                noteDragDelta = CGSize(width: v.translation.width / k, height: v.translation.height / k)
            }
            .onEnded { _ in
                if let n = store.doc.notes.first(where: { $0.id == id }), let x = n.x, let y = n.y {
                    store.moveNote(id, to: CGPoint(x: x + noteDragDelta.width, y: y + noteDragDelta.height))
                }
                noteDragID = nil
                noteDragDelta = .zero
            }
    }

    /// World rects of the notes, for link ends (the dragged note where it is now).
    private func noteRects() -> [String: CGRect] {
        var out: [String: CGRect] = [:]
        for n in store.doc.notes {
            guard let x = n.x, let y = n.y else { continue }
            let kind = CanvasNoteKind(rawValue: n.kind) ?? .note
            let moving = n.id == noteDragID
            out[n.id] = CGRect(x: x + (moving ? noteDragDelta.width : 0), y: y + (moving ? noteDragDelta.height : 0),
                               width: kind.width, height: CanvasNoteKind.height)
        }
        return out
    }

    /// Build the Package (README, one Markdown file per item, covers, canvas.json)
    /// and hand it to the save panel.
    private func exportPackage() {
        guard !store.doc.cards.isEmpty else {
            store.notice = "Add items to the canvas to export it"
            return
        }
        refreshIndex()
        do {
            let data = try CanvasPackageExporter.makeZip(doc: store.doc, items: index, rects: rects(), families: families)
            exportDoc = CanvasPackageDocument(data: data)
            exporting = true
        } catch {
            store.notice = "Couldn’t build the Package"
        }
    }

    // MARK: - Data

    private func height(_ item: Item) -> CGFloat {
        let img = item.coverImage
        let hasImage = !(img?.data?.isEmpty ?? true)
        return CanvasMetrics.cardHeight(imageWidth: img?.width, imageHeight: img?.height, hasImage: hasImage)
    }

    private func height(slug: String) -> CGFloat {
        if let item = index[slug] ?? fetch([slug]).first { return height(item) }
        return (CanvasMetrics.cardWidth * 0.62).rounded()
    }

    /// Only the items on the canvas are fetched, never the whole library.
    private func fetch(_ slugs: [String]) -> [Item] {
        guard !slugs.isEmpty else { return [] }
        let wanted = slugs
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { wanted.contains($0.slug) })
        return (try? context.fetch(descriptor)) ?? []
    }

    private func refreshIndex() {
        let slugs = store.doc.cards.map(\.slug)
        let missing = slugs.filter { index[$0] == nil }
        var next = index.filter { store.slugs.contains($0.key) }
        for item in fetch(missing) where next[item.slug] == nil { next[item.slug] = item }
        if next.count != index.count || !missing.isEmpty {
            index = next
            refreshFeatures()
        } else if Set(features.keys) != Set(index.keys) {
            refreshFeatures()
        }
    }

    /// World rects of the cards on the canvas, with the dragged card where it is now.
    private func rects() -> [String: CGRect] {
        var out: [String: CGRect] = [:]
        for c in store.doc.cards {
            guard let item = index[c.slug] else { continue }
            let moving = c.slug == dragSlug
            out[c.slug] = CGRect(x: c.x + (moving ? dragDelta.width : 0), y: c.y + (moving ? dragDelta.height : 0),
                                 width: CanvasMetrics.cardWidth, height: height(item))
        }
        return out
    }

    /// Features of every item on the canvas; only the canvas items, never the library.
    private func refreshFeatures() {
        var next: [String: [SimFeature]] = [:]
        for (slug, item) in index {
            let kind = CanvasSimilarity.kindName(kindLine: item.cardKindLine, kind: item.kind,
                                                 hasURL: !(item.sourceURL ?? "").isEmpty)
            // Only the kinds switched on in the Similarity menu (web `layers.sim`).
            next[slug] = CanvasSimilarity.features(tags: item.tags, kindName: kind, domain: item.domain)
                .filter { layers.shows($0.kind) }
        }
        features = next
        inverted = CanvasSimilarity.invert(next)
        refreshFamilies()
        screenshotFocus()
    }

    /// Screenshot runs (-screenshotLayer1): select the card with the most Layer 1
    /// neighbours so its lines show, and open its details with -screenshotDetails.
    private func screenshotFocus() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-screenshotLayer1"), !args.contains("-screenshotRevisits"), !features.isEmpty else { return }
        let best = store.doc.cards.map(\.slug).max { a, b in
            let na = CanvasSimilarity.neighbours(of: a, features: features, inverted: inverted)
            let nb = CanvasSimilarity.neighbours(of: b, features: features, inverted: inverted)
            return na.count != nb.count ? na.count < nb.count : a > b
        }
        guard let best else { return }
        store.selected = best
        if args.contains("-screenshotDetails") { openDetails = [best] }
    }

    private func refreshFamilies() {
        var all = rects()
        if let d = dragSlug, let c = store.doc.card(d), let r = all[d] { all[d] = CGRect(origin: CGPoint(x: c.x, y: c.y), size: r.size) }
        families = CanvasSimilarity.families(groups: store.doc.groups, rects: all, features: features, inverted: inverted)
        openDetails = openDetails.filter { store.slugs.contains($0) }
    }

    private func toggleDetails(_ slug: String, size: CGSize) {
        if openDetails.contains(slug) {
            openDetails.remove(slug)
            if store.selected == slug { store.selected = nil }
            return
        }
        openDetails.insert(slug)
        store.selected = slug
        // Too small on screen to read (zoomed out, or on iPhone): fly in until it is.
        let cam = store.camera
        guard let c = store.doc.card(slug), size.width > 0,
              CanvasMetrics.cardWidth * cam.k < 230 else { return }
        let w = CanvasMetrics.cardWidth
        let k = min(1, max(cam.k, (min(size.width, 420) - 48) / w))
        let h = height(slug: slug) + 220
        let top = max(24, min(size.height * 0.18, size.height - 120 - h * k))
        store.cameraMoved = true
        withAnimation(.smooth(duration: 0.28)) {
            store.camera = CanvasCamera(x: size.width / 2 - (c.x + w / 2) * k, y: top - c.y * k, k: k)
        }
    }

    private func copyText(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    private func drop(_ slugs: [String], at location: CGPoint) -> Bool {
        let world = store.camera.toWorld(location)
        for item in fetch(slugs.filter { index[$0] == nil }) { index[item.slug] = item }
        let added = store.add(slugs, at: world, height: { height(slug: $0) })
        if let last = added.last { store.selected = last }
        return !added.isEmpty
    }

    private func placeCamera(size: CGSize) {
        guard !store.cameraPlaced, size.width > 0 else { return }
        store.cameraPlaced = true
        if store.doc.cards.isEmpty {
            store.camera = CanvasCamera(x: size.width / 2, y: size.height / 2, k: 0.5)
        } else {
            fitAll(size: size, animated: false)
        }
    }

    private func fitAll(size: CGSize, animated: Bool) {
        guard let box = store.bounds(height: { height(slug: $0) }) else { return }
        let cam = CanvasCamera.fit(box, in: size, pad: 64, maxK: 1)
        if animated { withAnimation(.smooth(duration: 0.25)) { store.camera = cam } } else { store.camera = cam }
    }

    private func focusIfAsked(size: CGSize) {
        guard let slug = store.focusSlug, let c = store.doc.card(slug), size.width > 0 else { return }
        store.focusSlug = nil
        store.cameraPlaced = true
        store.cameraMoved = true
        store.selected = slug
        let box = CGRect(x: c.x, y: c.y, width: CanvasMetrics.cardWidth, height: height(slug: slug))
        withAnimation(.smooth(duration: 0.3)) {
            store.camera = CanvasCamera.fit(box.insetBy(dx: -400, dy: -300), in: size, pad: 48, maxK: 1)
        }
    }
}

/// − 50% + and fit. Inside the canvas in Split; in the bar in Canvas mode.
struct CanvasZoomPill: View {
    var viewport: CGSize? = nil
    @Environment(\.appTheme) private var theme
    private var store: CanvasStore { .shared }

    var body: some View {
        let size = viewport ?? store.viewportSize
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        HStack(spacing: 2) {
            button("minus", "Zoom out") { $0.zoom(to: $0.nextStep(up: false), anchor: centre) }
            Button {
                store.cameraMoved = true
                withAnimation(.smooth(duration: 0.22)) { store.camera.zoom(to: 1, anchor: centre) }
            } label: {
                Text("\(Int((store.camera.k * 100).rounded()))%")
                    .font(.karst(size: 12, weight: .medium))
                    .monospacedDigit()
                    .frame(minWidth: 44)
            }
            .buttonStyle(.plain)
            .help("Zoom to 100%")
            button("plus", "Zoom in") { $0.zoom(to: $0.nextStep(up: true), anchor: centre) }
            // Fit everything (web "Fit", ⇧1).
            Button {
                store.cameraMoved = true
                store.fitRequest &+= 1
            } label: {
                Text("Fit")
                    .font(.karst(size: 12, weight: .medium))
                    .frame(minWidth: 32, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Fit everything")
        }
        .foregroundStyle(theme.textPrimary)
        .padding(.horizontal, 6)
        .frame(height: StelloLayout.controlBarButtonSize)
        .background(theme.surfaceRaised.opacity(StelloLayout.controlBarGlassFillOpacity), in: Capsule())
        .overlay(Capsule().stroke(theme.border, lineWidth: 1))
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func button(_ symbol: String, _ label: String, _ edit: @escaping (inout CanvasCamera) -> Void) -> some View {
        Button {
            store.cameraMoved = true
            var cam = store.camera
            edit(&cam)
            withAnimation(.smooth(duration: 0.22)) { store.camera = cam }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

#if os(macOS)
/// Scroll-wheel and trackpad scroll events over the canvas (SwiftUI has no pan-by-scroll
/// gesture on macOS). A local monitor, so clicks and drags still reach SwiftUI.
struct CanvasScrollMonitor: NSViewRepresentable {
    let onScroll: (NSEvent, CGPoint) -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) { view.onScroll = onScroll }

    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stop() }

    final class MonitorView: NSView {
        var onScroll: ((NSEvent, CGPoint) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
                return consumed ? nil : event
            }
        }

        private func handle(_ event: NSEvent) -> Bool {
            guard event.window === window else { return false }
            let p = convert(event.locationInWindow, from: nil)
            guard bounds.contains(p) else { return false }
            // NSView is bottom-left; SwiftUI's canvas space is top-left.
            let top = CGPoint(x: p.x, y: isFlipped ? p.y : bounds.height - p.y)
            onScroll?(event, top)
            return true
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#endif


/// The canvas's two layer menus, top right (web `.lc-controls`): Similarity
/// (Layer 1: on, kinds, always show lines) and Intent, time & gaps (Layer 2 parts).
struct CanvasLayerMenus: View {
    @Environment(\.appTheme) private var theme
    private var store: CanvasStore { .shared }

    private static let hints: [SimKind: String] = [
        .place: "city or country", .colour: "shared palette", .looks: "similar look",
        .kind: "tool, studio, portfolio, foundry", .idea: "overlapping topic", .style: "shared style tags",
    ]

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 8) {
            Menu {
                Toggle("Sort by similarity", isOn: $store.layers.simOn)
                Section {
                    ForEach(SimKind.allCases, id: \.self) { k in
                        Toggle(isOn: kindBinding(k)) {
                            Text(k.label)
                            Text(Self.hints[k] ?? "")
                        }
                        .disabled(!store.layers.simOn)
                    }
                }
                Section {
                    Toggle("Always show lines", isOn: $store.layers.alwaysLines)
                        .disabled(!store.layers.simOn)
                }
            } label: {
                pill {
                    HStack(spacing: 2) {
                        ForEach(SimKind.allCases.filter { store.layers.shows($0) }, id: \.self) { k in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(k.color(text: theme.textPrimary))
                                .frame(width: 3, height: 12)
                        }
                    }
                    Text("Similarity")
                }
            }
            Menu {
                Toggle("Use / rejected", isOn: $store.layers.marks)
                Toggle("Questions, notes and sets", isOn: $store.layers.notes)
                Toggle("Gaps: maybe related, empty spots", isOn: $store.layers.gaps)
                Toggle("Revisits: glow and fade", isOn: $store.layers.glow)
            } label: {
                pill { Text("Intent, time & gaps") }
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func kindBinding(_ k: SimKind) -> Binding<Bool> {
        Binding(
            get: { store.layers.kinds.contains(k.rawValue) },
            set: { on in
                if on { store.layers.kinds.insert(k.rawValue) } else { store.layers.kinds.remove(k.rawValue) }
            }
        )
    }

    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6) {
            content()
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium))
        }
        .font(.karst(size: 13))
        .foregroundStyle(theme.textPrimary)
        .padding(.horizontal, 14)
        .frame(height: StelloLayout.controlBarButtonSize)
        .background(theme.surfaceRaised.opacity(StelloLayout.controlBarGlassFillOpacity), in: Capsule())
        .overlay(Capsule().stroke(theme.border, lineWidth: 1))
        .glassEffect(.regular.interactive(), in: .capsule)
        .contentShape(Capsule())
    }
}


/// The library, reduced to the features the Gaps "+ Maybe" scan reads. Built once off
/// the main actor and rebuilt when the library's size changes (or after 5 minutes), so
/// the canvas never decodes the whole library while you pan or drag.
@Observable
final class CanvasMaybeLibrary {
    static let shared = CanvasMaybeLibrary()
    private(set) var entries: [MaybeEntry] = []
    private(set) var version = 0
    @ObservationIgnored private var builtCount = -1
    @ObservationIgnored private var builtAt: Date = .distantPast
    @ObservationIgnored private var building = false

    func refresh(context: ModelContext) async {
        guard !building else { return }
        let count = (try? context.fetchCount(FetchDescriptor<Item>())) ?? 0
        if count == builtCount, Date.now.timeIntervalSince(builtAt) < 300 { return }
        building = true
        defer { building = false }
        var d = FetchDescriptor<Item>()
        d.propertiesToFetch = [\.slug, \.title, \.domain, \.tagsJSON, \.kind, \.metadataJSON, \.sourceURL]
        let raws = ((try? context.fetch(d)) ?? []).map {
            MaybeRaw(slug: $0.slug, title: $0.title, domain: $0.domain, tagsJSON: $0.tagsJSON, kind: $0.kind,
                     metadataJSON: $0.metadataJSON, hasURL: !($0.sourceURL ?? "").isEmpty)
        }
        let built = await Task.detached(priority: .utility) { CanvasSimilarity.maybeEntries(raws) }.value
        entries = built
        builtCount = count
        builtAt = .now
        version += 1
    }
}
