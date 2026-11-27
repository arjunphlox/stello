import SwiftUI
import SwiftData
import os
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.modelContext) private var context
    @Environment(\.enrichmentCoordinator) private var enrichmentCoordinator

    @Query(sort: \Item.addedAt, order: .reverse) private var allItems: [Item]
    /// Newest-first launch window (nil in previews: the whole library).
    @Environment(LibraryWindow.self) private var libraryWindow: LibraryWindow?

    /// `libraryLimit`: load only the newest this-many items (nil = the whole library).
    init(libraryLimit: Int? = nil) {
        var descriptor = FetchDescriptor<Item>(sortBy: [SortDescriptor(\Item.addedAt, order: .reverse)])
        descriptor.fetchLimit = libraryLimit
        _allItems = Query(descriptor)
    }

    /// The header count is the whole library, even while only the newest weeks are loaded.
    private var libraryCount: Int { libraryWindow?.count(loaded: allItems.count) ?? allItems.count }

    @AppStorage("panel.widthFraction") private var panelWidthFraction: Double = 0.25
    @State private var selectedItem: Item?
    @State private var panelContent: SidePanelContent = .none
    @State private var selectedTagNames: Set<String> = []
    @State private var needsReviewOnly = false
    @State private var scrollOffset: CGFloat = 0
    @State private var isResizingPanel = false
    @State private var isDropTargeted = false
    @State private var showCompactSettings = false
    @State private var showCompactCapture = false
    private var canvasStore: CanvasStore { .shared }

    private var isRegular: Bool { hSizeClass == .regular }

    private var clampedPanelFraction: Double {
        min(0.5, max(0.25, panelWidthFraction))
    }

    var body: some View {
        Group {
            if isRegular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .background {
            theme.background.ignoresSafeArea()
        }
        .environment(\.font, .karst(.body))
        #if DEBUG
        .task { await ScaleCheck.run(context: context) }
        #endif
        .task {
            // Demo catalog only for in-memory (preview/screenshot) stores; the
            // synced library is prepared in StelloApp.init before any view renders.
            if SeedData.isInMemory(context) {
                await SeedData.prepareStore(in: context)
            }
            applyScreenshotLaunchState()
        }
        .task(priority: .background) {
            // Sample catalog stays out of the synced library too.
            if SeedData.isInMemory(context) {
                await OptacosImporter.importIfNeeded(in: context)
                // Also demo-only: on the real library it would refetch pages one at a
                // time every launch, drop covers still waiting to download, and sync
                // generated placeholders.
                await SeedData.backfillSeedCovers(in: context)
            }
            await enrichmentCoordinator.enrichPendingItems(context: context)
            if !WebInboxProcessor.isDisabled {
                await WebLibraryImporter.classifyPending(context: context, coordinator: enrichmentCoordinator)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: SyncBridge.webSavesQueued)) { _ in
            // New web saves arrived as plain links: give them kinds now, not next launch.
            guard !WebInboxProcessor.isDisabled else { return }
            Task(priority: .background) {
                await WebLibraryImporter.classifyPending(context: context, coordinator: enrichmentCoordinator)
            }
        }
        .onAppear {
            applyScreenshotLaunchState()
            scheduleScreenshotLaunchStateRetryIfNeeded()
        }
        .onChange(of: allItems.count) { _, _ in
            applyScreenshotLaunchState()
            libraryWindow?.refreshTotal(in: context)
        }
        // Filters count tags across the whole library: load the rest first.
        .onChange(of: panelContent) { _, content in
            if content == .filters { libraryWindow?.loadAll() }
        }
        .onChange(of: selectedTagNames) { _, names in
            if !names.isEmpty { libraryWindow?.loadAll() }
        }
        .onChange(of: needsReviewOnly) { _, on in
            if on { libraryWindow?.loadAll() }
        }
        .onChange(of: selectedItem) { oldValue, _ in
            // Viewing an item counts as reviewing it. This fires on every path that stops
            // viewing `oldValue`: switching selection to another item, closing the panel
            // (selectedItem → nil), opening a different tool panel while an item was open
            // (togglePanel nils selectedItem), and the iPhone sheet being dismissed (SwiftUI
            // nils the `.sheet(item:)` binding). Guarded on `needsReview` so already-reviewed
            // items don't take a gratuitous `updatedAt` bump.
            markPreviouslyViewedItemReviewed(oldValue)
        }
        .onDrop(of: DropImportService.windowDropTypes, isTargeted: $isDropTargeted) { providers in
            DropImportService.importAsNewItem(
                from: providers,
                context: context,
                coordinator: enrichmentCoordinator
            )
        }
    }

    /// Screenshot launch args — applied after seed I/O so items exist in the store.
    private func applyScreenshotLaunchState() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains(where: { $0.hasPrefix("-screenshot") }) else { return }

        let sortedItems = screenshotItems

        // Canvas screenshots: a throwaway local canvas with the first few items.
        if args.contains("-screenshotCanvas") || args.contains("-screenshotSplit") {
            canvasStore.viewMode = args.contains("-screenshotSplit") ? .split : .canvas
            // -screenshotLayer1: a tight 4 × 3 block so families form, with the first
            // card selected so its Layer 1 lines show (and -screenshotDetails opens ≡).
            let layer1 = args.contains("-screenshotLayer1")
            let count = layer1 ? 12 : 6
            if canvasStore.doc.cards.isEmpty, sortedItems.count >= count {
                for (i, item) in sortedItems.prefix(count).enumerated() {
                    let img = item.coverImage
                    let h = CanvasMetrics.cardHeight(imageWidth: img?.width, imageHeight: img?.height,
                                                     hasImage: !(img?.data?.isEmpty ?? true))
                    let col = layer1 ? i % 4 : i, row = layer1 ? i / 4 : 0
                    let x = CGFloat(col) * (CanvasMetrics.cardWidth + (layer1 ? 40 : 60)) + CanvasMetrics.cardWidth / 2
                    let y = CGFloat(row) * 420 + h / 2
                    canvasStore.add([item.slug], at: CGPoint(x: x, y: y), height: { _ in h })
                }
                let revisits = args.contains("-screenshotRevisits") && args.contains("-screenshotCleanStore")
                // Revisit shots keep nothing selected, so no card is dimmed.
                if layer1 && !revisits { canvasStore.selected = sortedItems.first?.slug }
                // -screenshotRevisits: card 2 opened 3× this week (glow), card 4 last
                // opened seven months ago (fade), and the first item off the canvas gets
                // card 9's tags so a group shows a "+ Maybe" pill. Throwaway store only.
                if revisits {
                    let shown = Array(sortedItems.prefix(count))
                    // Card 9 (row 3, first) starts the seed's Typography group.
                    if layer1, sortedItems.count > count, shown.count > 8 {
                        sortedItems[count].tagsJSON = shown[8].tagsJSON
                    }
                    if shown.count > 3 {
                        shown[1].lastOpenedAt = .now.addingTimeInterval(-86_400)
                        shown[1].openCount = 3
                        shown[3].lastOpenedAt = .now.addingTimeInterval(-210 * 86_400)
                        shown[3].openCount = 1
                    }
                    try? context.save()
                }
                canvasStore.cameraPlaced = false
            }
        }

        if args.contains("-screenshotPanelHalf") {
            panelWidthFraction = 0.5
        }

        if args.contains("-screenshotEnrichmentDemo") {
            selectedItem = SeedData.ensureEnrichmentDemo(in: context)
            panelContent = .itemDetail
        } else if isRegular, let kind = screenshotKind(from: args),
                  let match = sortedItems.first(where: { $0.kind == kind }) {
            selectedItem = match
            panelContent = .itemDetail
        } else if isRegular && args.contains("-screenshotItemPanel"), let first = sortedItems.first {
            selectedItem = first
            panelContent = .itemDetail
        } else if isRegular && args.contains("-screenshotItemPanelSecond") {
            let pick = sortedItems.indices.contains(1) ? sortedItems[1] : sortedItems.first
            selectedItem = pick
            panelContent = .itemDetail
        } else if isRegular && args.contains("-screenshotSelectionEdge") {
            // Third item lands in the rightmost column at typical 3-col iPad widths.
            let pick = sortedItems.indices.contains(2) ? sortedItems[2] : sortedItems.first
            selectedItem = pick
            panelContent = .itemDetail
        } else if isRegular && args.contains("-screenshotFiltersPanel") {
            panelContent = .filters
        } else if isRegular && args.contains("-screenshotImportPanel") {
            panelContent = .import
        } else if args.contains("-screenshotSettingsPanel")
                    || args.contains("-screenshotUserPrefs")
                    || args.contains("-screenshotAccentsDark")
                    || args.contains("-screenshotAccentsLight") {
            panelContent = .settings
        } else if isRegular && args.contains("-screenshotFiltersActive") {
            selectedTagNames = ["figma"]
        } else if !isRegular && args.contains("-screenshotDetailSheet"), let first = sortedItems.first {
            selectedItem = first
        } else if args.contains("-screenshotDropState") {
            isDropTargeted = true
        } else if args.contains("-screenshotAwaitingReview") {
            SeedData.ensureAwaitingReviewFixtures(in: context)
        } else if args.contains("-screenshotLocalLink") {
            ensureScreenshotLocalItem()
        }
    }

    /// Inserts a dropped-style local item (no URL) for screenshot fixtures.
    private func ensureScreenshotLocalItem() {
        let descriptor = FetchDescriptor<Item>(
            predicate: #Predicate<Item> { $0.slug == "screenshot-local-drop" }
        )
        if let existing = try? context.fetch(descriptor), let first = existing.first {
            selectedItem = first
            if isRegular { panelContent = .itemDetail }
            return
        }
        let item = Item(
            slug: "screenshot-local-drop",
            title: "Dropped Notes",
            sourceURL: nil,
            summary: "A local file drop with no source URL.",
            enrichmentStatus: "text_done"
        )
        context.insert(item)
        try? context.save()
        selectedItem = item
        if isRegular { panelContent = .itemDetail }
    }

    private func scheduleScreenshotLaunchStateRetryIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains(where: { $0.hasPrefix("-screenshot") }) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            applyScreenshotLaunchState()
        }
    }

    private func screenshotKind(from args: [String]) -> String? {
        guard let idx = args.firstIndex(of: "-screenshotKind"), idx + 1 < args.count else { return nil }
        let kind = args[idx + 1]
        return kind.isEmpty ? nil : kind
    }

    /// Prefer live `@Query` items; fall back to a direct fetch when hooks run before Query refreshes.
    private var screenshotItems: [Item] {
        if !allItems.isEmpty { return allItems }
        let descriptor = FetchDescriptor<Item>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Regular width (Mac / iPad): HStack panel column

    private var regularLayout: some View {
        GeometryReader { geo in
            // Edge gutter and card gap follow the window width, as on the web.
            let _ = StelloLayout.applyWidth(geo.size.width)
            let scrollTopInset = StelloLayout.headerOverlayScrollInset
            let headerScrollProgress = min(
                max(scrollOffset, 0) / StelloLayout.headerScrollFadeDistance,
                1
            )
            let panelOpen = panelContent != .none
            let panelWidth = panelOpen
                ? SidePanelContent.width(for: geo.size.width, fraction: clampedPanelFraction)
                : 0
            let contentWidth = geo.size.width - 2 * StelloLayout.windowInset
            let gridWidth = max(
                0,
                contentWidth - (panelOpen ? panelWidth + StelloLayout.columnGap : 0)
            )

            // Grid column absorbs the leading window inset so the timeline overlay can
            // render in the window-edge↔grid-edge gutter without being clipped.
            // Cards + header keep their exact baseline x via compensating padding/frames.
            let gridColumnWidth = gridWidth + StelloLayout.windowInset

            // Grid / Split / Canvas (web #94-#99). Split: grid on the left (46%),
            // the canvas as an inset panel on the right. Canvas: the grid leaves the
            // hierarchy entirely, so nothing renders behind it (web #98 lesson).
            let mode = canvasStore.viewMode
            let splitGridWidth = ((gridWidth - StelloLayout.columnGap) * 0.46).rounded()
            let shownGridWidth = mode == .split ? splitGridWidth : gridWidth
            let canvasFullBleed = mode == .canvas && !panelOpen

            HStack(alignment: .top, spacing: StelloLayout.columnGap) {
                if mode != .canvas {
                ZStack(alignment: .topTrailing) {
                    MasonryGridView(
                        embedInPanelLayout: true,
                        scrollTopInset: scrollTopInset,
                        scrollOffset: $scrollOffset,
                        catalogItems: allItems,
                        selectedTagNames: $selectedTagNames,
                        needsReviewOnly: $needsReviewOnly,
                        selectedItem: selectedItem,
                        panelContent: panelContent,
                        onCardTap: handleCardTap,
                        onFilters: { togglePanel(.filters) },
                        onImport: { togglePanel(.import) },
                        onSettings: { togglePanel(.settings) },
                        autoColumnsWidth: contentWidth
                    )
                    .frame(width: shownGridWidth + StelloLayout.windowInset)
                    .frame(maxHeight: .infinity)

                    headerOverlay(
                        itemCount: libraryCount,
                        headerScrollProgress: headerScrollProgress
                    )
                    .frame(width: shownGridWidth)
                }
                .frame(width: shownGridWidth + StelloLayout.windowInset)
                .frame(maxHeight: .infinity)
                // Horizontal outset keeps the selection ring visible on edge cards,
                // which sit flush with the header edges (ring slack, not card inset).
                .clipShape(HorizontalOutsetClip(outset: StelloLayout.gridRingClipOutset))
                .layoutPriority(0)
                }

                if mode == .split {
                    CanvasView(isPanel: true, onOpen: openFromCanvas)
                        .frame(width: max(0, gridWidth - StelloLayout.columnGap - splitGridWidth))
                        .padding(.top, StelloLayout.windowInset)
                        .padding(.bottom, StelloLayout.bottomEdgeGap())
                        .transition(.opacity)
                } else if mode == .canvas {
                    CanvasView(showsZoom: false, onOpen: openFromCanvas)
                        .overlay(alignment: .bottom) {
                            CanvasBottomBar(
                                onAdd: { togglePanel(.import) },
                                onSettings: { togglePanel(.settings) }
                            )
                            .padding(.leading, StelloLayout.windowInset)
                            .padding(.trailing, canvasFullBleed ? StelloLayout.windowInset : 0)
                            .padding(.bottom, StelloLayout.bottomEdgeGap())
                        }
                        // Canvas mode keeps the header as a small chip (web view-canvas).
                        .overlay(alignment: .topLeading) {
                            StelloHeaderView(itemCount: libraryCount, integratesMacTitleBar: isMac, chip: true)
                                .padding(.leading, StelloLayout.windowInset)
                                .padding(.top, StelloLayout.windowInset)
                        }
                        .frame(width: canvasFullBleed ? geo.size.width : gridColumnWidth)
                        .transition(.opacity)
                }

                if panelOpen {
                    SidePanelView(
                        content: panelContent,
                        selectedItem: selectedItem,
                        allItems: allItems,
                        selectedTagNames: $selectedTagNames,
                        needsReviewOnly: $needsReviewOnly,
                        onClose: closePanel,
                        onSelectItem: { item in
                            selectedItem = item
                            panelContent = .itemDetail
                        }
                    )
                    .frame(width: panelWidth)
                    .overlay(alignment: .leading) {
                        PanelResizeHandle(
                            fraction: $panelWidthFraction,
                            viewportWidth: geo.size.width,
                            isDragging: $isResizingPanel
                        )
                    }
                    .padding(.top, StelloLayout.windowInset)
                    // Same bottom gap as the control bar: max(gutter, safe area).
                    .padding(.bottom, StelloLayout.bottomEdgeGap())
                    .layoutPriority(1)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.trailing, canvasFullBleed ? 0 : StelloLayout.windowInset)
        }
        .clipped()
        #if os(macOS)
        .ignoresSafeArea(edges: .top)
        #else
        // iPad: the grid scrolls under the home indicator; the bar and panel keep
        // their own max(gutter, safe area) gap instead of gutter + safe area.
        .ignoresSafeArea(edges: .bottom)
        #endif
        .animation(.spring(duration: 0.28), value: panelContent)
        .animation(isResizingPanel ? nil : .default, value: clampedPanelFraction)
        .background(theme.background)
        #if os(macOS)
        .background(MacWindowConfigurator())
        #endif
    }

    // MARK: - Compact width (iPhone): sheet detail + tool sheets

    private var compactLayout: some View {
        NavigationStack {
            // Phones keep the 12pt gutter and card gap (web, under 500px).
            let _ = StelloLayout.applyWidth(0)
            // Phones: Grid or Canvas (Split falls back to Canvas, web #97).
            if canvasStore.viewMode == .grid {
                MasonryGridView(
                    catalogItems: allItems,
                    selectedTagNames: $selectedTagNames,
                    needsReviewOnly: $needsReviewOnly,
                    onCardTap: { selectedItem = $0 },
                    isDropTargeted: isDropTargeted
                )
            } else {
                // The canvas (and its dot grid) runs under the status bar, as the grid
                // does; the chip and the canvas's own top overlays sit below it.
                CanvasView(showsZoom: false, topInset: compactSafeTop, onOpen: openFromCanvas)
                    .ignoresSafeArea(edges: [.top, .bottom])
                    .overlay(alignment: .topLeading) {
                        StelloHeaderView(itemCount: libraryCount, chip: true)
                            .padding(.leading, StelloLayout.windowInset)
                            .padding(.top, compactSafeTop + StelloLayout.windowInset)
                            .ignoresSafeArea(edges: .top)
                    }
                    .overlay(alignment: .bottom) {
                        CanvasBottomBar(
                            compactPhone: true,
                            onAdd: { showCompactCapture = true },
                            onSettings: { showCompactSettings = true }
                        )
                        .padding(.horizontal, StelloLayout.windowInset)
                        .padding(.bottom, StelloLayout.bottomEdgeGap())
                        .ignoresSafeArea(edges: .bottom)
                    }
                    #if os(iOS)
                    .navigationBarHidden(true)
                    #endif
                    .sheet(isPresented: $showCompactSettings) {
                        SettingsView()
                            .environment(\.appTheme, theme)
                            .environment(UserProfileStore.shared)
                            .preferredColorScheme(theme.colorScheme)
                    }
                    .sheet(isPresented: $showCompactCapture) {
                        CaptureSheet()
                            .environment(\.appTheme, theme)
                            .preferredColorScheme(theme.colorScheme)
                    }
            }
        }
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        .containerBackground(.clear, for: .navigation)
        #endif
        .sheet(item: $selectedItem) { item in
            DetailView(item: item)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .environment(\.appTheme, theme)
                .environment(\.detailOpenItem, { selectedItem = $0 })
                .preferredColorScheme(theme.colorScheme)
        }
    }

    // MARK: - Panel actions (regular width)

    private func handleCardTap(_ item: Item) {
        if selectedItem?.persistentModelID == item.persistentModelID && panelContent == .itemDetail {
            closePanel()
        } else {
            selectedItem = item
            panelContent = .itemDetail
        }
    }

    /// Double-click / Open on a canvas card: the item panel, as in the grid.
    private func openFromCanvas(_ item: Item) {
        if isRegular {
            selectedItem = item
            panelContent = .itemDetail
        } else {
            selectedItem = item
        }
    }

    private func togglePanel(_ tool: SidePanelContent) {
        if panelContent == tool {
            closePanel()
        } else {
            selectedItem = nil
            panelContent = tool
        }
    }

    private func closePanel() {
        panelContent = .none
        selectedItem = nil
    }

    /// Clears the review nag for an item the user just stopped viewing (see the
    /// `onChange(of: selectedItem)` hook above). Idempotent — safe to call even when the
    /// item was already reviewed or `nil`.
    private func markPreviouslyViewedItemReviewed(_ item: Item?) {
        guard let item, item.needsReview else { return }
        try? AwaitingReviewFilter.markReviewed(for: item, context: context)
    }

    private var compactSafeTop: CGFloat {
        #if os(iOS)
        StelloLayout.windowSafeArea.top
        #else
        0
        #endif
    }

    private var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// Header confined to the content column — does not span over the side panel.
    private func headerOverlay(itemCount: Int, headerScrollProgress: CGFloat) -> some View {
        StelloHeaderView(
            itemCount: itemCount,
            integratesMacTitleBar: isMac,
            scrollProgress: headerScrollProgress,
            isDropTargeted: isDropTargeted
        )
        .padding(.top, StelloLayout.windowInset)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

// MARK: - Panel resize handle

private struct PanelResizeHandle: View {
    @Binding var fraction: Double
    let viewportWidth: CGFloat
    @Binding var isDragging: Bool

    @Environment(\.appTheme) private var theme
    @State private var dragStartFraction: Double?

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: 12)
                .contentShape(Rectangle())

            Capsule()
                .fill(theme.border.opacity(isDragging ? 0.95 : 0.55))
                .frame(width: 3, height: 36)
        }
        .frame(width: 8)
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragStartFraction == nil {
                        dragStartFraction = fraction
                        isDragging = true
                    }
                    let start = dragStartFraction ?? fraction
                    let delta = -value.translation.width / viewportWidth
                    fraction = min(0.5, max(0.25, start + delta))
                }
                .onEnded { _ in
                    dragStartFraction = nil
                    isDragging = false
                }
        )
        #if os(macOS)
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        #endif
    }
}

