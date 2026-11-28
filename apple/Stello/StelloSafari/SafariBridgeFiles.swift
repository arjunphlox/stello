import Foundation

/// Folder reads shared by the Stello app (relay) and the Safari extension (direct test).
/// Commands: "list" (folders + item count + first few item paths), "read" (text file),
/// "image" (base64 picture). Paths are relative to a folder and may not leave it.
enum SafariBridgeFiles {
    struct Root { let id: String; let name: String; let url: URL }

    static let imageTypes: [String: String] = [
        "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "webp": "image/webp",
        "gif": "image/gif", "heic": "image/heic", "avif": "image/avif",
    ]

    static func answer(_ request: [String: Any], roots: (String?) -> [Root]) -> [String: Any] {
        let cmd = request["cmd"] as? String ?? ""
        let started = Date()
        var reply: [String: Any]
        switch cmd {
        case "list":
            reply = ["folders": roots(nil).map(list)]
        case "read", "image":
            guard let folder = request["folder"] as? String, let root = roots(folder).first,
                  let rel = request["path"] as? String, let url = inside(root.url, rel) else {
                reply = ["error": "Unknown folder or path"]
                break
            }
            let scoped = root.url.startAccessingSecurityScopedResource()
            defer { if scoped { root.url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                if cmd == "read" {
                    reply = ["text": String(decoding: data, as: UTF8.self), "bytes": data.count]
                } else {
                    let type = imageTypes[url.pathExtension.lowercased()] ?? "application/octet-stream"
                    reply = ["type": type, "base64": data.base64EncodedString(), "bytes": data.count]
                }
            } catch {
                reply = ["error": error.localizedDescription]
            }
        default:
            reply = ["error": "Unknown command \(cmd)"]
        }
        reply["ms"] = Int(Date().timeIntervalSince(started) * 1000)
        return reply
    }

    static func list(_ root: Root) -> [String: Any] {
        let scoped = root.url.startAccessingSecurityScopedResource()
        defer { if scoped { root.url.stopAccessingSecurityScopedResource() } }
        var items: [String] = []
        var images: [String] = []
        var error: String?
        let fm = FileManager.default
        if !fm.isReadableFile(atPath: root.url.path) { error = "Folder not readable from here" }
        let keys: [URLResourceKey] = [.isRegularFileKey]
        if let walker = fm.enumerator(at: root.url, includingPropertiesForKeys: keys,
                                      options: [.skipsHiddenFiles], errorHandler: { _, e in
                                          error = e.localizedDescription; return true }) {
            let base = root.url.standardizedFileURL.path + "/"
            for case let file as URL in walker {
                let path = file.standardizedFileURL.path
                guard path.hasPrefix(base) else { continue }
                let rel = String(path.dropFirst(base.count))
                let ext = file.pathExtension.lowercased()
                if ext == "md", rel.hasPrefix("items/") { items.append(rel) }
                else if imageTypes[ext] != nil, images.count < 20 { images.append(rel) }
            }
        }
        items.sort(by: >)
        var out: [String: Any] = ["id": root.id, "name": root.name, "itemCount": items.count,
                                  "firstItems": Array(items.prefix(5)), "firstImages": Array(images.prefix(5))]
        if let error { out["error"] = error }
        return out
    }

    /// The file URL for a relative path, or nil if it would leave the folder.
    static func inside(_ root: URL, _ rel: String) -> URL? {
        let base = root.standardizedFileURL.path + "/"
        let url = root.appendingPathComponent(rel).standardizedFileURL
        return url.path.hasPrefix(base) ? url : nil
    }
}
