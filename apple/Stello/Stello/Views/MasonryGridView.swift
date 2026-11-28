import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

// MARK: - Scroll offset tracking

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Rectangle clip extended horizontally past the view bounds, so the 4pt outset
/// selection ring on edge cards survives the grid's clip while vertical scroll
/// containment stays exact.
struct HorizontalOutsetClip: Shape {
    var outset: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(rect.insetBy(dx: -outset, dy: 0))
    }
}

private struct ScrollContentBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MasonryGridView: View {
    /// When true, header lives in `ContentView` and card taps call `onCardTap`.
    var embedInPanelLayout: Bool = false
    /// Top scroll inset when header floats over the grid (regular Mac/iPad layout).
    var scrollTopInset: CGFloat = 0
    /// Bound scroll offset for header transparency (regular Mac/iPad layout).
    var scrollOffset: Binding<CGFloat>? = nil
    @Binding var selectedTagNames: Set<String>
    @Binding var needsReviewOnly: Bool
    var selectedItem: Item? = nil
    var panelContent: SidePanelContent = .none
    var onCardTap: ((Item) -> Void)? = nil

    /// iPhone callbacks — open tool sheets from header buttons.
    var onFilters: (() -> Void)? = nil
    var onImport: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil
    /// Window drag hover — drives compact header drop-state UI.
    var isDropTargeted: Bool = false
    /// When set, avoids a second `@Query` in the grid (pass from `ContentView`).
    var catalogItems: [Item]? = nil
    /// Width the automatic column count is picked from: the grid's width with no
    /// side panel and no Split. Opening the detail panel or the split canvas then
    /// narrows the cards but keeps the columns; only a pinch changes them.
    var autoColumnsWidth: CGFloat? = nil

