import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.horizontalSizeClass) private var hSizeClass

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
                    ContentUnavailableView("Select an item", systemImage: "doc.text")
                        .foregroundStyle(theme.textSecondary)
                }
            } else {
                // iPhone: push navigation
                NavigationStack {
                    MasonryGridView()
                        .navigationDestination(for: Item.self) { item in
                            DetailView(item: item)
                        }
                }
            }
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
