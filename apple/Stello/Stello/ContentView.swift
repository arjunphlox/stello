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
            await SeedData.seedIfNeeded(in: context)
            SeedData.backfillSeedCovers(in: context)
            if ProcessInfo.processInfo.arguments.contains("-screenshotEnrichmentDemo") {
                selectedItem = SeedData.ensureEnrichmentDemo(in: context)
                panelContent = .itemDetail
            } else if isRegular && ProcessInfo.processInfo.arguments.contains("-screenshotItemPanel"),
                      let first = allItems.first {
                selectedItem = first
                panelContent = .itemDetail
            } else if isRegular && ProcessInfo.processInfo.arguments.contains("-screenshotFiltersPanel") {
                panelContent = .filters
            }
            await enrichmentCoordinator.enrichPendingItems(context: context)
        }
    }

    // MARK: - Regular width (Mac / iPad): HStack panel column

    private var regularLayout: some View {
        GeometryReader { geo in
            HStack(spacing: StelloLayout.columnGap) {
                VStack(spacing: StelloLayout.columnGap) {
                    StelloHeaderView(
                        itemCount: allItems.count,
                        hasActiveFilters: !selectedTagNames.isEmpty,
                        activePanel: panelContent,
                        integratesMacTitleBar: isMac,
                        onFilters: { togglePanel(.filters) },
                        onImport: { togglePanel(.import) },
                        onSettings: { togglePanel(.settings) }
                    )

                    MasonryGridView(
                        embedInPanelLayout: true,
                        selectedTagNames: $selectedTagNames,
                        selectedItem: selectedItem,
                        panelContent: panelContent,
                        onCardTap: handleCardTap
                    )
                }
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
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.leading, StelloLayout.windowInset)
            .padding(.trailing, StelloLayout.windowInset)
            .padding(.top, StelloLayout.windowInset)
            .padding(.bottom, StelloLayout.windowInset)
            .animation(.spring(duration: 0.28), value: panelContent)
        }
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
