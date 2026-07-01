import SwiftUI
import SwiftData

// MARK: - Scroll offset tracking

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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

struct MasonryGridView: View {
    /// When true, header lives in `ContentView` and card taps call `onCardTap`.
    var embedInPanelLayout: Bool = false
    /// Top scroll inset when header floats over the grid (regular Mac/iPad layout).
    var scrollTopInset: CGFloat = 0
    /// Bound scroll offset for header transparency (regular Mac/iPad layout).
    var scrollOffset: Binding<CGFloat>? = nil
    @Binding var selectedTagNames: Set<String>
    var selectedItem: Item? = nil
    var panelContent: SidePanelContent = .none
    var onCardTap: ((Item) -> Void)? = nil

    /// iPhone callbacks — open tool sheets from header buttons.
    var onFilters: (() -> Void)? = nil
    var onImport: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil
    /// Window drag hover — drives compact header drop-state UI.
    var isDropTargeted: Bool = false

    init(
        embedInPanelLayout: Bool = false,
        scrollTopInset: CGFloat = 0,
        scrollOffset: Binding<CGFloat>? = nil,
        selectedTagNames: Binding<Set<String>> = .constant([]),
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
        self.selectedItem = selectedItem
        self.panelContent = panelContent
        self.onCardTap = onCardTap
        self.onFilters = onFilters
        self.onImport = onImport
        self.onSettings = onSettings
        self.isDropTargeted = isDropTargeted
    }

    @Query(sort: \Item.addedAt, order: .reverse) private var allItems: [Item]
    @Environment(\.modelContext) private var context
    @Environment(\.appTheme) private var theme

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
    @State private var activeWeekKey: String?
    @State private var interactionWeekKey: String?
    /// Local scroll offset when header is owned here (compact iPhone layout).
    @State private var compactScrollOffset: CGFloat = 0

    /// Inset inside the scroll clip so the 4pt outset selection ring stays visible at grid edges.
    private static let selectionOutlineInset: CGFloat = 6
    /// Deadband past a column boundary before stepping to the next count (prevents flicker).
    private static let columnHysteresis: Double = 0.35

    private var effectiveForcedColumns: Int? {
        gridColumns == 0 ? nil : min(max(gridColumns, 1), 12)
    }

    private func resolvedColumnCount(for width: CGFloat) -> Int {
        MasonryLayout(forcedColumns: effectiveForcedColumns).resolvedColumnCount(for: width)
    }

    private var displayItems: [Item] {
        ItemFilter.apply(allItems, searchText: searchText, selectedTagNames: selectedTagNames)
    }

    private var weekGroups: [WeekGroup] {
        WeekGroup.makeGroups(from: displayItems)
    }

    private var effectiveScrollOffset: CGFloat {
        scrollOffset?.wrappedValue ?? compactScrollOffset
    }

    private var headerScrollProgress: CGFloat {
        min(max(effectiveScrollOffset, 0) / StelloLayout.headerScrollFadeDistance, 1)
    }

    private var firstOfWeekAnchorByItemID: [PersistentIdentifier: String] {
        var map: [PersistentIdentifier: String] = [:]
        var previousKey: String?
        for item in displayItems {
            let key = WeekGroup.isoWeekKey(for: item.addedAt)
            if key != previousKey {
                map[item.persistentModelID] = key
                previousKey = key
            }
        }
        return map
    }