#Preview("iPhone", traits: .sizeThatFitsLayout) {
    ContentView()
        .modelContainer(SeedData.previewContainer)
        .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
        .preferredColorScheme(.dark)
}

#Preview("iPad") {
    ContentView()
        .modelContainer(SeedData.previewContainer)
        .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
        .preferredColorScheme(.dark)
        .frame(width: 1024, height: 820)
}

#Preview("Mac") {
    ContentView()
        .modelContainer(SeedData.previewContainer)
        .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
        .preferredColorScheme(.dark)
        .frame(width: 1280, height: 900)
}

// MARK: - Newest weeks first

/// Launch loads only the newest weeks, so the grid shows at once; the rest loads as
/// you scroll toward the end, or all at once when search, filters or the timeline
/// need the whole library. Every load of the library runs on the main thread
/// (SwiftData `@Query`), so a smaller first load is a faster first frame.
@MainActor @Observable
final class LibraryWindow {
    /// Items loaded; nil = the whole library.
    private(set) var limit: Int?
    /// Items in the whole library (for the header count while partly loaded).
    private(set) var total = 0

    static let launchWeeks = 4
    /// Never start with fewer than this many (a quiet month still fills the screen).
    static let minimumLaunch = 300
    /// Each step as you scroll near the end of what's loaded.
    static let growStep = 1_500
    /// Load the rest in one go when this little is left.
    static let finishSlack = 300

