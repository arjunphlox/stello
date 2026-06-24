import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        MasonryGridView()
    }
}

#Preview("iPhone", traits: .sizeThatFitsLayout) {
    ContentView()
        .modelContainer(SeedData.previewContainer)
}

#Preview("iPad") {
    ContentView()
        .modelContainer(SeedData.previewContainer)
        .frame(width: 768, height: 1024)
}

#Preview("Mac") {
    ContentView()
        .modelContainer(SeedData.previewContainer)
        .frame(width: 1280, height: 900)
}
