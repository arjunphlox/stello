import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.modelContext) private var context
    @Environment(\.enrichmentCoordinator) private var enrichmentCoordinator

    @State private var selectedItem: Item?

    private var isRegular: Bool { hSizeClass == .regular }

    var body: some View {
        Group {
            if isRegular {
                // iPad / Mac: masonry grid is the MAIN content; selected item's
                // details live in a right-hand inspector (mirrors the web side panel).
                NavigationStack {
                    MasonryGridView(selection: $selectedItem)
                        .inspector(isPresented: inspectorPresented) {
                            inspectorContent
                                .inspectorColumnWidth(min: 320, ideal: 380, max: 480)
                        }
                }
            } else {
                // iPhone: push navigation into the detail view.
                NavigationStack {
                    MasonryGridView()
                        .navigationDestination(for: Item.self) { DetailView(item: $0) }
                        .navigationDestination(item: $selectedItem) { DetailView(item: $0) }
                }
            }
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("-screenshotEnrichmentDemo") {
                selectedItem = SeedData.ensureEnrichmentDemo(in: context)
            }
            await enrichmentCoordinator.enrichPendingItems(context: context)
        }
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { selectedItem != nil },
            set: { if !$0 { selectedItem = nil } }
        )
    }

    @ViewBuilder
    private var inspectorContent: some View {
        if let selectedItem {
            DetailView(item: selectedItem)
        } else {
            ContentUnavailableView("Select an item", systemImage: "sidebar.right")
                .foregroundStyle(theme.textSecondary)
        }
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
