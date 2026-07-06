import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.modelContext) private var context
    @Environment(\.enrichmentCoordinator) private var enrichmentCoordinator

    @Query(sort: \Item.addedAt, order: .reverse) private var allItems: [Item]

    @AppStorage("panel.widthFraction") private var panelWidthFraction: Double = 0.25
    @State private var selectedItem: Item?
    @State private var panelContent: SidePanelContent = .none
    @State private var selectedTagNames: Set<String> = []
    @State private var needsReviewOnly = false
    @State private var scrollOffset: CGFloat = 0
    @State private var isResizingPanel = false
    @State private var isDropTargeted = false

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
        .task {
            await SeedData.prepareStore(in: context)
            applyScreenshotLaunchState()
        }
        .task(priority: .background) {
            await OptacosImporter.importIfNeeded(in: context)
            await SeedData.backfillSeedCovers(in: context)
            await enrichmentCoordinator.enrichPendingItems(context: context)
        }
        .onAppear {
            applyScreenshotLaunchState()
            scheduleScreenshotLaunchStateRetryIfNeeded()
        }
        .onChange(of: allItems.count) { _, _ in
            applyScreenshotLaunchState()
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

            HStack(alignment: .top, spacing: StelloLayout.columnGap) {
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
                        onSettings: { togglePanel(.settings) }
                    )
                    .frame(width: gridColumnWidth)
                    .frame(maxHeight: .infinity)

                    headerOverlay(
                        itemCount: allItems.count,
                        headerScrollProgress: headerScrollProgress
                    )
                    .frame(width: gridWidth)
                }
                .frame(width: gridColumnWidth)
                .frame(maxHeight: .infinity)
                // Horizontal outset keeps the selection ring visible on edge cards,
                // which sit flush with the header edges (ring slack, not card inset).
                .clipShape(HorizontalOutsetClip(outset: StelloLayout.gridRingClipOutset))
                .layoutPriority(0)

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
                    .padding(.bottom, StelloLayout.windowInset)
                    .layoutPriority(1)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.trailing, StelloLayout.windowInset)
        }
        .clipped()
        #if os(macOS)
        .ignoresSafeArea(edges: .top)
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
            MasonryGridView(
                catalogItems: allItems,
                selectedTagNames: $selectedTagNames,
                needsReviewOnly: $needsReviewOnly,
                onCardTap: { selectedItem = $0 },
                isDropTargeted: isDropTargeted
            )
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
