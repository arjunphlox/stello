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
        do {
            container = try StelloStore.makeContainer()
        } catch {
            // App Group container unavailable (e.g. entitlement not yet provisioned);
            // fall back to local store so the app still launches.
            print("⚠️ App Group container failed (\(error)); falling back to local store")
            container = try! StelloStore.makeLocalContainer()
        }
    }

    var body: some Scene {
        WindowGroup {
            rootView
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        #endif
    }

    private var rootView: some View {
        ContentView()
            .modelContainer(container)
            .environment(\.appTheme, theme)
            .environment(\.enrichmentCoordinator, EnrichmentCoordinator())
            .preferredColorScheme(theme.colorScheme)
    }
}
