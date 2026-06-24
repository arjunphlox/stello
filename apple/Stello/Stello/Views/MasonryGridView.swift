import SwiftUI
import SwiftData

struct MasonryGridView: View {
    @Query(sort: \Item.addedAt, order: .reverse) private var items: [Item]
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            ScrollView {
                MasonryLayout(spacing: 12) {
                    ForEach(items) { item in
                        ItemCardView(item: item)
                    }
                }
                .padding(12)
            }
            .navigationTitle("Stello")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
        .task {
            await SeedData.seedIfNeeded(in: context)
        }
    }
}

#Preview("iPhone 17 Pro") {
    MasonryGridView()
        .modelContainer(SeedData.previewContainer)
        .frame(width: 393)
}

#Preview("iPad Pro 13\"") {
    MasonryGridView()
        .modelContainer(SeedData.previewContainer)
        .frame(width: 1032, height: 1376)
}

#Preview("Mac 1280") {
    MasonryGridView()
        .modelContainer(SeedData.previewContainer)
        .frame(width: 1280, height: 900)
}
