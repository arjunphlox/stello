import Foundation

/// Minimal Supabase Auth (GoTrue) REST client for the native apps.
///
/// Covers only what account linking needs: Sign in with Apple (ID token
/// exchange), passkey sign-in and registration (Supabase's built-in passkey
/// endpoints, the same ones supabase-js uses on the web), token refresh and
/// sign-out. No third-party SDK, so nothing new to resolve in the project.
nonisolated struct SupabaseAuthClient: Sendable {
    /// Same project + publishable key the web app ships (`supabase-client.js`).
    /// The publishable key is safe to embed; RLS protects the data.
    static let projectURL = URL(string: "https://ngncjtzsqrrfrhgammne.supabase.co")!
    static let publishableKey = "sb_publishable_r7udhKoy2jEtBrcbKY1wGg_LFn-wMjR"

    /// Passkey relying party. Must match Supabase Auth's passkey RP ID and the
    /// `webcredentials:` associated domain in Stello.entitlements.
    static let relyingPartyID = "stello.arjunphlox.workers.dev"

    var baseURL: URL = projectURL.appending(path: "auth/v1")
    var session: URLSession = .shared

    // MARK: - Models

    struct Session: Codable, Sendable, Equatable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var user: User

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresAt = "expires_at"
            case expiresIn = "expires_in"
            case user
        }

        init(accessToken: String, refreshToken: String, expiresAt: Date, user: User) {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.expiresAt = expiresAt
            self.user = user
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            accessToken = try c.decode(String.self, forKey: .accessToken)
            refreshToken = try c.decode(String.self, forKey: .refreshToken)
            user = try c.decode(User.self, forKey: .user)
            if let at = try c.decodeIfPresent(Double.self, forKey: .expiresAt) {
                expiresAt = Date(timeIntervalSince1970: at)
            } else {
                let expiresIn = try c.decodeIfPresent(Double.self, forKey: .expiresIn) ?? 3600
                expiresAt = Date().addingTimeInterval(expiresIn)
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(accessToken, forKey: .accessToken)
            try c.encode(refreshToken, forKey: .refreshToken)
            try c.encode(expiresAt.timeIntervalSince1970, forKey: .expiresAt)
            try c.encode(user, forKey: .user)
        }

        /// Refresh a minute early so requests never go out with a dead token.
        var needsRefresh: Bool { expiresAt.timeIntervalSinceNow < 60 }
    }

    struct User: Codable, Sendable, Equatable {
        var id: String
        var email: String?
    }

    struct Passkey: Codable, Sendable, Identifiable, Equatable {
        var id: String
        var friendlyName: String?
        var createdAt: String
        var lastUsedAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case friendlyName = "friendly_name"
            case createdAt = "created_at"
            case lastUsedAt = "last_used_at"
        }
    }

    /// `POST /passkeys/authentication/options` → WebAuthn request options (JSON form).
    struct PasskeyAssertionChallenge: Decodable, Sendable {
        var challengeID: String
        var challenge: Data
        var rpID: String

        enum CodingKeys: String, CodingKey { case challengeID = "challenge_id", options }
        enum OptionKeys: String, CodingKey { case challenge, rpId }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            challengeID = try c.decode(String.self, forKey: .challengeID)
            let o = try c.nestedContainer(keyedBy: OptionKeys.self, forKey: .options)
            challenge = try Base64URL.decode(o.decode(String.self, forKey: .challenge))
            rpID = try o.decodeIfPresent(String.self, forKey: .rpId) ?? SupabaseAuthClient.relyingPartyID
        }
    }

    /// `POST /passkeys/registration/options` → WebAuthn creation options (JSON form).
    struct PasskeyRegistrationChallenge: Decodable, Sendable {
        var challengeID: String
        var challenge: Data
        var rpID: String
        var userID: Data
        var userName: String

        enum CodingKeys: String, CodingKey { case challengeID = "challenge_id", options }
        enum OptionKeys: String, CodingKey { case challenge, rp, user }
        enum RPKeys: String, CodingKey { case id }
        enum UserKeys: String, CodingKey { case id, name }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            challengeID = try c.decode(String.self, forKey: .challengeID)
            let o = try c.nestedContainer(keyedBy: OptionKeys.self, forKey: .options)
            challenge = try Base64URL.decode(o.decode(String.self, forKey: .challenge))
            let rp = try o.nestedContainer(keyedBy: RPKeys.self, forKey: .rp)
            rpID = try rp.decodeIfPresent(String.self, forKey: .id) ?? SupabaseAuthClient.relyingPartyID
            let user = try o.nestedContainer(keyedBy: UserKeys.self, forKey: .user)
            userID = try Base64URL.decode(user.decode(String.self, forKey: .id))
            userName = try user.decode(String.self, forKey: .name)
        }
    }

    struct APIError: LocalizedError, Sendable {
        var status: Int
        var code: String?
        var message: String
        var errorDescription: String? { message }
    }

    // MARK: - Sign in

    /// Exchange an Apple ID token for a Supabase session. `rawNonce` is the
    /// unhashed nonce whose SHA-256 went into the Apple request.
    func signInWithApple(idToken: String, rawNonce: String) async throws -> Session {
        try await send("token?grant_type=id_token", body: [
            "provider": "apple",
            "id_token": idToken,
            "nonce": rawNonce,
        ])
    }

    func refresh(_ refreshToken: String) async throws -> Session {
        try await send("token?grant_type=refresh_token", body: ["refresh_token": refreshToken])
    }

    func signOut(accessToken: String) async {
        let _: Empty? = try? await send("logout", body: [String: String](), accessToken: accessToken)
    }

    // MARK: - Passkeys

    func passkeyAssertionChallenge() async throws -> PasskeyAssertionChallenge {
        try await send("passkeys/authentication/options", body: [String: String]())
    }

    func verifyPasskeyAssertion(challengeID: String, credential: [String: Any]) async throws -> Session {
        try await send("passkeys/authentication/verify", json: [
            "challenge_id": challengeID,
            "credential": credential,
        ])
    }

    func passkeyRegistrationChallenge(accessToken: String) async throws -> PasskeyRegistrationChallenge {
        try await send("passkeys/registration/options", body: [String: String](), accessToken: accessToken)
    }

    func verifyPasskeyRegistration(challengeID: String, credential: [String: Any], accessToken: String) async throws {
        let _: Empty = try await send("passkeys/registration/verify", json: [
            "challenge_id": challengeID,
            "credential": credential,
        ], accessToken: accessToken)
    }

    func listPasskeys(accessToken: String) async throws -> [Passkey] {
        try await send("passkeys", method: "GET", accessToken: accessToken)
    }

    func deletePasskey(id: String, accessToken: String) async throws {
        let _: Empty? = try await send("passkeys/\(id)", method: "DELETE", accessToken: accessToken)
    }

    // MARK: - Transport

    private struct Empty: Decodable, Sendable {}

    private func send<T: Decodable, B: Encodable>(
        _ path: String, method: String = "POST", body: B, accessToken: String? = nil
    ) async throws -> T {
        try await perform(path, method: method, body: try JSONEncoder().encode(body), accessToken: accessToken)
    }

    private func send<T: Decodable>(
        _ path: String, method: String = "POST", json: [String: Any], accessToken: String? = nil
    ) async throws -> T {
        try await perform(path, method: method, body: try JSONSerialization.data(withJSONObject: json), accessToken: accessToken)
    }

    private func send<T: Decodable>(_ path: String, method: String, accessToken: String?) async throws -> T {
        try await perform(path, method: method, body: nil, accessToken: accessToken)
    }

    private func perform<T: Decodable>(_ path: String, method: String, body: Data?, accessToken: String?) async throws -> T {
        guard let url = URL(string: baseURL.absoluteString + "/" + path) else {
            throw APIError(status: 0, code: nil, message: "Bad auth URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(Self.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = payload?["msg"] as? String
                ?? payload?["message"] as? String
                ?? payload?["error_description"] as? String
                ?? "Sign-in failed (\(status))"
            throw APIError(status: status, code: payload?["error_code"] as? String, message: message)
        }
        if data.isEmpty || T.self == Empty.self {
            return try JSONDecoder().decode(T.self, from: Data("{}".utf8))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// base64url without padding, the encoding WebAuthn JSON uses.
nonisolated enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ string: String) throws -> Data {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        guard let data = Data(base64Encoded: s) else {
            throw SupabaseAuthClient.APIError(status: 0, code: nil, message: "Malformed passkey challenge")
        }
        return data
    }
}