    init(limit: Int?, total: Int = 0) {
        self.limit = limit
        self.total = total
    }

    /// The launch window for this store: the last few weeks of saves, or everything
    /// when the library is small.
    static func atLaunch(in context: ModelContext) -> LibraryWindow {
        let total = (try? context.fetchCount(FetchDescriptor<Item>())) ?? 0
        let since = Calendar.current.date(byAdding: .day, value: -7 * launchWeeks, to: .now) ?? .distantPast
        let recent = (try? context.fetchCount(FetchDescriptor<Item>(predicate: #Predicate<Item> { $0.addedAt >= since }))) ?? 0
        let first = max(recent, minimumLaunch)
        return LibraryWindow(limit: first + finishSlack >= total ? nil : first, total: total)
    }

    func count(loaded: Int) -> Int { limit == nil ? loaded : max(total, loaded) }

    /// Called as the grid scrolls; grows the window when the built cards near its end.
    func gridReached(index: Int, loaded: Int) {
        guard let limit, loaded >= limit, index >= loaded - 200 else { return }
        let next = limit + Self.growStep
        self.limit = next + Self.finishSlack >= total ? nil : next
    }

    func loadAll() {
        if limit != nil { limit = nil }
    }

    func refreshTotal(in context: ModelContext) {
        guard limit != nil else { return }
        total = (try? context.fetchCount(FetchDescriptor<Item>())) ?? total
    }
}

/// Time from app start to the grid's first appearance, in the unified log
/// (`log show --predicate 'subsystem == "com.arjunphlox.Stello"'`), so launch speed
/// can be measured on a real library.
enum LaunchClock {
    static let start = ContinuousClock.now
    private static var reported = false
    private static let log = Logger(subsystem: "com.arjunphlox.Stello", category: "perf")

    static func gridAppeared(loaded: Int) {
        guard !reported else { return }
        reported = true
        let ms = (ContinuousClock.now - start).components
        let elapsed = Double(ms.seconds) * 1_000 + Double(ms.attoseconds) / 1e15
        log.notice("grid first appeared after \(elapsed, format: .fixed(precision: 0), privacy: .public) ms with \(loaded, privacy: .public) items loaded")
    }
}
