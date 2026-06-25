import SwiftUI
import SwiftData

struct MasonryGridView: View {
    /// When provided (iPad/Mac), card taps set this inspector selection instead of pushing.
    var selection: Binding<Item?>? = nil
    /// Inspector visibility (regular width only). Separate from selection so the panel can dismiss.
    var isInspectorPresented: Binding<Bool>? = nil
    var showsInspectorToggle: Bool = false

    @Query(sort: \Item.addedAt, order: .reverse) private var allItems: [Item]
    @Environment(\.modelContext) private var context
    @Environment(\.appTheme) private var theme

    @State private var searchText = ""
    @State private var selectedTagNames: Set<String> = []
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
        ScrollView {
            VStack(spacing: 12) {
                StelloHeaderView(
                    itemCount: allItems.count,
                    hasActiveFilters: !selectedTagNames.isEmpty,
                    onFilters: { showFilterSheet = true },
                    onImport: { showCapture = true },
                    onSettings: { showSettings = true }
                )

                searchField

                if !selectedTagNames.isEmpty {
                    filterPillsRow
                }

                ForEach(weekGroups) { group in
                    WeekSectionView(
                        group: group,
                        isExpanded: isFiltering || expandedWeeks.contains(group.key),
                        onToggle: { toggleWeek(group.key) },
                        selection: selection
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(theme.background)
        #if os(iOS)
        .navigationBarHidden(true)
        #else
        .navigationTitle("")
        #endif
        .toolbar {
            if showsInspectorToggle, let isInspectorPresented {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isInspectorPresented.wrappedValue.toggle()
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .help("Toggle inspector")
                    .foregroundStyle(
                        isInspectorPresented.wrappedValue ? theme.accentColor : theme.textSecondary
                    )
                }
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
        .task {
            await SeedData.seedIfNeeded(in: context)
            SeedData.backfillSeedCovers(in: context)
            openScreenshotDetailIfNeeded()
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

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.textSecondary)
            TextField("Search items…", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundStyle(theme.textPrimary)
        }
        .font(.body)
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(theme.backgroundSubtle)
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
              selection == nil,
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
    NavigationStack {
        MasonryGridView(selection: .constant(nil), isInspectorPresented: .constant(false), showsInspectorToggle: true)
    }
    .modelContainer(SeedData.previewContainer)
    .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
    .preferredColorScheme(.dark)
    .frame(width: 1032, height: 1376)
}

#Preview("Mac 1280") {
    NavigationStack {
        MasonryGridView(selection: .constant(nil), isInspectorPresented: .constant(true), showsInspectorToggle: true)
    }
    .modelContainer(SeedData.previewContainer)
    .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
    .preferredColorScheme(.dark)
    .frame(width: 1280, height: 900)
}
