import SwiftUI
import SwiftData

@main
struct StelloApp: App {
    let container: ModelContainer

    init() {
        StelloFont.registerBundledKarstFonts()
        Self.applyScreenshotLaunchFixtures()

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

    private static func applyScreenshotLaunchFixtures() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-screenshotAccentsDark") {
            UserDefaults.standard.set(ColorMode.dark.rawValue, forKey: ThemeAppearancePreference.storageKey)
        } else if args.contains("-screenshotAccentsLight") {
            UserDefaults.standard.set(ColorMode.light.rawValue, forKey: ThemeAppearancePreference.storageKey)
        }
        if args.contains("-screenshotUserPrefs") {
            UserDefaults.standard.set("Arjun", forKey: "profile.name")
            UserDefaults.standard.set("Designer", forKey: "profile.designation")
        }
        if args.contains("-screenshotPanelHalf") {
            UserDefaults.standard.set(0.5, forKey: "panel.widthFraction")
        }
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
        let mode = ThemeAppearancePreference.resolvedColorMode(rawMode: rawMode, systemScheme: systemScheme)
        let accent = AccentColor.resolved(storedRawValue: rawAccent, for: mode)
        return AppTheme(mode: mode, accent: accent)
    }

    var body: some View {
        ContentView()
            .modelContainer(container)
            .environment(\.appTheme, theme)
            .environment(\.enrichmentCoordinator, enrichmentCoordinator)
            .environment(UserProfileStore.shared)
            .preferredColorScheme(ThemeAppearancePreference.preferredColorScheme(rawMode: rawMode, theme: theme))
            .onOpenURL { url in
                DropImportService.importFileURL(url, context: context, coordinator: enrichmentCoordinator)
            }
    }
}
