import SwiftUI
import SwiftData
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
    var onOpen: (Item) -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.modelContext) private var context

    @State private var index: [String: Item] = [:]
    @State private var dragSlug: String?
    @State private var dragDelta: CGSize = .zero
    @State private var panStart: CanvasCamera?
    @State private var pinchStart: CanvasCamera?
    @State private var dropTargeted = false
    @FocusState private var focused: Bool

    private var store: CanvasStore { .shared }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                dotGrid(store.camera)
                    .contentShape(Rectangle())
                    .gesture(panGesture)
                    .onTapGesture { store.selected = nil; focused = true }

                world(size: geo.size)

                if store.doc.cards.isEmpty {
                    emptyState.frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .coordinateSpace(name: "canvas")
            .simultaneousGesture(pinchGesture)
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
                        .padding(.top, StelloLayout.windowInset)
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
            .onChange(of: geo.size) { _, size in store.viewportSize = size }
            .onChange(of: store.cameraPlaced) { _, placed in if !placed { placeCamera(size: geo.size) } }
            .onChange(of: store.slugs) { _, _ in refreshIndex() }
            .onChange(of: store.focusSlug) { _, _ in focusIfAsked(size: geo.size) }
            .task { await store.pull(); refreshIndex() }
        }
        .background(isPanel ? theme.backgroundSubtle : theme.background)
        .clipShape(RoundedRectangle(cornerRadius: isPanel ? StelloLayout.panelCornerRadius : 0, style: .continuous))
        .overlay {
            if isPanel {
                RoundedRectangle(cornerRadius: StelloLayout.panelCornerRadius, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            }
        }
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

    private func world(size: CGSize) -> some View {
        let cam = store.camera
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
                    CanvasCardView(item: item, height: height(item),
                                   isSelected: store.selected == c.slug,
                                   counterScale: 1 / cam.k)
                        .shadow(color: .black.opacity(moving ? 0.28 : 0), radius: 12, y: 6)
                        .offset(x: c.x + (moving ? dragDelta.width : 0),
                                y: c.y + (moving ? dragDelta.height : 0))
                        .gesture(cardDrag(c.slug))
                        .onTapGesture(count: 2) { onOpen(item) }
                        .onTapGesture { store.selected = c.slug; focused = true }
                        .contextMenu {
                            Button("Open") { onOpen(item) }
                            Button("Remove from Canvas", role: .destructive) { store.remove([c.slug]) }
                        }
                        .zIndex(moving ? 1 : 0)
                }
            }
        }
        .scaleEffect(cam.k, anchor: .topLeading)
        .offset(x: cam.x, y: cam.y)
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
            }
            .onEnded { _ in
                if let c = store.doc.card(slug) {
                    store.move(slug, to: CGPoint(x: c.x + dragDelta.width, y: c.y + dragDelta.height))
                }
                dragSlug = nil
                dragDelta = .zero
            }
    }

    #if os(macOS)
    /// Trackpad: two-finger scroll pans. Mouse wheel pans too; ⌘ or ⌃ + wheel zooms
    /// at the pointer (pinch comes through `MagnifyGesture`).
    private func handleScroll(_ e: NSEvent, at p: CGPoint) {
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
        var cam = store.camera
        edit(&cam)
        withAnimation(.smooth(duration: 0.22)) { store.camera = cam }
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
        if next.count != index.count || !missing.isEmpty { index = next }
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