    var body: some View {
        gridWithTimeline
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
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
            TagFilterSheet(allItems: allItems, selectedTagNames: $selectedTagNames)
                .environment(\.appTheme, theme)
                .preferredColorScheme(theme.colorScheme)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(\.appTheme, theme)
                .preferredColorScheme(theme.colorScheme)
        }
        .task {
            openScreenshotDetailIfNeeded()
            if !embedInPanelLayout && ProcessInfo.processInfo.arguments.contains("-screenshotFilterSheet") {
                showFilterSheet = true
            }
            if ProcessInfo.processInfo.arguments.contains("-screenshotSettings") {
                showSettings = true
            }
        }
        .onChange(of: allItems.count) { _, _ in
            openScreenshotDetailIfNeeded()
        }
        .onChange(of: weekAnchorYs) { _, _ in
            updateActiveWeekKey()
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
            let scrollToWeek: (String) -> Void = { weekKey in
                withAnimation(.easeOut(duration: 0.25)) {
                    scrollProxy.scrollTo(weekKey, anchor: .top)
                }
            }

            GeometryReader { viewport in
                let safeTop = embedInPanelLayout ? 0 : viewport.safeAreaInsets.top
                let compactScrollInset = embedInPanelLayout
                    ? scrollTopInset
                    : StelloLayout.headerOverlayScrollInset + safeTop

                ZStack(alignment: .top) {
                    ScrollView {
                        gridScrollContent(topInset: compactScrollInset)
                            .frame(width: viewport.size.width, alignment: .leading)
                    }
                    #if os(iOS)
                    .scrollContentBackground(.hidden)
                    #endif
                    .frame(width: viewport.size.width, height: viewport.size.height)
                    .coordinateSpace(name: "stelloScroll")
                    .onPreferenceChange(ScrollOffsetKey.self) { offset in
                        if let scrollOffset {
                            scrollOffset.wrappedValue = offset
                        } else {
                            compactScrollOffset = offset
                        }
                    }
                    .onPreferenceChange(GridContainerWidthKey.self) { width in
                        gridContainerWidth = width
                    }
                    .onPreferenceChange(WeekAnchorPreferenceKey.self) { anchors in
                        weekAnchorYs = anchors
                        updateActiveWeekKey()
                    }
                    .simultaneousGesture(gridPinchGesture)
                    .overlay(alignment: .leading) {
                        if !weekGroups.isEmpty {
                            TimelineOverlay(
                                weekGroups: weekGroups,
                                activeWeekKey: activeWeekKey,
                                interactionWeekKey: interactionWeekKey,
                                onWeekSelected: scrollToWeek,
                                onInteractionChanged: { interactionWeekKey = $0 }
                            )
                            .padding(.leading, embedInPanelLayout ? 0 : StelloLayout.windowInset)
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
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .onAppear {
                scrollForScreenshotIfNeeded(using: scrollProxy)
                updateActiveWeekKey()
                applyScreenshotTimelineHoverIfNeeded()
            }
        }
    }

    private func compactHeaderOverlay(safeTop: CGFloat) -> some View {
        StelloHeaderView(
            itemCount: allItems.count,
            scrollProgress: headerScrollProgress,
            isDropTargeted: isDropTargeted
        )
        .padding(.top, safeTop + StelloLayout.windowInset)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func bottomControlOverlay(safeBottom: CGFloat) -> some View {
        let screenshotHoverFilters = ProcessInfo.processInfo.arguments.contains("-screenshotHeaderHover")
        let bottomPadding = StelloLayout.controlBarBottomPadding(embedInPanelLayout: embedInPanelLayout)
            + (embedInPanelLayout ? 0 : safeBottom)

        return GridBottomControlBar(
            searchText: $searchText,
            hasActiveFilters: !selectedTagNames.isEmpty,
            isFilterPanelOpen: panelContent == .filters,
            isImportPanelOpen: panelContent == .import,
            isSettingsPanelOpen: panelContent == .settings,
            forceFilterHover: screenshotHoverFilters,
            onAdd: { onImport?() ?? (showCapture = true) },
            onFilter: { onFilters?() ?? (showFilterSheet = true) },
            onSettings: { onSettings?() ?? (showSettings = true) }
        )
        .padding(.horizontal, StelloLayout.controlBarHorizontalPadding(embedInPanelLayout: embedInPanelLayout))
        .padding(.bottom, bottomPadding)
        .frame(maxWidth: .infinity, alignment: .bottom)
    }

    private func gridScrollContent(topInset: CGFloat) -> some View {
        VStack(spacing: 12) {
            scrollOffsetProbe

            if !selectedTagNames.isEmpty {
                filterPillsRow
            }

            MasonryLayout(spacing: 12, forcedColumns: effectiveForcedColumns) {
                ForEach(displayItems) { item in
                    card(for: item)
                        .modifier(WeekAnchorModifier(
                            weekKey: firstOfWeekAnchorByItemID[item.persistentModelID]
                        ))
                }
            }
            .padding(Self.selectionOutlineInset)
        }
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: GridContainerWidthKey.self,
                    value: geo.size.width
                )
            }
        }
        .padding(.horizontal, embedInPanelLayout ? 0 : StelloLayout.windowInset)
        .padding(.top, topInset)
        .padding(.bottom, StelloLayout.floatingSearchScrollInset)
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
        activeWeekKey = weekGroups.last { group in
            (weekAnchorYs[group.key] ?? .infinity) <= threshold
        }?.key ?? weekGroups.first?.key
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
              let target = weekGroups.dropFirst().first?.key ?? weekGroups.first?.key else { return }
        interactionWeekKey = target
    }

    private func scrollForScreenshotIfNeeded(using proxy: ScrollViewProxy) {
        guard ProcessInfo.processInfo.arguments.contains("-screenshotScrolledHeader"),
              let target = weekGroups.dropFirst(2).first?.key ?? weekGroups.last?.key else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.none) {
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }

    private var filterPillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
                Button("Clear all") { selectedTagNames.removeAll() }
                    .font(.karst(.caption))
                    .foregroundStyle(theme.accentColor)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Week scroll anchor

private struct WeekAnchorModifier: ViewModifier {
    let weekKey: String?

    func body(content: Content) -> some View {
        if let weekKey {
            content
                .id(weekKey)
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: WeekAnchorPreferenceKey.self,
                            value: [weekKey: geo.frame(in: .named("stelloScroll")).minY]
                        )
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
