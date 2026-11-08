import Foundation

/// What the Worker's page readers made of a saved link (`POST /api/classify`).
///
/// The Worker is the one copy of the sorting rules (kind + typed metadata), shared with web
/// saves. The app still fetches the page itself (device IP, so bot walls behave as before)
/// and sends the HTML; the answer's metadata is already in the JSON shape the meta structs
/// encode to, so it goes straight into `item.metadataJSON`.
nonisolated struct WorkerRead: Sendable {
    var kind: ItemKind
    var title: String?
    var summary: String?
    var extractedText: String?
    var domain: String?
    var isGone: Bool
    /// Ready for `item.metadataJSON`; nil for a plain link.
    var metadataJSON: String?
    /// Cover first (product gallery / post media / music cover / og:image).
    var imageURLs: [URL]
    /// "product", "post" or "og".
    var imageSource: String
    /// Tried in order when `imageURLs` all fail (og:image behind a gallery, book covers).
    var fallbackImageURLs: [URL]
    var confidence: Double

    func meta<T: Decodable>(_ type: T.Type) -> T? {
        guard let metadataJSON else { return nil }
        return try? JSONDecoder().decode(T.self, from: Data(metadataJSON.utf8))
    }

    /// Parses one `/api/classify` answer; nil for an error answer.
    init?(json: [String: Any]) {
        guard json["error"] == nil,
              let raw = json["kind"] as? String,
              let kind = ItemKind(rawValue: raw) else { return nil }
        self.kind = kind
        title = Self.text(json["title"])
        summary = Self.text(json["summary"])
        extractedText = Self.text(json["extractedText"])
        domain = Self.text(json["domain"])
        isGone = (json["status"] as? String) == "gone"
        if let meta = json["metadata"], !(meta is NSNull),
           JSONSerialization.isValidJSONObject(meta),
           let data = try? JSONSerialization.data(withJSONObject: meta, options: [.sortedKeys]) {
            metadataJSON = String(decoding: data, as: UTF8.self)
        } else {
            metadataJSON = nil
        }
        let images = json["images"] as? [String: Any] ?? [:]
        imageURLs = Self.urls(images["urls"])
        imageSource = images["source"] as? String ?? "og"
        fallbackImageURLs = Self.urls(images["fallbacks"])
        confidence = (json["confidence"] as? NSNumber)?.doubleValue ?? 0
    }

    private static func text(_ value: Any?) -> String? {
        guard let s = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    private static func urls(_ value: Any?) -> [URL] {
        (value as? [String] ?? []).compactMap { URL(string: $0) }
    }
}

/// Client for the Worker's page readers. Needs the Stello web sign-in (the sync device
/// token); without it, or offline, every call answers nil and the caller keeps the item a
/// plain link with `unsortedStatus`, so the background pass sorts it on a later launch.
nonisolated enum WorkerSorter {
    /// A link waiting for the Worker's rules: imports, web saves the web couldn't type, and
    /// saves made while the Worker was out of reach. `WebLibraryImporter.readPages` sorts
    /// them (kind only; fields come with Enrich).
    static let unsortedStatus = "awaiting_classify"
    /// The Worker (same host as `SyncAPI.baseURL`).
    static let baseURL = URL(string: "https://stello.arjunphlox.workers.dev")!

    /// The web account's device token. The app wires this to `SyncAccount` at launch; the
    /// share extension has no web sign-in, so its saves stay unsorted for the app to sort.
    nonisolated(unsafe) static var token: @Sendable () -> String? = { nil }
    /// Called when the Worker rejects the token.
    nonisolated(unsafe) static var tokenRejected: @Sendable () -> Void = {}

    static var canSort: Bool { token() != nil }

    /// HTML beyond this is never sent (the Worker reads at most 2 MB too).
    static let maxHTMLBytes = 2_000_000

    /// Kinds Enrich reads an item as again (the Worker's `READ_AS_KINDS`).
    static let readAsKinds: Set<ItemKind> = [.post, .product, .resource, .book, .tool, .course, .article, .music]

    /// Kinds a plain link may become on Enrich or a later sort.
    static let linkKinds: Set<ItemKind> = [.post, .product, .resource, .book, .tool, .course, .article, .music]

    /// The `asKind` for an item of `kind`, or nil to classify from scratch.
    static func asKind(for kind: String) -> String? {
        guard let k = ItemKind(rawValue: kind), readAsKinds.contains(k) else { return nil }
        return k.rawValue
    }

    /// Reads one page. `page == nil` means the app couldn't fetch it: the URL and labels
    /// decide, and the Worker never fetches it either. `kindOnly` skips the field readers
    /// (the import only needs the kind).
    static func read(
        url: URL,
        page: PageFetchResult?,
        labels: [String] = [],
        asKind: String? = nil,
        kindOnly: Bool = false,
        session: URLSession = .shared
    ) async -> WorkerRead? {
        guard let deviceToken = token() else { return nil }
        var body: [String: Any] = ["url": url.absoluteString, "html": ""]
        if let page {
            body["html"] = String(decoding: page.html.utf8.prefix(maxHTMLBytes), as: UTF8.self)
            if let status = page.statusCode { body["status"] = status }
            if let finalURL = page.finalURL { body["finalURL"] = finalURL.absoluteString }
        }
        if !labels.isEmpty { body["collectionLabels"] = labels }
        if let asKind { body["asKind"] = asKind }
        if kindOnly { body["kindOnly"] = true }
        guard let json = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: baseURL.appending(path: "api/classify"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        // Raw DEFLATE (Apple's `.zlib` is RFC 1951 without a header): pages shrink 5-10x,
        // which is most of an import's upload.
        if let packed = try? (json as NSData).compressed(using: .zlib) as Data {
            request.setValue("deflate-raw", forHTTPHeaderField: "X-Stello-Encoding")
            request.httpBody = packed
        } else {
            request.httpBody = json
        }

        guard let (data, response) = try? await session.data(for: request) else { return nil }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 {
            tokenRejected()
            return nil
        }
        guard code == 200,
              let answer = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return WorkerRead(json: answer)
    }
}
