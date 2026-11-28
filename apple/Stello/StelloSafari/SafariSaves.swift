import Foundation
#if os(macOS)
import AppKit
#endif

/// The extension side of saving from Safari: answers "canvases", "save" and "status".
///
/// - canvases → `{ canvases: [{ id, name }] }`, the list the app last shared.
/// - save { entries: [{ kind, url, page?, title? }], canvas?, newName?, groupName?, from }
///   → `{ queued, id, app: "running" | "opening" | "later" }`. The request waits in the App
///   Group (`SafariSaveInbox`) for the app; on the Mac the app is told at once, or opened in
///   the background if it isn't running.
/// - status { id } → `{ done: false }` or `{ done: true, text, canvas? }`.
enum SafariSaves {
    static func answer(_ message: [String: Any]) -> [String: Any] {
        switch message["cmd"] as? String {
        case "canvases":
            return ["canvases": SafariSaveInbox.canvases().map { ["id": $0.id, "name": $0.name] }]
        case "status":
            guard let id = message["id"] as? String else { return ["error": "No id"] }
            guard let done = SafariSaveInbox.done(id) else { return ["done": false] }
            var out: [String: Any] = ["done": true, "text": done["text"] as? String ?? "Saved"]
            if let canvas = done["canvas"] { out["canvas"] = canvas }
            return out
        case "save":
            return save(message)
        default:
            return ["error": "Unknown command"]
        }
    }

    static func save(_ message: [String: Any]) -> [String: Any] {
        let raw = message["entries"] as? [[String: Any]] ?? []
        var seen = Set<String>()
        let entries: [SafariSaveInbox.Entry] = raw.compactMap { e in
            guard let url = e["url"] as? String, url.hasPrefix("http"), url.count < 4000,
                  seen.insert(url).inserted else { return nil }
            let kind = e["kind"] as? String == "image" ? "image" : "link"
            return .init(kind: kind, url: url, page: e["page"] as? String,
                         title: (e["title"] as? String).map { String($0.prefix(300)) })
        }
        guard !entries.isEmpty else { return ["error": "Nothing to save"] }
        let id = UUID().uuidString.lowercased()
        let request = SafariSaveInbox.Request(
            id: id, at: Date(),
            canvas: (message["canvas"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            newName: message["newName"] as? String,
            groupName: (message["groupName"] as? String).map { String($0.prefix(60)) },
            entries: Array(entries.prefix(200)),
            from: message["from"] as? String ?? "safari"
        )
        guard SafariSaveInbox.enqueue(request) else { return ["error": "Stello can't be reached. Open the Stello app once, then try again."] }
        return ["queued": true, "id": id, "count": request.entries.count, "app": tellApp()]
    }

    /// Mac: poke the running app, or open it in the background. iPhone and iPad: the app
    /// saves these the next time it opens.
    static func tellApp() -> String {
        #if os(macOS)
        if let remote = CFMessagePortCreateRemote(nil, SafariSaveInbox.portName as CFString),
           let body = try? JSONSerialization.data(withJSONObject: ["cmd": "inbox"]) {
            var out: Unmanaged<CFData>?
            let status = CFMessagePortSendRequest(remote, 0, body as CFData, 2, 2,
                                                  CFRunLoopMode.defaultMode.rawValue, &out)
            _ = out?.takeRetainedValue()
            if status == kCFMessagePortSuccess { return "running" }
        }
        // StelloSafari.appex sits in Stello.app/Contents/PlugIns.
        let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard app.pathExtension == "app" else { return "later" }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        config.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: app, configuration: config, completionHandler: nil)
        return "opening"
        #else
        return "later"
        #endif
    }
}
