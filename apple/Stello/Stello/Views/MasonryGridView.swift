import SwiftUI
import SwiftData

struct MasonryGridView: View {
    @Query(sort: \Item.addedAt, order: .reverse) private var allItems: [Item]
    @Environment(\.modelContext) private var context
    @Environment(\.appTheme) private var theme

    @State private var searchText = ""
    @State private var selectedTagNames: Set<String> = []
    @State private var expandedWeeks: Set<String> = []
    @State private var hasInitialized = false
    @State private var showFilterSheet = false
    @State private var showSettings = false

    private var isFiltering: Bool { !searchText.isEmpty || !selectedTagNames.isEmpty }

    private var displayItems: [Item] {
        ItemFilter.apply(allItems, searchText: searchText, selectedTagNames: selectedTagNames)
    }

    private var weekGroups: [WeekGroup] {
        WeekGroup.makeGroups(from: displayItems)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !selectedTagNames.isEmpty {
                    filterPillsRow
                }
                ForEach(weekGroups) { group in
                    WeekSectionView(
                        group: group,
                        isExpanded: isFiltering || expandedWeeks.contains(group.key),
                        onToggle: { toggleWeek(group.key) }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
        }
        .background(theme.background)
        .navigationTitle("Stello")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button { showFilterSheet = true } label: {
                        Image(systemName: selectedTagNames.isEmpty
                              ? "line.3.horizontal.decrease"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                    Button { showSettings = true } label: {
                        Image(systemName: "gear")
                    }
                }
                .foregroundStyle(theme.accentColor)
            }
        }
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
        #else
        .toolbar {
            ToolbarItem {
                Button { showFilterSheet = true } label: {
                    Image(systemName: selectedTagNames.isEmpty
                          ? "line.3.horizontal.decrease"
                          : "line.3.horizontal.decrease.circle.fill")
                }
                .foregroundStyle(theme.accentColor)
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            TagFilterSheet(allItems: allItems, selectedTagNames: $selectedTagNames)
                .environment(\.appTheme, theme)
        }
        #endif
        .searchable(text: $searchText, prompt: "Search items…")
        .task { await SeedData.seedIfNeeded(in: context) }
        .onAppear { initExpansion() }
        .onChange(of: allItems.count) { _, _ in initExpansion() }
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
        .padding(.bottom, 4)
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
    NavigationSplitView {
        MasonryGridView()
            .navigationDestination(for: Item.self) { DetailView(item: $0) }
    } detail: {
        ContentUnavailableView("Select an item", systemImage: "doc.text")
    }
    .modelContainer(SeedData.previewContainer)
    .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
    .preferredColorScheme(.dark)
    .frame(width: 1032, height: 1376)
}

#Preview("Mac 1280") {
    NavigationSplitView {
        MasonryGridView()
            .navigationDestination(for: Item.self) { DetailView(item: $0) }
    } detail: {
        ContentUnavailableView("Select an item", systemImage: "doc.text")
    }
    .modelContainer(SeedData.previewContainer)
    .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
    .preferredColorScheme(.dark)
    .frame(width: 1280, height: 900)
}
