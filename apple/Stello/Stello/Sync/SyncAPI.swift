import Foundation
import Security

/// HTTP client for the Stello Worker's `/api/sync/*` routes (the web copy of the library).
/// Wire shapes match `src/lib/sync.js`; see docs/plans/apple-web-sync.md.
nonisolated struct SyncAPI: Sendable {
    static let baseURL = URL(string: "https://stello.arjunphlox.workers.dev")!

    let token: String
    var session: URLSession = .shared

    struct PullPage: Decodable, Sendable {
        let items: [SyncWire.Row]
        let cursor: Int
        let more: Bool
    }

    struct PushResult: Decodable, Sendable {
        struct Entry: Decodable, Sendable { let id: String?; let status: String }
        let results: [Entry]
        let cursor: Int
    }

    struct ImageResult: Decodable, Sendable { let path: String }

    enum Failure: Error, Sendable {
        case unauthorized
        case server(Int, String)
    }

    func pull(since: Int, limit: Int = 500) async throws -> PullPage {
        var url = URLComponents(url: Self.baseURL.appending(path: "api/sync/pull"), resolvingAgainstBaseURL: false)!
        url.queryItems = [.init(name: "since", value: String(since)), .init(name: "limit", value: String(limit))]
        return try await send(URLRequest(url: url.url!))
    }

    func push(_ changes: [SyncWire.Change]) async throws -> PushResult {
        var request = URLRequest(url: Self.baseURL.appending(path: "api/sync/push"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["changes": changes.map(\.json)])
        return try await send(request)
    }

    func uploadImage(_ data: Data, contentType: String) async throws -> String {
        var request = URLRequest(url: Self.baseURL.appending(path: "api/sync/image"))
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let result: ImageResult = try await send(request)
        return result.path
    }

    /// Bytes behind a `/img/<key>` path (or any absolute URL).
    func downloadImage(path: String) async throws -> Data {
        let url = path.hasPrefix("http") ? URL(string: path)! : Self.baseURL.appending(path: String(path.dropFirst()))
        let (data, response) = try await session.data(from: url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw Failure.server(code, "image") }
        return data
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw Failure.unauthorized }
        guard (200..<300).contains(code) else {
            throw Failure.server(code, String(decoding: data.prefix(300), as: UTF8.self))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// The device's sign-in to the Stello web account. One Sign in with Apple, exchanged
/// for a long-lived device token kept in the Keychain.
@Observable
@MainActor
final class SyncAccount {
    static let shared = SyncAccount()

    private(set) var isSignedIn = false
    private(set) var lastError: String?

    private nonisolated static let service = "com.arjunphlox.Stello.webSync"
    private nonisolated static let account = "deviceToken"

    private init() { isSignedIn = Self.readToken() != nil }

    nonisolated static var api: SyncAPI? { readToken().map { SyncAPI(token: $0) } }

    /// `identityToken` from `ASAuthorizationAppleIDCredential`; `nonce` is the raw nonce
    /// whose SHA-256 went into the request.
    func signIn(identityToken: Data, nonce: String?) async {
        lastError = nil
        do {
            var request = URLRequest(url: SyncAPI.baseURL.appending(path: "api/auth/apple/native"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var body: [String: Any] = [
                "identityToken": String(decoding: identityToken, as: UTF8.self),
                "deviceName": Self.deviceName,
            ]
            if let nonce { body["nonce"] = nonce }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["token"] as? String
            else {
                lastError = "Couldn't sign in (\(code))."
                return
            }
            Self.writeToken(token)
            isSignedIn = true
            SyncBridge.requestSync(reason: "signed in")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() {
        Self.deleteToken()
        isSignedIn = false
        SyncBridge.resetState()
    }

    /// Called when the server rejects the token (revoked or expired).
    nonisolated static func tokenRejected() {
        deleteToken()
        Task { @MainActor in shared.isSignedIn = false }
    }

    private static var deviceName: String {
        #if os(macOS)
        Host.current().localizedName ?? "Mac"
        #else
        "iPhone"
        #endif
    }

    // MARK: Keychain

    private nonisolated static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    nonisolated static func readToken() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private nonisolated static func writeToken(_ token: String) {
        deleteToken()
        var q = query
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock // background refresh
        SecItemAdd(q as CFDictionary, nil)
    }

    private nonisolated static func deleteToken() {
        SecItemDelete(query as CFDictionary)
    }
}
