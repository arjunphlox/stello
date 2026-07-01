import SwiftUI
import SwiftData

@main
struct StelloApp: App {
    let container: ModelContainer

    init() {
        StelloFont.registerBundledKarstFonts()

        // Screenshot runs use a clean in-memory store so CloudKit-synced legacy records
        // (stale titles / duplicates) don't pollute the captured grid.
        if ProcessInfo.processInfo.arguments.contains("-screenshotCleanStore") {
            container = try! StelloStore.makeInMemoryContainer()
            return
        }
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
            RootView(container: container)
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        #endif
    }
}

/// Resolves stored appearance preference (`system` / `light` / `dark`) against the device scheme.
private struct RootView: View {
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.modelContext) private var context
    @AppStorage(ThemeAppearancePreference.storageKey) private var rawMode: String = ThemeAppearancePreference.defaultMode
    @AppStorage("theme.accent") private var rawAccent: String = AccentColor.amber.rawValue

    let container: ModelContainer
    private let enrichmentCoordinator = EnrichmentCoordinator()

    private var theme: AppTheme {
        AppTheme(
            mode: ThemeAppearancePreference.resolvedColorMode(rawMode: rawMode, systemScheme: systemScheme),
            accent: AccentColor(rawValue: rawAccent) ?? .amber
        )
    }

    var body: some View {
        ContentView()
            .modelContainer(container)
            .environment(\.appTheme, theme)
            .environment(\.enrichmentCoordinator, enrichmentCoordinator)
            .preferredColorScheme(ThemeAppearancePreference.preferredColorScheme(rawMode: rawMode, theme: theme))
            .onOpenURL { url in
                DropImportService.importFileURL(url, context: context, coordinator: enrichmentCoordinator)
            }
    }
}
