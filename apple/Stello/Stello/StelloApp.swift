import SwiftUI
import SwiftData

@main
struct StelloApp: App {
    let container: ModelContainer

    @AppStorage("theme.mode")   private var rawMode:   String = ColorMode.dark.rawValue
    @AppStorage("theme.accent") private var rawAccent: String = AccentColor.amber.rawValue

    private var theme: AppTheme {
        AppTheme(
            mode:   ColorMode(rawValue: rawMode)   ?? .dark,
            accent: AccentColor(rawValue: rawAccent) ?? .amber
        )
    }

    init() {
        let schema = Schema([Item.self, Tag.self, ItemImage.self, Snippet.self])
        let config = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .private("iCloud.com.phloxpage.Stello")
        )
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Cannot create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            rootView
        }
        .defaultSize(width: 1200, height: 800)

        Settings {
            SettingsView()
                .environment(\.appTheme, theme)
                .preferredColorScheme(theme.colorScheme)
        }
        #else
        WindowGroup {
            rootView
        }
        #endif
    }

    private var rootView: some View {
        ContentView()
            .modelContainer(container)
            .environment(\.appTheme, theme)
            .preferredColorScheme(theme.colorScheme)
    }
}
