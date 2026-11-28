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
        _ = LaunchClock.start
        StelloFont.registerBundledKarstFonts()
        Self.applyScreenshotLaunchFixtures()

        // Screenshot runs use a clean in-memory store so CloudKit-synced legacy records
        // (stale titles / duplicates) don't pollute the captured grid.
        // Unit tests are hosted by the app: never let a test run open the real iCloud library.
        #if DEBUG
        // The 10k scale check needs a store that keeps image bytes on disk like the real
        // library; an in-memory store holds every cover in RAM and swamps the budget.
        if ScaleCheck.isEnabled {
            container = try! StelloStore.makeScaleCheckContainer()
            return
        }
        #endif
        if ProcessInfo.processInfo.arguments.contains("-screenshotCleanStore")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
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
        // Sorting asks the Worker with the web account's device token (tests and screenshot
        // runs returned above, so they never reach the network).
        WorkerSorter.token = { SyncAccount.readToken() }
        WorkerSorter.tokenRejected = { SyncAccount.tokenRejected() }
        SeedData.prepareSyncedStore(in: container.mainContext)
        _ = SyncChildTracking.install
        _ = CoverImageCache.watchMemoryPressure
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
    @State private var libraryWindow: LibraryWindow

    init(container: ModelContainer) {
        self.container = container
        _libraryWindow = State(initialValue: LibraryWindow.atLaunch(in: container.mainContext))
    }

    private var theme: AppTheme {
        let mode = ThemeAppearancePreference.resolvedColorMode(rawMode: rawMode, systemScheme: systemScheme)
        let accent = AccentColor.resolved(storedRawValue: rawAccent, for: mode)
        return AppTheme(mode: mode, accent: accent)
    }

    var body: some View {
        ContentView(libraryLimit: libraryWindow.limit)
            .environment(libraryWindow)
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
            // Keep the web copy (Stello account) in step with this library.
            .task { SyncBridge.shared.start(container: container) }
            // Write saves, edits and deletes to the folders in Settings › Folders.
            .task { FolderWriteObserver.shared.start(container: container) }
            // Safari extension test: let Stello in Safari read the folders through this app.
            .task { SafariBridge.start() }
            // Saves from Safari (menu, drop shelf, popup) and the share sheet's canvas row.
            .task { SafariInbox.shared.start(context: container.mainContext, coordinator: enrichmentCoordinator) }
            // Re-read the folders in Settings › Folders (changed files only).
            .task { FolderSources.shared.refreshAll() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    FolderSources.shared.refreshAll()
                    SafariBridge.publishBookmarks()
                    FolderWriteObserver.shared.poke()
                    SafariInbox.shared.processSoon()
                    Task { await WebInboxProcessor.shared.processPending() }
                    Task { await SyncBridge.shared.sync() }
                }
                #if os(iOS)
                if phase == .background { SyncBridge.scheduleBackgroundRefresh() }
                #endif
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
        if !SyncBridge.isDisabled { SyncBridge.registerBackgroundRefresh() }
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
