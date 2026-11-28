import Foundation

#if os(macOS)
/// Safari test (Nov 28 2026): lets the Stello Safari extension read the added folders.
///
/// Safari can't open a folder itself (WebKit opposes the folder-picking API), so the
/// extension asks this app. Two ways are tried, and the test page reports which works:
/// 1. Direct: the extension resolves a plain bookmark of each folder that the app leaves
///    in the shared App Group defaults. Likely blocked by the extension's sandbox.
/// 2. Relay: the extension sends the request to this app over a local message port
///    (name prefixed with the App Group, as the sandbox requires). The app must be running.
///
/// Read-only: list, read a text file, read a picture. Paths stay inside the folder.
@MainActor
enum SafariBridge {
    static let groupID = "group.com.arjunphlox.Stello"
    static let portName = groupID + ".safari-bridge"
    static let bookmarksKey = "stello.safariBridge.bookmarks"
    private static var port: CFMessagePort?

    static func start() {
        publishBookmarks()
        guard port == nil else { return }
        var context = CFMessagePortContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        var shouldFree: DarwinBoolean = false
        guard let local = CFMessagePortCreateLocal(nil, portName as CFString, { _, _, data, _ in
            let request = (data as Data?) ?? Data()
            let reply = MainActor.assumeIsolated { SafariBridge.handle(request) }
            return Unmanaged.passRetained(reply as CFData)
        }, &context, &shouldFree) else {
            print("SafariBridge: could not open port \(portName)")
            return
        }
        port = local
        let source = CFMessagePortCreateRunLoopSource(nil, local, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    /// Plain (not security-scoped) bookmarks for the direct test.
    static func publishBookmarks() {
        let sources = FolderSources.shared
        var out: [[String: Any]] = []
        for folder in sources.folders {
            guard let root = sources.roots[folder.id],
                  let data = try? root.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            else { continue }
            out.append(["id": folder.id.uuidString, "name": folder.name, "path": root.path, "bookmark": data])
        }
        UserDefaults(suiteName: groupID)?.set(out, forKey: bookmarksKey)
    }

    static func handle(_ data: Data) -> Data {
        let request = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let reply = SafariBridgeFiles.answer(request) { id in
            let sources = FolderSources.shared
            let folders = sources.folders.compactMap { f -> SafariBridgeFiles.Root? in
                guard let url = sources.roots[f.id] else { return nil }
                return SafariBridgeFiles.Root(id: f.id.uuidString, name: f.name, url: url)
            }
            return id == nil ? folders : folders.filter { $0.id == id }
        }
        return (try? JSONSerialization.data(withJSONObject: reply)) ?? Data("{}".utf8)
    }
}
#endif