    init(
        embedInPanelLayout: Bool = false,
        scrollTopInset: CGFloat = 0,
        scrollOffset: Binding<CGFloat>? = nil,
        catalogItems: [Item]? = nil,
        selectedTagNames: Binding<Set<String>> = .constant([]),
        needsReviewOnly: Binding<Bool> = .constant(false),
        selectedItem: Item? = nil,
        panelContent: SidePanelContent = .none,
        onCardTap: ((Item) -> Void)? = nil,
        onFilters: (() -> Void)? = nil,
        onImport: (() -> Void)? = nil,
        onSettings: (() -> Void)? = nil,
        isDropTargeted: Bool = false,
        autoColumnsWidth: CGFloat? = nil
    ) {
        self.autoColumnsWidth = autoColumnsWidth
        self.embedInPanelLayout = embedInPanelLayout
        self.scrollTopInset = scrollTopInset
        self.scrollOffset = scrollOffset
        _selectedTagNames = selectedTagNames
        _needsReviewOnly = needsReviewOnly
        self.selectedItem = selectedItem
        self.panelContent = panelContent
        self.onCardTap = onCardTap
        self.onFilters = onFilters
        self.onImport = onImport
        self.onSettings = onSettings
        self.isDropTargeted = isDropTargeted
        self.catalogItems = catalogItems
        // The library comes from ContentView's query: don't run (and keep
        // re-running on every save) a second full fetch here.
        if catalogItems != nil {
            _queriedItems = Query(filter: #Predicate<Item> { _ in false })
        }
    }

    @Query(sort: \Item.addedAt, order: .reverse) private var queriedItems: [Item]
    @Environment(\.modelContext) private var context
    @Environment(LibraryWindow.self) private var libraryWindow: LibraryWindow?
    @Environment(\.appTheme) private var theme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var allItems: [Item] { catalogItems ?? queriedItems }
    private var isCompactPhone: Bool { !embedInPanelLayout && horizontalSizeClass == .compact }

    @State private var searchText = ""
    @State private var showFilterSheet = false
    @State private var showSettings = false
    @State private var showCapture = false
    @State private var screenshotDetailItem: Item?

    /// 0 = auto (width-based); 1…12 = user pinch-zoom column count.
    @AppStorage("stello.gridColumns") private var gridColumns: Int = 0
    @State private var pinchBaseColumns: Int?
    @State private var gridContainerWidth: CGFloat = 375

    @State private var weekAnchorYs: [String: CGFloat] = [:]
    @State private var weekBottomYs: [String: CGFloat] = [:]
    @State private var scrollContentBottom: CGFloat = 0
    @State private var cachedContentWeekRanges: [String: (top: CGFloat, bottom: CGFloat)] = [:]
    @State private var activeWeekKey: String?
    @State private var interactionWeekKey: String?
    @State private var selectedWeekKey: String?
    /// Local scroll offset when header is owned here (compact iPhone layout).
    @State private var compactScrollOffset: CGFloat = 0
    @State private var cachedTagFilteredItems: [Item] = []
    @State private var cachedDisplayItems: [Item] = []
    @State private var cachedTimelineWeekGroups: [WeekGroup] = []
    @State private var cachedDisplayWeekKeys: [String] = []
    @State private var filterCacheToken: UInt = 0
    /// Frames for every card in `displayItems`. Only cards near the viewport are built.
    @State private var gridModel = VirtualMasonryModel()
    /// Grid selection for bulk actions (Mac drag box, ⌘/⇧-click; touch: Select in the menu).
    @State private var selection = GridSelection.shared
    #if os(macOS)
    @State private var marquee: MarqueeDrag?
    #endif
    /// A drag box just ended: the click that ends it isn't a tap on a card.
    @State private var ignoreTapsUntil: Date = .distantPast
    @State private var gridModelVersion: UInt = 0
    /// The grid's top edge in the scroll view's coordinate space.
    @State private var gridViewportTop: CGFloat = 0
    /// Scroll position in `visibleWindowStep`s: cards are only rebuilt when this changes.
    @State private var visibleWindowIndex = 0

    /// Ring headroom for the 4pt outset selection ring. Applied vertically inside the
    /// card stack; horizontally it lives in the HorizontalOutsetClip boundaries so the
    /// outer card edges stay flush with the header edges.
    private static let selectionOutlineInset: CGFloat = StelloLayout.gridRingClipOutset
    /// Deadband past a column boundary before stepping to the next count (prevents flicker).
    private static let columnHysteresis: Double = 0.35
    /// How far the grid scrolls before the set of built cards is refreshed.
    private static let visibleWindowStep: CGFloat = 300
    /// The web's masonry gap for this width (`StelloLayout.cardGap`).
    private static var gridSpacing: CGFloat { StelloLayout.cardGap }
    /// Minimum scroll delta before updating header / week-spy state.
    private static let scrollOffsetDeadband: CGFloat = 10

    private var effectiveForcedColumns: Int? {
        gridColumns == 0 ? nil : min(max(gridColumns, 1), 12)
    }

    private func resolvedColumnCount(for width: CGFloat) -> Int {
        MasonryLayout(forcedColumns: effectiveForcedColumns).resolvedColumnCount(for: autoColumnsWidth ?? width)
    }

    /// Card width in points, so covers decode at the size they're shown.
    private var cardColumnWidth: CGFloat {
        let columns = CGFloat(resolvedColumnCount(for: gridContainerWidth))
        guard gridContainerWidth > 0, columns > 0 else { return 0 }
        return (gridContainerWidth - Self.gridSpacing * (columns - 1)) / columns
    }

    private var tagFilteredItems: [Item] { cachedTagFilteredItems }
    private var displayItems: [Item] { cachedDisplayItems }
    private var timelineWeekGroups: [WeekGroup] { cachedTimelineWeekGroups }

    private func refreshFilterCaches() {
        #if DEBUG
        let refreshStart = Date()
        defer {
            if ScaleCheck.isEnabled, allItems.count >= ScaleCheck.itemCount {
                ScaleCheck.gridRefreshSeconds = Date().timeIntervalSince(refreshStart)
            }
        }
        #endif
        let tagFiltered = ItemFilter.apply(
            allItems,
            searchText: searchText,
            selectedTagNames: selectedTagNames,
            needsReviewOnly: needsReviewOnly
        )
        cachedTagFilteredItems = tagFiltered
        if let selectedWeekKey {
            cachedDisplayItems = tagFiltered.filter { WeekGroup.isoWeekKey(for: $0.addedAt) == selectedWeekKey }
        } else {
            cachedDisplayItems = tagFiltered
        }
        cachedTimelineWeekGroups = WeekGroup.makeGroups(from: tagFiltered)

        cachedDisplayWeekKeys = cachedDisplayItems.map { WeekGroup.isoWeekKey(for: $0.addedAt) }
        filterCacheToken &+= 1
        selection.gridChanged(cachedDisplayItems)
        rebuildGridModel()
    }

    private func rebuildGridModel() {
        gridModel = VirtualMasonryModel(
            aspects: cachedDisplayItems.map(\.coverAspect),
            weekKeys: cachedDisplayWeekKeys,
            width: gridContainerWidth,
            columnCount: resolvedColumnCount(for: gridContainerWidth),
            spacing: Self.gridSpacing
        )
        gridModelVersion &+= 1
        publishWeekAnchors()
    }

    /// Feeds the timeline from computed frames, because offscreen cards don't exist.
    private func publishWeekAnchors() {
        let top = gridViewportTop
        weekAnchorYs = gridModel.weekTops.mapValues { $0 + top }
        weekBottomYs = gridModel.weekBottoms.mapValues { $0 + top }
        cacheContentWeekRangesIfNeeded()
    }

    private func applyGridViewportTop(_ top: CGFloat) {
        guard top != gridViewportTop else { return }
        gridViewportTop = top
        publishWeekAnchors()
        updateActiveWeekKey()
    }

    private func updateVisibleWindow(scrollOffset: CGFloat) {
        let window = Int(max(0, scrollOffset) / Self.visibleWindowStep)
        guard window != visibleWindowIndex else { return }
        visibleWindowIndex = window
        reportScrollDepth()
    }

    /// Lets the launch window load more as the built cards near the end of what's
    /// loaded (search and filters load the whole library on their own).
    private func reportScrollDepth() {
        guard let libraryWindow, libraryWindow.limit != nil else { return }
        let windowTop = CGFloat(visibleWindowIndex) * Self.visibleWindowStep
        let lookahead: CGFloat = 4_000
        let deepest = gridModel.visibleIndices(minY: windowTop, maxY: windowTop + lookahead).max() ?? 0
        let reachedEnd = windowTop + lookahead >= gridModel.contentHeight
        libraryWindow.gridReached(index: reachedEnd ? allItems.count : deepest, loaded: allItems.count)
    }

    /// The built cards: one viewport of overscan either side of the visible window.
    private func placedCards(viewportHeight: CGFloat) -> [PlacedCard] {
        let windowTop = CGFloat(visibleWindowIndex) * Self.visibleWindowStep
        let indices = gridModel.visibleIndices(
            minY: windowTop - viewportHeight,
            maxY: windowTop + Self.visibleWindowStep + viewportHeight * 2
        )
        return indices.compactMap { index in
            guard index < displayItems.count else { return nil }
            return PlacedCard(item: displayItems[index], frame: gridModel.frames[index])
        }
    }

    private func applyScrollOffset(_ offset: CGFloat) {
        if let scrollOffset {
            let current = scrollOffset.wrappedValue
            guard abs(offset - current) >= Self.scrollOffsetDeadband else { return }
            scrollOffset.wrappedValue = offset
        } else {
            guard abs(offset - compactScrollOffset) >= Self.scrollOffsetDeadband else { return }
            compactScrollOffset = offset
        }
        updateActiveWeekKey()
    }

    private var effectiveScrollOffset: CGFloat {
        scrollOffset?.wrappedValue ?? compactScrollOffset
    }

    private var headerScrollProgress: CGFloat {
        min(max(effectiveScrollOffset, 0) / StelloLayout.headerScrollFadeDistance, 1)
    }

    private static func compactSafeTop(_ viewport: GeometryProxy) -> CGFloat {
        #if os(iOS)
        StelloLayout.windowSafeArea.top
        #else
        viewport.safeAreaInsets.top
        #endif
    }

    private func compactScrollTopInset(safeTop: CGFloat) -> CGFloat {
        StelloLayout.compactHeaderScrollInset(safeTop: safeTop)
    }

    var body: some View {
        gridWithTimeline
        .frame(maxHeight: .infinity)
        // Horizontal outset keeps the selection ring visible on edge cards now that
        // the card stack sits flush with the header edges (see gridScrollContent).
        .clipShape(HorizontalOutsetClip(outset: Self.selectionOutlineInset))
        .background {
            theme.background.ignoresSafeArea()
        }
        #if os(iOS)
        .navigationBarHidden(true)
        // Compact: the grid runs edge to edge (top and bottom) and places the header
        // and the control bar itself from the window's safe area. Respecting the top
        // safe area here as well put the header a second safe area lower (iPhone
        // showed ~136pt above the header instead of 62 + 12).
        .ignoresSafeArea(edges: embedInPanelLayout ? [] : [.top, .bottom])
        #endif
        .sheet(isPresented: $showFilterSheet) {
            TagFilterSheet(allItems: allItems, selectedTagNames: $selectedTagNames, needsReviewOnly: $needsReviewOnly)
                .environment(\.appTheme, theme)
                .preferredColorScheme(theme.colorScheme)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(\.appTheme, theme)
                .environment(UserProfileStore.shared)
                .preferredColorScheme(theme.colorScheme)
        }
        .task {
            refreshFilterCaches()
            openScreenshotDetailIfNeeded()
            if !embedInPanelLayout && ProcessInfo.processInfo.arguments.contains("-screenshotFilterSheet") {
                showFilterSheet = true
            }
            // The sheet is the compact (iPhone) Settings; wider layouts show the side
            // panel, so -screenshotSettingsPanel there must not open both.
            let args = ProcessInfo.processInfo.arguments
            let wantsSettings = args.contains(where: {
                ["-screenshotSettings", "-screenshotUserPrefs", "-screenshotSettingsPanel",
                 "-screenshotAccentsDark", "-screenshotAccentsLight"].contains($0)
            })
            if wantsSettings && !(embedInPanelLayout && args.contains("-screenshotSettingsPanel")) {
                showSettings = true
            }
        }
        .onAppear { refreshFilterCaches() }
        .onChange(of: allItems.count) { _, _ in
            refreshFilterCaches()
            openScreenshotDetailIfNeeded()
        }
        .onChange(of: searchText) { _, text in
            if !text.isEmpty { libraryWindow?.loadAll() }
            refreshFilterCaches()
        }
        .onChange(of: selectedTagNames) { _, _ in refreshFilterCaches() }
        .onChange(of: selectedWeekKey) { _, key in
            if key != nil { libraryWindow?.loadAll() }
            refreshFilterCaches()
        }
        // Search, filters and the timeline work on the whole library.
        .onChange(of: showFilterSheet) { _, open in
            if open { libraryWindow?.loadAll() }
        }
        .onChange(of: interactionWeekKey) { _, key in
            if key != nil { libraryWindow?.loadAll() }
        }
        .onChange(of: needsReviewOnly) { _, _ in refreshFilterCaches() }
        // Reviewing an item flips needsReview at the store layer; the cached filter results
        // must follow so a just-reviewed card leaves the "Needs review"-filtered grid live.
        .background {
            LibraryChangeWatcher(
                items: allItems,
                onReviewChange: { if needsReviewOnly { refreshFilterCaches() } },
                onCoverChange: { rebuildGridModel() }
            )
            .equatable()
        }
        .onChange(of: gridContainerWidth) { _, _ in rebuildGridModel() }
        .onChange(of: gridColumns) { _, _ in rebuildGridModel() }
        .onChange(of: autoColumnsWidth) { old, new in
            let layout = MasonryLayout(forcedColumns: effectiveForcedColumns)
            if layout.resolvedColumnCount(for: old ?? gridContainerWidth)
                != layout.resolvedColumnCount(for: new ?? gridContainerWidth) {
                rebuildGridModel()
            }
        }
        .onChange(of: weekAnchorYs) { _, _ in
            cacheContentWeekRangesIfNeeded()
        }
        .onChange(of: weekBottomYs) { _, _ in
            cacheContentWeekRangesIfNeeded()
        }
        .sheet(isPresented: tagEditorBinding) {
            BulkTagEditor(selection: selection)
                .environment(\.appTheme, theme)
                .preferredColorScheme(theme.colorScheme)
                #if os(iOS)
                .presentationDetents([.medium, .large])
                #endif
        }
        .confirmationDialog(deleteTitle, isPresented: deleteBinding, titleVisibility: .visible) {
            Button(selection.count == 1 ? "Delete 1 Item" : "Delete \(selection.count) Items", role: .destructive) {
                let n = BulkActions.delete(selection.items, context: context)
                selection.clear()
                selection.say(n == 1 ? "Deleted 1 item" : "Deleted \(n) items")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
        .onAppear { selection.loadAll = { [weak window = libraryWindow] in window?.loadAll() } }
        .sheet(isPresented: $showCapture) {
            CaptureSheet()
                .environment(\.appTheme, theme)
                .preferredColorScheme(theme.colorScheme)
        }
        .navigationDestination(item: $screenshotDetailItem) { DetailView(item: $0) }
    }

    private var gridWithTimeline: some View {
        ScrollViewReader { scrollProxy in
            GeometryReader { viewport in
                // The window's top inset (Dynamic Island / status bar), read from the
                // window so a hidden navigation bar can't add to it.
                let safeTop = embedInPanelLayout ? 0 : Self.compactSafeTop(viewport)
                let compactScrollInset = embedInPanelLayout
                    ? scrollTopInset
                    : compactScrollTopInset(safeTop: safeTop)

                ZStack(alignment: .top) {
                    ScrollView {
                        gridScrollContent(topInset: compactScrollInset, viewportHeight: viewport.size.height)
                            .frame(width: viewport.size.width, alignment: .leading)
                    }
                    // The scroll clip would cut the selection ring at the flush card
                    // edges; the enclosing HorizontalOutsetClip shapes contain scrolled
                    // content instead (exact vertically, +ring slack horizontally).
                    .scrollClipDisabled()
                    #if os(iOS)
                    .scrollContentBackground(.hidden)
                    #endif
                    .frame(width: viewport.size.width, height: viewport.size.height)
                    .coordinateSpace(name: "stelloScroll")
                    .onPreferenceChange(ScrollOffsetKey.self) { offset in
                        applyScrollOffset(offset)
                    }
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.y + geometry.contentInsets.top
                    } action: { _, offset in
                        updateVisibleWindow(scrollOffset: offset)
                    }
                    .onPreferenceChange(ScrollContentBottomKey.self) { bottom in
                        scrollContentBottom = bottom
                        cacheContentWeekRangesIfNeeded()
                    }
                    .simultaneousGesture(gridPinchGesture)
                    .overlay(alignment: .leading) {
                        if !timelineWeekGroups.isEmpty {
                            TimelineOverlay(
                                weekGroups: timelineWeekGroups,
                                weekBarLayouts: timelineBarLayouts(scrollTopInset: compactScrollInset),
                                activeWeekKey: activeWeekKey,
                                interactionWeekKey: interactionWeekKey,
                                selectedWeekKey: selectedWeekKey,
                                onWeekFilterToggled: toggleWeekFilter,
                                onInteractionChanged: { interactionWeekKey = $0 }
                            )
                            // Bars centered in the 12pt window-edge↔grid-edge margin on all
                            // platforms — cards now sit flush at windowInset (header-aligned),
                            // so the old compact windowInset offset would overlap edge cards.
                            .padding(
                                .leading,
                                (StelloLayout.windowInset - TimelineMetrics.barWidth) / 2
                            )
                            .padding(.top, compactScrollInset)
                            .allowsHitTesting(true)
                        }
                    }

                    if !embedInPanelLayout {
                        compactHeaderOverlay(safeTop: safeTop)
                    }
                }
                .overlay(alignment: .bottom) {
                    bottomControlOverlay(safeBottom: viewport.safeAreaInsets.bottom)
                }
                // The grid's width is the viewport less the paddings in `gridScrollContent`.
                .onChange(of: viewport.size.width, initial: true) { _, width in
                    gridContainerWidth = width - StelloLayout.windowInset
                        - (embedInPanelLayout ? 0 : StelloLayout.windowInset)
                }
            }
            .frame(maxHeight: .infinity)
            .clipShape(HorizontalOutsetClip(outset: Self.selectionOutlineInset))
            .onAppear {
                #if DEBUG
                if ScaleCheck.isEnabled {
                    ScaleCheck.scrollToWeek = { scrollProxy.scrollTo($0, anchor: .top) }
                    ScaleCheck.weekKeys = { timelineWeekGroups.map(\.key) }
                }
                #endif
                scrollForScreenshotIfNeeded(using: scrollProxy)
                LaunchClock.gridAppeared(loaded: allItems.count)
                updateActiveWeekKey()
                applyScreenshotTimelineHoverIfNeeded()
                applyScreenshotWeekFilterIfNeeded()
            }
        }
    }

    private func compactHeaderOverlay(safeTop: CGFloat) -> some View {
        StelloHeaderView(
            itemCount: libraryWindow?.count(loaded: allItems.count) ?? allItems.count,
            scrollProgress: headerScrollProgress,
            isDropTargeted: isDropTargeted
        )
        .padding(.horizontal, StelloLayout.windowInset)
        .padding(.top, safeTop + StelloLayout.compactHeaderBelowSafeAreaGap)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func bottomControlOverlay(safeBottom: CGFloat) -> some View {
        let screenshotHoverFilters = ProcessInfo.processInfo.arguments.contains("-screenshotHeaderHover")
        // One gap per edge: max(gutter, safe area), never summed (web --gap-bottom).
        let bottomPadding = StelloLayout.bottomEdgeGap(proxySafeBottom: safeBottom)

        return Group {
            if selection.isActive {
                GridSelectionBar(selection: selection, compactPhone: isCompactPhone)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
            } else {
                bottomBar(screenshotHoverFilters: screenshotHoverFilters)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.2), value: selection.isActive)
        // Embed: leading pad compensates the gutter now included in the grid column
        // (see gridScrollContent); trailing sits flush with the column. iPhone: the
        // grid's own 12pt gutter on both sides, so the bar lines up with the cards.
        .padding(.leading, StelloLayout.windowInset)
        .padding(.trailing, embedInPanelLayout ? 0 : StelloLayout.windowInset)
        .padding(.bottom, bottomPadding)
        .frame(maxWidth: .infinity, alignment: .bottom)
    }

    private func bottomBar(screenshotHoverFilters: Bool) -> some View {
        GridBottomControlBar(
            searchText: $searchText,
            hasActiveFilters: !selectedTagNames.isEmpty || selectedWeekKey != nil || needsReviewOnly,
            isFilterPanelOpen: panelContent == .filters,
            isImportPanelOpen: panelContent == .import,
            isSettingsPanelOpen: panelContent == .settings,
            forceFilterHover: screenshotHoverFilters,
            compactPhone: isCompactPhone,
            onAdd: { onImport?() ?? (showCapture = true) },
            onFilter: { onFilters?() ?? (showFilterSheet = true) },
            onSettings: { onSettings?() ?? (showSettings = true) }
        )
    }

    private func gridScrollContent(topInset: CGFloat, viewportHeight: CGFloat) -> some View {
        VStack(spacing: 12) {
            scrollOffsetProbe

            if !selectedTagNames.isEmpty || selectedWeekKey != nil || needsReviewOnly {
                filterPillsRow
            }

            VirtualMasonryCards(
                placed: placedCards(viewportHeight: viewportHeight),
                token: VirtualMasonryCards.Token(
                    window: visibleWindowIndex,
                    viewportHeight: viewportHeight,
                    modelVersion: gridModelVersion,
                    filterVersion: filterCacheToken,
                    selectedItem: panelContent == .itemDetail ? selectedItem?.persistentModelID : nil,
                    selectionVersion: selection.version
                ),
                card: { card(for: $0) }
            )
            .equatable()
            .frame(height: gridModel.contentHeight, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            #if os(macOS)
            .overlay(alignment: .topLeading) { marqueeBox }
            .contentShape(Rectangle())
            .simultaneousGesture(marqueeGesture)
            #endif
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named("stelloScroll")).minY
            } action: { top in
                applyGridViewportTop(top)
            }
            .background(alignment: .topLeading) {
                if ProcessInfo.processInfo.arguments.contains("-screenshotScrolledHeader")
                    || ProcessInfo.processInfo.arguments.contains("-scaleCheck") {
                    ForEach(Array(gridModel.weekTops.keys), id: \.self) { key in
                        Color.clear
                            .frame(height: 1)
                            .offset(y: gridModel.weekTops[key] ?? 0)
                            .id(key)
                    }
                }
            }
            .padding(Self.selectionOutlineInset)
            // Cancel the outline inset horizontally so the outer card edges sit flush
            // with the header's left/right edges; the ring's horizontal slack lives in
            // the HorizontalOutsetClip boundaries instead of inside the card stack.
            .padding(.horizontal, -Self.selectionOutlineInset)

            scrollContentBottomProbe
        }
        // Embed (Mac/iPad): the grid column includes the leading window gutter, so the
        // card stack pads leading by the inset to keep cards at the baseline x while the
        // timeline overlay occupies the gutter. Compact (iPhone): unchanged 12pt both sides.
        .padding(.leading, StelloLayout.windowInset)
        .padding(.trailing, embedInPanelLayout ? 0 : StelloLayout.windowInset)
        .padding(.top, topInset)
        .padding(
            .bottom,
            StelloLayout.floatingSearchScrollInset(
                compactPhone: isCompactPhone,
                bottomGap: StelloLayout.bottomEdgeGap()
            )
        )
    }

    /// Reports the scroll content's bottom edge in `"stelloScroll"` viewport space.
    private var scrollContentBottomProbe: some View {
        Color.clear
            .frame(height: 1)
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollContentBottomKey.self,
                        value: geo.frame(in: .named("stelloScroll")).maxY
                    )
                }
            }
    }

    /// Invisible probe at scroll content top — reports how far content has scrolled.
    private var scrollOffsetProbe: some View {
        GeometryReader { geo in
            Color.clear
                .preference(
                    key: ScrollOffsetKey.self,
                    value: max(0, -geo.frame(in: .named("stelloScroll")).minY)
                )
        }
        .frame(height: 0)
    }

    /// Photos-style pinch: spread → fewer columns, pinch → more columns (1…12).
    /// Column count steps live during the gesture; masonry re-flows with smooth animation.
    private var gridPinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchBaseColumns == nil {
                    let base = resolvedColumnCount(for: gridContainerWidth)
                    pinchBaseColumns = base
                    if gridColumns == 0 {
                        gridColumns = base
                    }
                }
                guard let baseCols = pinchBaseColumns else { return }
                let currentCols = gridColumns
                let target = pinchTargetColumns(
                    baseCols: baseCols,
                    magnification: value.magnification,
                    currentCols: currentCols
                )
                if target != currentCols {
                    withAnimation(.smooth(duration: 0.22)) {
                        gridColumns = target
                    }
                }
            }
            .onEnded { _ in
                pinchBaseColumns = nil
            }
    }

    /// Maps pinch magnification to a column count with hysteresis so counts don't oscillate at boundaries.
    private func pinchTargetColumns(baseCols: Int, magnification: CGFloat, currentCols: Int) -> Int {
        let continuous = Double(baseCols) / Double(magnification)
        let ideal = Int(round(continuous))
        let clamped = min(max(ideal, 1), 12)

        if clamped == currentCols { return currentCols }

        if clamped > currentCols {
            guard continuous >= Double(currentCols) + 0.5 + Self.columnHysteresis else { return currentCols }
        } else {
            guard continuous <= Double(currentCols) - 0.5 - Self.columnHysteresis else { return currentCols }
        }
        return clamped
    }

    @ViewBuilder
    private func card(for item: Item) -> some View {
        if let onCardTap {
            Button {
                handleTap(item, open: onCardTap)
            } label: {
                ItemCardView(
                    item: item,
                    isSelected: selectedItem?.persistentModelID == item.persistentModelID
                        && panelContent == .itemDetail,
                    resolvedColumns: resolvedColumnCount(for: gridContainerWidth),
                    columnWidth: cardColumnWidth,
                    onOpen: { onCardTap(item) }
                )
                .overlay { GridSelectionMark(isSelected: selection.contains(item)) }
                .overlay(alignment: .topLeading) {
                    // Split view: a dot on cards already on the canvas (web `.on-canvas`).
                    if CanvasStore.shared.viewMode == .split, CanvasStore.shared.doc.contains(item.slug) {
                        Circle()
                            .fill(theme.accentColor)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 2))
                            .padding(10)
                            .allowsHitTesting(false)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selection.contains(item) ? .isSelected : [])
            // Mac / iPad: drag a card onto the canvas (Split view). Its own type, so
            // the window's file/text drop import ignores it. With no canvas showing, a
            // drag on the Mac draws a selection box instead.
            .modifier(CanvasCardDrag(item: item, enabled: canvasDragEnabled, theme: theme))
        } else {
            NavigationLink(value: item) {
                ItemCardView(
                    item: item,
                    resolvedColumns: resolvedColumnCount(for: gridContainerWidth),
                    columnWidth: cardColumnWidth
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Selection

    private var canvasDragEnabled: Bool {
        #if os(macOS)
        CanvasStore.shared.viewMode == .split
        #else
        true
        #endif
    }

    /// A tap or click on a card: ⌘ adds or removes it, ⇧ selects a run of cards; while
    /// selecting, a plain tap adds or removes too. Otherwise it opens the item.
    private func handleTap(_ item: Item, open: (Item) -> Void) {
        #if os(macOS)
        if marquee != nil { return }
        #endif
        if Date() < ignoreTapsUntil { return }
        #if os(macOS)
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift), selection.isActive { selection.extend(to: item); return }
        if flags.contains(.command) || flags.contains(.shift) { selection.toggle(item); return }
        #endif
        if selection.isActive {
            selection.toggle(item)
            return
        }
        open(item)
    }

    private var tagEditorBinding: Binding<Bool> {
        Binding(get: { selection.showTagEditor }, set: { selection.showTagEditor = $0 })
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { selection.confirmDelete }, set: { selection.confirmDelete = $0 })
    }

    private var deleteTitle: String {
        selection.count == 1 ? "Delete 1 item?" : "Delete \(selection.count) items?"
    }

    private var deleteMessage: String {
        FolderSources.shared.folders.isEmpty
            ? "You can’t undo this."
            : "Their files move to the .trash folder inside your Stello folder."
    }

    #if os(macOS)
    /// Drag on the grid draws a box; every card it touches is selected. ⇧ or ⌘ held at
    /// the start adds to what's selected (⌘ flips cards already in it).
    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { value in
                let start = value.startLocation
                if marquee == nil {
                    let flags = NSEvent.modifierFlags
                    let onCard = gridModel.visibleIndices(minY: start.y, maxY: start.y)
                        .contains { gridModel.frames[$0].contains(start) }
                    // Split view: dragging a card carries it to the canvas.
                    let ignore = canvasDragEnabled && onCard
                    let keep = flags.contains(.shift) || flags.contains(.command)
                    marquee = MarqueeDrag(
                        base: keep ? selection.ids : [], flips: flags.contains(.command),
                        ignored: ignore, rect: .zero)
                }
                guard var drag = marquee, !drag.ignored else { return }
                let loc = value.location
                drag.rect = CGRect(
                    x: min(start.x, loc.x), y: min(start.y, loc.y),
                    width: abs(loc.x - start.x), height: abs(loc.y - start.y))
                marquee = drag
                var next = drag.base
                for index in gridModel.visibleIndices(minY: drag.rect.minY, maxY: drag.rect.maxY)
                where index < displayItems.count && gridModel.frames[index].intersects(drag.rect) {
                    let id = displayItems[index].id
                    if drag.flips && drag.base.contains(id) { next.remove(id) } else { next.insert(id) }
                }
                selection.set(next)
            }
            .onEnded { _ in
                if marquee?.ignored == false { ignoreTapsUntil = Date().addingTimeInterval(0.3) }
                marquee = nil
            }
    }

    @ViewBuilder private var marqueeBox: some View {
        if let drag = marquee, !drag.ignored, drag.rect.width > 0 || drag.rect.height > 0 {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(theme.accentColor.opacity(0.14))
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(theme.accentColor, lineWidth: 1))
                .frame(width: drag.rect.width, height: drag.rect.height)
                .offset(x: drag.rect.minX, y: drag.rect.minY)
                .allowsHitTesting(false)
        }
    }
    #endif

    private func updateActiveWeekKey() {
        let threshold = TimelineMetrics.scrollSpyThreshold
        activeWeekKey = timelineWeekGroups.last { group in
            (weekAnchorYs[group.key] ?? .infinity) <= threshold
        }?.key ?? timelineWeekGroups.first?.key
    }

    private func toggleWeekFilter(_ key: String) {
        if selectedWeekKey == key {
            selectedWeekKey = nil
        } else {
            cacheContentWeekRangesIfNeeded(force: true)
            selectedWeekKey = key
        }
    }

    /// Scroll-content Y ranges for each week — cached while unfiltered, replayed when filtered.
    private func cacheContentWeekRangesIfNeeded(force: Bool = false) {
        guard force || selectedWeekKey == nil else { return }
        guard !timelineWeekGroups.isEmpty else { return }

        let scrollOffset = effectiveScrollOffset
        var ranges: [String: (top: CGFloat, bottom: CGFloat)] = [:]
        for group in timelineWeekGroups {
            guard let viewportTop = weekAnchorYs[group.key] else { continue }
            let contentTop = viewportTop + scrollOffset
            let contentBottom: CGFloat
            if let viewportBottom = weekBottomYs[group.key] {
                contentBottom = viewportBottom + scrollOffset
            } else if let index = timelineWeekGroups.firstIndex(where: { $0.key == group.key }),
                      index + 1 < timelineWeekGroups.count,
                      let nextViewportTop = weekAnchorYs[timelineWeekGroups[index + 1].key] {
                contentBottom = nextViewportTop + scrollOffset
            } else {
                contentBottom = scrollContentBottom + scrollOffset
            }
            if contentBottom > contentTop {
                ranges[group.key] = (contentTop, contentBottom)
            }
        }
        if !ranges.isEmpty {
            cachedContentWeekRanges = ranges
        }
    }

    /// Viewport Y positions for timeline bars — spans first→last card per week with 4pt gaps.
    private func timelineBarLayouts(scrollTopInset: CGFloat) -> [String: WeekBarLayout] {
        let scrollOffset = effectiveScrollOffset
        var rawLayouts: [(key: String, topY: CGFloat, bottomY: CGFloat)] = []

        for group in timelineWeekGroups {
            let topY: CGFloat
            let bottomY: CGFloat

            if selectedWeekKey == nil,
               let liveTop = weekAnchorYs[group.key] {
                topY = liveTop - scrollTopInset
                if let liveBottom = weekBottomYs[group.key] {
                    bottomY = liveBottom - scrollTopInset
                } else if let index = timelineWeekGroups.firstIndex(where: { $0.key == group.key }),
                          index + 1 < timelineWeekGroups.count,
                          let nextTop = weekAnchorYs[timelineWeekGroups[index + 1].key] {
                    bottomY = nextTop - scrollTopInset - TimelineMetrics.barGap
                } else {
                    bottomY = scrollContentBottom - scrollTopInset
                }
            } else if let cached = cachedContentWeekRanges[group.key] {
                topY = cached.top - scrollOffset - scrollTopInset
                bottomY = cached.bottom - scrollOffset - scrollTopInset
            } else {
                continue
            }

            if bottomY > topY {
                rawLayouts.append((group.key, topY, bottomY))
            }
        }

        rawLayouts.sort { $0.topY < $1.topY }
        var layouts: [String: WeekBarLayout] = [:]
        var previousBottom: CGFloat = -.infinity
        for entry in rawLayouts {
            var topY = entry.topY
            if previousBottom > -.infinity, topY < previousBottom + TimelineMetrics.barGap {
                topY = previousBottom + TimelineMetrics.barGap
            }
            let bottomY = max(topY + 2, entry.bottomY)
            layouts[entry.key] = WeekBarLayout(topY: topY, bottomY: bottomY)
            previousBottom = bottomY
        }
        return layouts
    }

    private func openScreenshotDetailIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-screenshotDetailDemo"),
              screenshotDetailItem == nil,
              !embedInPanelLayout,
              let first = allItems.first else { return }
        screenshotDetailItem = first
    }

    private func applyScreenshotTimelineHoverIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-screenshotTimelineHover"),
              let target = timelineWeekGroups.dropFirst().first?.key ?? timelineWeekGroups.first?.key else { return }
        interactionWeekKey = target
    }

    private func applyScreenshotWeekFilterIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-screenshotWeekFilter") else { return }
        scheduleScreenshotWeekFilter(attempt: 0)
    }

    private func scheduleScreenshotWeekFilter(attempt: Int) {
        let delay = attempt == 0 ? 1.0 : 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            cacheContentWeekRangesIfNeeded(force: true)
            let ready = scrollContentBottom > 0 && !cachedContentWeekRanges.isEmpty
            if !ready && attempt < 8 {
                scheduleScreenshotWeekFilter(attempt: attempt + 1)
                return
            }
            if let target = timelineWeekGroups.dropFirst().first?.key ?? timelineWeekGroups.first?.key {
                selectedWeekKey = target
            }
        }
    }

    private func scrollForScreenshotIfNeeded(using proxy: ScrollViewProxy) {
        guard ProcessInfo.processInfo.arguments.contains("-screenshotScrolledHeader"),
              let target = timelineWeekGroups.dropFirst(2).first?.key ?? timelineWeekGroups.last?.key else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.none) {
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }

    private var filterPillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if needsReviewOnly {
                    HStack(spacing: 4) {
                        Text("Needs review").font(.karst(.caption, weight: .medium))
                        Button { needsReviewOnly = false } label: {
                            Image(systemName: "xmark").font(.caption2)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(theme.accentSubtle)
                    .foregroundStyle(theme.textPrimary)
                    .clipShape(Capsule())
                }
                if let weekKey = selectedWeekKey,
                   let label = timelineWeekGroups.first(where: { $0.key == weekKey })?.label {
                    HStack(spacing: 4) {
                        Text(label).font(.karst(.caption, weight: .medium))
                        Button { selectedWeekKey = nil } label: {
                            Image(systemName: "xmark").font(.caption2)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(theme.accentSubtle)
                    .foregroundStyle(theme.textPrimary)
                    .clipShape(Capsule())
                }
                ForEach(Array(selectedTagNames).sorted(), id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag).font(.karst(.caption, weight: .medium))
                        Button { selectedTagNames.remove(tag) } label: {
                            Image(systemName: "xmark").font(.caption2)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(theme.accentSubtle)
                    .foregroundStyle(theme.textPrimary)
                    .clipShape(Capsule())
                }
                if !selectedTagNames.isEmpty || selectedWeekKey != nil || needsReviewOnly {
                    Button("Clear all") {
                        selectedTagNames.removeAll()
                        selectedWeekKey = nil
                        needsReviewOnly = false
                    }
                    .font(.karst(.caption))
                    .foregroundStyle(theme.accentColor)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Week scroll anchor


// MARK: - Previews

#Preview("iPhone 17 Pro") {
    NavigationStack {
        MasonryGridView()
            .navigationDestination(for: Item.self) { DetailView(item: $0) }
    }
    .modelContainer(SeedData.previewContainer)
    .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
    .preferredColorScheme(.dark)
    .frame(width: 393)
}

#Preview("iPad Pro 13\"") {
    ContentView()
        .modelContainer(SeedData.previewContainer)
        .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
        .preferredColorScheme(.dark)
        .frame(width: 1032, height: 1376)
}

#Preview("Mac 1280") {
    ContentView()
        .modelContainer(SeedData.previewContainer)
        .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
        .preferredColorScheme(.dark)
        .frame(width: 1280, height: 900)
}


private struct PlacedCard {
    let item: Item
    let frame: CGRect
}

/// Only the cards near the viewport. Equatable so scrolling within a window, which
/// re-renders the grid view for the timeline, leaves the cards alone.
private struct VirtualMasonryCards<Card: View>: View, Equatable {
    struct Token: Equatable {
        var window: Int
        var viewportHeight: CGFloat
        var modelVersion: UInt
        var filterVersion: UInt
        var selectedItem: PersistentIdentifier?
        var selectionVersion: UInt = 0
    }

    let placed: [PlacedCard]
    let token: Token
    @ViewBuilder let card: (Item) -> Card

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.token == rhs.token
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(placed, id: \.item.persistentModelID) { placed in
                card(placed.item)
                    .frame(width: placed.frame.width, height: placed.frame.height, alignment: .top)
                    .offset(x: placed.frame.minX, y: placed.frame.minY)
            }
        }
    }
}

