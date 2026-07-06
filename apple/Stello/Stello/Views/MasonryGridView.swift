import SwiftUI
import SwiftData

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

private struct GridContainerWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 375
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct WeekAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct WeekBottomAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
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
        isDropTargeted: Bool = false
    ) {
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
        self.onSettings = onSettings
        self.isDropTargeted = isDropTargeted
        self.catalogItems = catalogItems
    }

    @Query(sort: \Item.addedAt, order: .reverse) private var queriedItems: [Item]
    @Environment(\.modelContext) private var context
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
    @State private var cachedFirstWeekAnchorByItemID: [PersistentIdentifier: String] = [:]
    @State private var cachedLastWeekAnchorByItemID: [PersistentIdentifier: String] = [:]
    @State private var filterCacheToken: UInt = 0

    /// Ring headroom for the 4pt outset selection ring. Applied vertically inside the
    /// card stack; horizontally it lives in the HorizontalOutsetClip boundaries so the
    /// outer card edges stay flush with the header edges.
    private static let selectionOutlineInset: CGFloat = StelloLayout.gridRingClipOutset
    /// Deadband past a column boundary before stepping to the next count (prevents flicker).
    private static let columnHysteresis: Double = 0.35
    /// Minimum scroll delta before updating header / week-spy state.
    private static let scrollOffsetDeadband: CGFloat = 10

    private var effectiveForcedColumns: Int? {
        gridColumns == 0 ? nil : min(max(gridColumns, 1), 12)
    }

    private func resolvedColumnCount(for width: CGFloat) -> Int {
        MasonryLayout(forcedColumns: effectiveForcedColumns).resolvedColumnCount(for: width)
    }

    private var tagFilteredItems: [Item] { cachedTagFilteredItems }
    private var displayItems: [Item] { cachedDisplayItems }
    private var timelineWeekGroups: [WeekGroup] { cachedTimelineWeekGroups }
    private var firstOfWeekAnchorByItemID: [PersistentIdentifier: String] { cachedFirstWeekAnchorByItemID }
    private var lastOfWeekAnchorByItemID: [PersistentIdentifier: String] { cachedLastWeekAnchorByItemID }

    private func refreshFilterCaches() {
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

        var firstMap: [PersistentIdentifier: String] = [:]
        var lastMap: [PersistentIdentifier: String] = [:]
        var previousKey: String?
        for item in cachedDisplayItems {
            let key = WeekGroup.isoWeekKey(for: item.addedAt)
            if key != previousKey {
                firstMap[item.persistentModelID] = key
                previousKey = key
            }
            lastMap[item.persistentModelID] = key
        }
        cachedFirstWeekAnchorByItemID = firstMap
        cachedLastWeekAnchorByItemID = lastMap
        filterCacheToken &+= 1
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
        // Compact: respect top safe area so the sticky header sits below the notch;
        // ignore bottom so the grid + control bar bleed to the home-indicator edge.
        // Background still paints edge-to-edge via `.background { … .ignoresSafeArea() }`.
        .ignoresSafeArea(edges: embedInPanelLayout ? [] : .bottom)
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
            if ProcessInfo.processInfo.arguments.contains(where: {
                ["-screenshotSettings", "-screenshotUserPrefs", "-screenshotSettingsPanel",
                 "-screenshotAccentsDark", "-screenshotAccentsLight"].contains($0)
            }) {
                showSettings = true
            }
        }
        .onAppear { refreshFilterCaches() }
        .onChange(of: allItems.count) { _, _ in
            refreshFilterCaches()
            openScreenshotDetailIfNeeded()
        }
        .onChange(of: searchText) { _, _ in refreshFilterCaches() }
        .onChange(of: selectedTagNames) { _, _ in refreshFilterCaches() }
        .onChange(of: selectedWeekKey) { _, _ in refreshFilterCaches() }
        .onChange(of: needsReviewOnly) { _, _ in refreshFilterCaches() }
        .onChange(of: weekAnchorYs) { _, _ in
            cacheContentWeekRangesIfNeeded()
        }
        .onChange(of: weekBottomYs) { _, _ in
            cacheContentWeekRangesIfNeeded()
        }
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
                let safeTop = embedInPanelLayout ? 0 : viewport.safeAreaInsets.top
                let compactScrollInset = embedInPanelLayout
                    ? scrollTopInset
                    : compactScrollTopInset(safeTop: safeTop)

                ZStack(alignment: .top) {
                    ScrollView {
                        gridScrollContent(topInset: compactScrollInset)
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
                    .onPreferenceChange(GridContainerWidthKey.self) { width in
                        gridContainerWidth = width
                    }
                    .onPreferenceChange(WeekAnchorPreferenceKey.self) { anchors in
                        weekAnchorYs = anchors
                        cacheContentWeekRangesIfNeeded()
                    }
                    .onPreferenceChange(WeekBottomAnchorPreferenceKey.self) { anchors in
                        weekBottomYs = anchors
                        cacheContentWeekRangesIfNeeded()
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
            }
            .frame(maxHeight: .infinity)
            .clipShape(HorizontalOutsetClip(outset: Self.selectionOutlineInset))
            .onAppear {
                scrollForScreenshotIfNeeded(using: scrollProxy)
                updateActiveWeekKey()
                applyScreenshotTimelineHoverIfNeeded()
                applyScreenshotWeekFilterIfNeeded()
            }
        }
    }

    private func compactHeaderOverlay(safeTop: CGFloat) -> some View {
        StelloHeaderView(
            itemCount: allItems.count,
            scrollProgress: headerScrollProgress,
            isDropTargeted: isDropTargeted
        )
        .padding(.horizontal, StelloLayout.windowInset)
        .padding(.top, safeTop + StelloLayout.compactHeaderBelowSafeAreaGap)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func bottomControlOverlay(safeBottom: CGFloat) -> some View {
        let screenshotHoverFilters = ProcessInfo.processInfo.arguments.contains("-screenshotHeaderHover")
        let bottomPadding = StelloLayout.controlBarBottomPadding(
            embedInPanelLayout: embedInPanelLayout,
            compactPhone: isCompactPhone
        ) + (embedInPanelLayout ? 0 : safeBottom)

        return GridBottomControlBar(
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
        // Embed: leading pad compensates the gutter now included in the grid column
        // (see gridScrollContent). Non-embed (iPhone): unchanged 16pt compact side inset.
        .padding(
            .leading,
            embedInPanelLayout
                ? StelloLayout.windowInset
                : StelloLayout.controlBarHorizontalPadding(embedInPanelLayout: embedInPanelLayout)
        )
        .padding(.trailing, StelloLayout.controlBarHorizontalPadding(embedInPanelLayout: embedInPanelLayout))
        .padding(.bottom, bottomPadding)
        .frame(maxWidth: .infinity, alignment: .bottom)
    }

    private func gridScrollContent(topInset: CGFloat) -> some View {
        VStack(spacing: 12) {
            scrollOffsetProbe

            if !selectedTagNames.isEmpty || selectedWeekKey != nil || needsReviewOnly {
                filterPillsRow
            }

            MasonryLayout(spacing: 12, forcedColumns: effectiveForcedColumns) {
                ForEach(displayItems) { item in
                    card(for: item)
                        .modifier(WeekAnchorModifier(
                            weekKey: firstOfWeekAnchorByItemID[item.persistentModelID],
                            edge: .top
                        ))
                        .modifier(WeekAnchorModifier(
                            weekKey: lastOfWeekAnchorByItemID[item.persistentModelID],
                            edge: .bottom
                        ))
                }
            }
            .padding(Self.selectionOutlineInset)
            // Cancel the outline inset horizontally so the outer card edges sit flush
            // with the header's left/right edges; the ring's horizontal slack lives in
            // the HorizontalOutsetClip boundaries instead of inside the card stack.
            .padding(.horizontal, -Self.selectionOutlineInset)

            scrollContentBottomProbe
        }
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: GridContainerWidthKey.self,
                    value: geo.size.width
                )
            }
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
                embedInPanelLayout: embedInPanelLayout,
                compactPhone: isCompactPhone
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
                onCardTap(item)
            } label: {
                ItemCardView(
                    item: item,
                    isSelected: selectedItem?.persistentModelID == item.persistentModelID
                        && panelContent == .itemDetail,
                    resolvedColumns: resolvedColumnCount(for: gridContainerWidth),
                    onOpen: { onCardTap(item) }
                )
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: item) {
                ItemCardView(
                    item: item,
                    resolvedColumns: resolvedColumnCount(for: gridContainerWidth)
                )
            }
            .buttonStyle(.plain)
        }
    }

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

private enum WeekAnchorEdge {
    case top
    case bottom
}

private struct WeekAnchorModifier: ViewModifier {
    let weekKey: String?
    var edge: WeekAnchorEdge = .top

    func body(content: Content) -> some View {
        if let weekKey {
            content
                .id(edge == .top ? weekKey : "\(weekKey)-bottom")
                .background {
                    GeometryReader { geo in
                        let frame = geo.frame(in: .named("stelloScroll"))
                        let y = frame.minY + (edge == .bottom ? frame.height : 0)
                        Group {
                            if edge == .top {
                                Color.clear.preference(
                                    key: WeekAnchorPreferenceKey.self,
                                    value: [weekKey: y]
                                )
                            } else {
                                Color.clear.preference(
                                    key: WeekBottomAnchorPreferenceKey.self,
                                    value: [weekKey: y]
                                )
                            }
                        }
                    }
                }
        } else {
            content
        }
    }
}

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
