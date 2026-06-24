import SwiftUI
import SwiftData

@main
struct StelloApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([Item.self, Tag.self, ItemImage.self, Snippet.self])
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .private("iCloud.com.phloxpage.Stello"))
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Cannot create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        #endif
    }
}
