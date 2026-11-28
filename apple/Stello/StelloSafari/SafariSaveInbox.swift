import Foundation

/// Saves from Safari (right-click menu, drop shelf, toolbar popup) and the share sheet's
/// "Add to a canvas" row, waiting for the Stello app.
///
/// The extensions never write the folders or the library themselves: each save is one small
/// JSON request in the App Group's `SafariInbox/` folder. The app picks it up (at once on the
/// Mac when it's running, otherwise the next time it opens), saves each web address through
/// the normal capture path, which writes the item file to the folder, places the new items on
/// the chosen canvas, and deletes the request.
///
/// The app also leaves the list of canvases in the App Group defaults so Safari can show them.
nonisolated enum SafariSaveInbox {
    static let groupID = "group.com.arjunphlox.Stello"
    /// Canvases Safari can offer, newest first: `[[id, name]]` with the open one first.
    static let canvasesKey = "stello.safari.canvases"
    /// What happened to the last saves, newest first: `[[id, text, canvas?, at]]`.
    static let doneKey = "stello.safari.done"
    /// Mac: the app's local port, also used by the folder test (`SafariBridge`).
    static let portName = groupID + ".safari-bridge"

    struct Entry: Codable, Equatable, Sendable {
        /// "link" (a web address) or "image" (a picture's address, `page` is where it was).
        var kind: String
        var url: String
        var page: String?
        var title: String?
    }

    struct Request: Codable, Equatable, Sendable {
        var id: String
        var at: Date
        /// nil = the grid only; a canvas id; or "new" with `newName`.
        var canvas: String?
        var newName: String?
        /// Names the group of cards when more than one lands on a canvas (the page's title).
        var groupName: String?
        var entries: [Entry]
        /// "safari-menu", "safari-drop", "safari-popup" or "share".
        var from: String
    }

    static var folder: URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else { return nil }
        let dir = base.appending(path: "SafariInbox", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var defaults: UserDefaults? { UserDefaults(suiteName: groupID) }

    /// Writes one request. Returns false if the App Group can't be reached.
    @discardableResult
    static func enqueue(_ request: Request) -> Bool {
        guard let dir = folder else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(request) else { return false }
        let url = dir.appending(path: "\(Int(request.at.timeIntervalSince1970 * 1000))-\(request.id).json")
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// Waiting requests, oldest first.
    static func pending() -> [(URL, Request)] {
        guard let dir = folder,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let request = try? decoder.decode(Request.self, from: data) else {
                    // A broken request would block nothing but would stay forever: drop it.
                    try? FileManager.default.removeItem(at: url)
                    return nil
                }
                return (url, request)
            }
    }

    static func remove(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    // MARK: - Canvases for Safari

    struct CanvasEntry: Equatable, Sendable { var id: String; var name: String }

    static func publishCanvases(_ list: [CanvasEntry]) {
        let out = list.prefix(12).map { ["id": $0.id, "name": $0.name] }
        defaults?.set(Array(out), forKey: canvasesKey)
    }

    static func canvases() -> [CanvasEntry] {
        let raw = defaults?.array(forKey: canvasesKey) as? [[String: String]] ?? []
        return raw.compactMap { d in d["id"].flatMap { id in d["name"].map { CanvasEntry(id: id, name: $0) } } }
    }

    // MARK: - Done list (so Safari can say "Added")

    static func markDone(_ id: String, text: String, canvas: String?) {
        var list = defaults?.array(forKey: doneKey) as? [[String: Any]] ?? []
        var entry: [String: Any] = ["id": id, "text": text, "at": Date().timeIntervalSince1970]
        if let canvas { entry["canvas"] = canvas }
        list.insert(entry, at: 0)
        defaults?.set(Array(list.prefix(20)), forKey: doneKey)
    }

    static func done(_ id: String) -> [String: Any]? {
        (defaults?.array(forKey: doneKey) as? [[String: Any]])?.first { $0["id"] as? String == id }
    }
}
