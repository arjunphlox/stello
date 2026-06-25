import SwiftUI
import SwiftData

// MARK: - Scroll offset tracking

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
        onSettings: (() -> Void)? = nil
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
    }

    @Query(sort: \Item.addedAt, order: .reverse) private var allItems: [Item]
    @Environment(\.modelContext) private var context
    @Environment(\.appTheme) private var theme

    @State private var searchText = ""
    @State private var expandedWeeks: Set<String> = []
    @State private var hasInitialized = false
    @State private var showFilterSheet = false
    @State private var showSettings = false
    @State private var showCapture = false
    @State private var screenshotDetailItem: Item?

    private var isFiltering: Bool { !searchText.isEmpty || !selectedTagNames.isEmpty }

    private var displayItems: [Item] {
        ItemFilter.apply(allItems, searchText: searchText, selectedTagNames: selectedTagNames)
    }

    private var weekGroups: [WeekGroup] {
        WeekGroup.makeGroups(from: displayItems)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 12) {
                        scrollOffsetProbe

                        if !embedInPanelLayout {
                            StelloHeaderView(
                                itemCount: allItems.count,
                                hasActiveFilters: !selectedTagNames.isEmpty,
                                onFilters: { onFilters?() ?? (showFilterSheet = true) },
                                onImport: { onImport?() ?? (showCapture = true) },
                                onSettings: { onSettings?() ?? (showSettings = true) }
                            )
                        }

                        if !selectedTagNames.isEmpty {
                            filterPillsRow
                        }

                        ForEach(weekGroups) { group in
                            WeekSectionView(
                                group: group,
                                isExpanded: isFiltering || expandedWeeks.contains(group.key),
                                onToggle: { toggleWeek(group.key) },
                                selectedItem: embedInPanelLayout ? selectedItem : nil,
                                panelContent: embedInPanelLayout ? panelContent : .none,
                                onCardTap: embedInPanelLayout ? onCardTap : nil
                            )
                            .id(group.key)
                        }
                    }
                    .padding(.horizontal, embedInPanelLayout ? 0 : StelloLayout.windowInset)
                    .padding(.top, embedInPanelLayout ? scrollTopInset : StelloLayout.windowInset)
                    .padding(.bottom, StelloLayout.floatingSearchScrollInset)
                }
                .coordinateSpace(name: "stelloScroll")
                .onPreferenceChange(ScrollOffsetKey.self) { offset in
                    scrollOffset?.wrappedValue = offset
                }
                .onAppear {
                    scrollForScreenshotIfNeeded(using: scrollProxy)
                }
            }

            FloatingSearchBar(text: $searchText)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, embedInPanelLayout ? 0 : StelloLayout.windowInset)
                .padding(.bottom, StelloLayout.floatingSearchBarBottomMargin)
        }
        .background(theme.background)
        #if os(iOS)
        .navigationBarHidden(true)
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
            await SeedData.seedIfNeeded(in: context)
            await SeedData.backfillSeedCovers(in: context)
            openScreenshotDetailIfNeeded()
            if !embedInPanelLayout && ProcessInfo.processInfo.arguments.contains("-screenshotFilterSheet") {
                showFilterSheet = true
            }
        }
        .onAppear { initExpansion() }
        .onChange(of: allItems.count) { _, _ in
            initExpansion()
            openScreenshotDetailIfNeeded()
        }
        .sheet(isPresented: $showCapture) {
            CaptureSheet()
                .environment(\.appTheme, theme)
                .preferredColorScheme(theme.colorScheme)
        }
        .navigationDestination(item: $screenshotDetailItem) { DetailView(item: $0) }
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

    private func initExpansion() {
        guard !hasInitialized, let first = weekGroups.first else { return }
        hasInitialized = true
        // Screenshot demos expand every week so the full cover grid is visible and there
        // is enough content below the header to drive the opaque → glass transition.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-screenshotScrolledHeader") || args.contains("-screenshotExpandAll") {
            expandedWeeks = Set(weekGroups.map(\.key))
        } else {
            expandedWeeks = [first.key]
        }
    }

    private func toggleWeek(_ key: String) {
        if expandedWeeks.contains(key) { expandedWeeks.remove(key) }
        else { expandedWeeks.insert(key) }
    }

    private func openScreenshotDetailIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-screenshotDetailDemo"),
              screenshotDetailItem == nil,
              !embedInPanelLayout,
              let first = allItems.first else { return }
        screenshotDetailItem = first
    }

    private func scrollForScreenshotIfNeeded(using proxy: ScrollViewProxy) {
        guard embedInPanelLayout,
              ProcessInfo.processInfo.arguments.contains("-screenshotScrolledHeader"),
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
                        Text(tag).font(.caption.weight(.medium))
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
                    .font(.caption)
                    .foregroundStyle(theme.accentColor)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
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
