import SwiftUI
import SwiftData

@main
struct StelloApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([Item.self, Tag.self, ItemImage.self, Snippet.self])
        // TODO Sprint 1: switch to .private("iCloud.com.phloxpage.Stello") once
        // iCloud + CloudKit capability and Background Modes are enabled in Xcode.
        // CloudKit hard-traps (SIGTRAP) — not a catchable Swift error — when the
        // com.apple.developer.icloud-services entitlement is absent, so we keep
        // the container local-only until the capability is wired up.
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
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
