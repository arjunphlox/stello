import Foundation
import SafariServices

/// Stello Safari extension, test build (Nov 28 2026): answers the extension's messages
/// by reading the person's added folders. Each message names a route:
/// - "direct": this extension reads the folder itself, from the plain bookmarks the
///   Stello app leaves in the shared App Group defaults.
/// - "relay": the request goes to the running Stello app over its local message port.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    static let groupID = "group.com.arjunphlox.Stello"
    static let portName = groupID + ".safari-bridge"
    static let bookmarksKey = "stello.safariBridge.bookmarks"

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any] ?? [:]
        let route = message["route"] as? String ?? "relay"
        let started = Date()
        var reply = route == "direct" ? Self.direct(message) : Self.relay(message)
        reply["route"] = route
        reply["totalMs"] = Int(Date().timeIntervalSince(started) * 1000)

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: reply]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }

    static func direct(_ message: [String: Any]) -> [String: Any] {
        guard let defaults = UserDefaults(suiteName: groupID) else {
            return ["error": "No App Group defaults"]
        }
        let saved = defaults.array(forKey: bookmarksKey) as? [[String: Any]] ?? []
        if saved.isEmpty { return ["error": "The Stello app has not shared any folders yet (open it once)"] }
        var resolveErrors: [String] = []
        let roots: [SafariBridgeFiles.Root] = saved.compactMap { entry in
            guard let id = entry["id"] as? String, let name = entry["name"] as? String,
                  let data = entry["bookmark"] as? Data else { return nil }
            var stale = false
            do {
                let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
                return SafariBridgeFiles.Root(id: id, name: name, url: url)
            } catch {
                resolveErrors.append("\(name): \(error.localizedDescription)")
                return nil
            }
        }
        var reply = SafariBridgeFiles.answer(message) { id in id == nil ? roots : roots.filter { $0.id == id } }
        if !resolveErrors.isEmpty { reply["resolveErrors"] = resolveErrors }
        return reply
    }

    static func relay(_ message: [String: Any]) -> [String: Any] {
        guard let remote = CFMessagePortCreateRemote(nil, portName as CFString) else {
            return ["error": "Stello app is not running, or its port is blocked"]
        }
        guard let body = try? JSONSerialization.data(withJSONObject: message) else {
            return ["error": "Bad message"]
        }
        var out: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(remote, 0, body as CFData, 10, 30,
                                              CFRunLoopMode.defaultMode.rawValue, &out)
        guard status == kCFMessagePortSuccess, let data = out?.takeRetainedValue() as Data? else {
            return ["error": "Relay failed (status \(status))"]
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? ["error": "Bad reply"]
    }
}
