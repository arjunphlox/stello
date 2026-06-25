import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.modelContext) private var context
    @Environment(\.enrichmentCoordinator) private var enrichmentCoordinator

    @Query(sort: \Item.addedAt, order: .reverse) private var allItems: [Item]

    @State private var selectedItem: Item?
    @State private var panelContent: SidePanelContent = .none
    @State private var selectedTagNames: Set<String> = []
    @State private var scrollOffset: CGFloat = 0

    private var isRegular: Bool { hSizeClass == .regular }

    var body: some View {
        Group {
            if isRegular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .task {
            await SeedData.prepareStore(in: context)
            await SeedData.backfillSeedCovers(in: context)
            await enrichmentCoordinator.enrichPendingItems(context: context)
        }
        .onAppear {
            applyScreenshotLaunchState()
        }
    }

    /// Screenshot launch args — applied synchronously so captures don't race seed I/O.
    private func applyScreenshotLaunchState() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-screenshotEnrichmentDemo") {
            selectedItem = SeedData.ensureEnrichmentDemo(in: context)
            panelContent = .itemDetail
        } else if isRegular && args.contains("-screenshotItemPanel"), let first = allItems.first {
            selectedItem = first
            panelContent = .itemDetail
        } else if isRegular && args.contains("-screenshotFiltersPanel") {
            panelContent = .filters
        } else if isRegular && args.contains("-screenshotFiltersActive") {
            selectedTagNames = ["figma"]
        }
    }

    // MARK: - Regular width (Mac / iPad): HStack panel column

    private var regularLayout: some View {
        GeometryReader { geo in
            let scrollTopInset = StelloLayout.headerHeight + StelloLayout.sectionGap
                + (isMac ? StelloLayout.macHeaderCardTopInset : 0)
            let headerScrollProgress = min(
                max(scrollOffset, 0) / StelloLayout.headerScrollFadeDistance,
                1
            )

            ZStack(alignment: .top) {
                HStack(spacing: StelloLayout.columnGap) {
                    MasonryGridView(
                        embedInPanelLayout: true,
                        scrollTopInset: scrollTopInset,
                        scrollOffset: $scrollOffset,
                        selectedTagNames: $selectedTagNames,
                        selectedItem: selectedItem,
                        panelContent: panelContent,
                        onCardTap: handleCardTap
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if panelContent != .none {
                        SidePanelView(
                            content: panelContent,
                            selectedItem: selectedItem,
                            allItems: allItems,
                            selectedTagNames: $selectedTagNames,
                            onClose: closePanel
                        )
                        .frame(width: SidePanelContent.width(for: geo.size.width))
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, StelloLayout.windowInset)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.leading, StelloLayout.windowInset)
                .padding(.trailing, StelloLayout.windowInset)

                #if os(macOS)
                macHeaderOverlay(
                    itemCount: allItems.count,
                    headerScrollProgress: headerScrollProgress
                )
                #else
                StelloHeaderView(
                    itemCount: allItems.count,
                    hasActiveFilters: !selectedTagNames.isEmpty,
                    activePanel: panelContent,
                    scrollProgress: headerScrollProgress,
                    onFilters: { togglePanel(.filters) },
                    onImport: { togglePanel(.import) },
                    onSettings: { togglePanel(.settings) }
                )
                .padding(.horizontal, StelloLayout.windowInset)
                .frame(maxWidth: .infinity, alignment: .top)
                #endif
            }
        }
        #if os(macOS)
        .ignoresSafeArea(edges: .top)
        #endif
        .animation(.spring(duration: 0.28), value: panelContent)
        .background(theme.background)
        #if os(macOS)
        .background(MacWindowConfigurator())
        #endif
    }

    // MARK: - Compact width (iPhone): push nav + sheets

    private var compactLayout: some View {
        NavigationStack {
            MasonryGridView(selectedTagNames: $selectedTagNames)
                .navigationDestination(for: Item.self) { DetailView(item: $0) }
                .navigationDestination(item: $selectedItem) { DetailView(item: $0) }
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

    private var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    #if os(macOS)
    /// Transparent full-width container flush to the window top; inner padding insets the accent card.
    private func macHeaderOverlay(itemCount: Int, headerScrollProgress: CGFloat) -> some View {
        StelloHeaderView(
            itemCount: itemCount,
            hasActiveFilters: !selectedTagNames.isEmpty,
            activePanel: panelContent,
            integratesMacTitleBar: true,
            scrollProgress: headerScrollProgress,
            onFilters: { togglePanel(.filters) },
            onImport: { togglePanel(.import) },
            onSettings: { togglePanel(.settings) }
        )
        .padding(.top, StelloLayout.macHeaderCardTopInset)
        .padding(.horizontal, StelloLayout.macHeaderCardSideInset)
        .frame(maxWidth: .infinity, alignment: .top)
    }
    #endif
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
