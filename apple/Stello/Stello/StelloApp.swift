import SwiftUI
import SwiftData

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@main
struct StelloApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(StelloAppDelegate.self) private var appDelegate
    #else
    @UIApplicationDelegateAdaptor(StelloAppDelegate.self) private var appDelegate
    #endif

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
    @Environment(\.scenePhase) private var scenePhase
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
            // Apply saves/edits made in the web app (iCloud inbox).
            .task {
                WebInboxProcessor.shared.start(context: container.mainContext, coordinator: enrichmentCoordinator)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await WebInboxProcessor.shared.processPending() } }
            }
    }
}

// MARK: - Remote notifications (web inbox pushes)

/// Registers for CloudKit silent pushes and hands inbox pushes to
/// `WebInboxProcessor`, so web saves are processed without opening the app.
#if os(macOS)
final class StelloAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.registerForRemoteNotifications()
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        guard WebInboxProcessor.isInboxNotification(userInfo) else { return }
        Task { @MainActor in await WebInboxProcessor.shared.processPending() }
    }
}
#else
final class StelloAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        guard WebInboxProcessor.isInboxNotification(userInfo) else { return .noData }
        await WebInboxProcessor.shared.processPending()
        return .newData
    }
}
#endif
