import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.modelContext) private var context
    @Environment(\.enrichmentCoordinator) private var enrichmentCoordinator

    @State private var screenshotDemoItem: Item? = nil

    var body: some View {
        Group {
            if hSizeClass == .regular {
                // iPad / Mac: sidebar grid + detail column
                NavigationSplitView {
                    MasonryGridView()
                        .navigationDestination(for: Item.self) { item in
                            DetailView(item: item)
                        }
                } detail: {
                    if let demo = screenshotDemoItem {
                        DetailView(item: demo)
                    } else {
                        ContentUnavailableView("Select an item", systemImage: "doc.text")
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            } else {
                // iPhone: push navigation
                NavigationStack {
                    MasonryGridView()
                        .navigationDestination(for: Item.self) { item in
                            DetailView(item: item)
                        }
                        .navigationDestination(item: $screenshotDemoItem) { item in
                            DetailView(item: item)
                        }
                }
            }
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("-screenshotEnrichmentDemo") {
                screenshotDemoItem = SeedData.ensureEnrichmentDemo(in: context)
            }
            await enrichmentCoordinator.enrichPendingItems(context: context)
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
        .frame(width: 768, height: 1024)
}

#Preview("Mac") {
    ContentView()
        .modelContainer(SeedData.previewContainer)
        .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
        .preferredColorScheme(.dark)
        .frame(width: 1280, height: 900)
}
