import SwiftUI
import SwiftData

struct MasonryGridView: View {
    /// When true, header lives in `ContentView` and card taps call `onCardTap`.
    var embedInPanelLayout: Bool = false
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
        selectedTagNames: Binding<Set<String>> = .constant([]),
        selectedItem: Item? = nil,
        panelContent: SidePanelContent = .none,
        onCardTap: ((Item) -> Void)? = nil,
        onFilters: (() -> Void)? = nil,
        onImport: (() -> Void)? = nil,
        onSettings: (() -> Void)? = nil
    ) {
        self.embedInPanelLayout = embedInPanelLayout
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
            ScrollView {
                VStack(spacing: 12) {
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
                    }
                }
                .padding(.horizontal, embedInPanelLayout ? 0 : StelloLayout.windowInset)
                .padding(.top, embedInPanelLayout ? 0 : StelloLayout.windowInset)
                .padding(.bottom, StelloLayout.floatingSearchScrollInset)
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

    private func initExpansion() {
        guard !hasInitialized, let first = weekGroups.first else { return }
        hasInitialized = true
        expandedWeeks = [first.key]
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