/// Watches per-item values in a view of its own: reading them in the grid's body would
/// walk the whole library on every scroll tick.
private struct LibraryChangeWatcher: View, Equatable {
    let items: [Item]
    let onReviewChange: () -> Void
    let onCoverChange: () -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.items.count == rhs.items.count
    }

    var body: some View {
        let sig = signatures
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: sig.review) { _, _ in onReviewChange() }
            .onChange(of: sig.cover) { _, _ in onCoverChange() }
    }

    /// One pass, no arrays: two hashes standing in for the per-item lists.
    private var signatures: (review: Int, cover: Int) {
        var review = Hasher(), cover = Hasher()
        for item in items {
            review.combine(item.needsReview)
            cover.combine(item.coverAspect)
        }
        return (review.finalize(), cover.finalize())
    }
}

#if os(macOS)
/// An in-progress drag box on the grid, in the card stack's coordinates.
private struct MarqueeDrag {
    var base: Set<UUID>
    var flips: Bool
    var ignored: Bool
    var rect: CGRect
}
#endif

/// The grid card's drag onto the canvas, only where a drag has that meaning.
private struct CanvasCardDrag: ViewModifier {
    let item: Item
    let enabled: Bool
    let theme: AppTheme

    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content.draggable(CanvasDragItem(slug: item.slug)) {
                ItemCardView(item: item, resolvedColumns: 6)
                    .frame(width: 180)
                    .environment(\.appTheme, theme)
            }
        } else {
            content
        }
    }
}
