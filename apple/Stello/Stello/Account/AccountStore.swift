import AuthenticationServices
import CryptoKit
import Foundation
import Security

/// Optional link between the native app and the user's Stello web account
/// (Supabase Auth). The app stays iCloud-first and fully usable signed out;
/// a linked account is what the Supabase import (and later sync) will use.
///
/// Sign-in methods: Sign in with Apple and passkeys. Passkeys are shared with
/// the web app through the `webcredentials:` associated domain, so a passkey
/// made on stello.arjunphlox.workers.dev works here and vice versa.
@Observable
@MainActor
final class AccountStore {
    static let shared = AccountStore()

    private(set) var session: SupabaseAuthClient.Session?
    private(set) var passkeys: [SupabaseAuthClient.Passkey] = []
    var isWorking = false
    var lastError: String?

    var isSignedIn: Bool { session != nil }
    var email: String? { session?.user.email }

    private let client = SupabaseAuthClient()
    private let keychain = SessionKeychain()

    private init() {
        session = keychain.load()
    }

    // MARK: - Sign in with Apple

    /// Builds the Apple ID request. Keep the returned raw nonce for `completeApple`.
    func makeAppleRequest() -> (ASAuthorizationAppleIDRequest, rawNonce: String) {
        let rawNonce = Self.randomNonce()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email, .fullName]
        request.nonce = Self.sha256(rawNonce)
        return (request, rawNonce)
    }

    func completeApple(_ credential: ASAuthorizationAppleIDCredential, rawNonce: String) async {
        await run {
            guard let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                throw SupabaseAuthClient.APIError(status: 0, code: nil, message: "Apple didn't return an identity token.")
            }
            let session = try await self.client.signInWithApple(idToken: idToken, rawNonce: rawNonce)
            self.store(session)
        }
    }

    // MARK: - Passkeys

    /// Fetches a sign-in challenge and builds the platform passkey request.
    func makePasskeyAssertionRequest() async -> (ASAuthorizationPlatformPublicKeyCredentialAssertionRequest, challengeID: String)? {
        var result: (ASAuthorizationPlatformPublicKeyCredentialAssertionRequest, String)?
        await run {
            let challenge = try await self.client.passkeyAssertionChallenge()
            let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: challenge.rpID)
            result = (provider.createCredentialAssertionRequest(challenge: challenge.challenge), challenge.challengeID)
        }
        return result
    }

    func completePasskeyAssertion(_ assertion: ASAuthorizationPlatformPublicKeyCredentialAssertion, challengeID: String) async {
        await run {
            let credentialID = Base64URL.encode(assertion.credentialID)
            var response: [String: Any] = [
                "clientDataJSON": Base64URL.encode(assertion.rawClientDataJSON),
                "authenticatorData": Base64URL.encode(assertion.rawAuthenticatorData),
                "signature": Base64URL.encode(assertion.signature),
            ]
            if let userID = assertion.userID, !userID.isEmpty {
                response["userHandle"] = Base64URL.encode(userID)
            }
            let credential: [String: Any] = [
                "id": credentialID,
                "rawId": credentialID,
                "type": "public-key",
                "response": response,
                "clientExtensionResults": [String: Any](),
                "authenticatorAttachment": "platform",
            ]
            let session = try await self.client.verifyPasskeyAssertion(challengeID: challengeID, credential: credential)
            self.store(session)
        }
    }

    /// Fetches a registration challenge for the signed-in user.
    func makePasskeyRegistrationRequest() async -> (ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest, challengeID: String)? {
        var result: (ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest, String)?
        await run {
            let token = try await self.validAccessToken()
            let challenge = try await self.client.passkeyRegistrationChallenge(accessToken: token)
            let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: challenge.rpID)
            let request = provider.createCredentialRegistrationRequest(
                challenge: challenge.challenge,
                name: challenge.userName,
                userID: challenge.userID
            )
            result = (request, challenge.challengeID)
        }
        return result
    }

    func completePasskeyRegistration(_ registration: ASAuthorizationPlatformPublicKeyCredentialRegistration, challengeID: String) async {
        await run {
            guard let attestation = registration.rawAttestationObject else {
                throw SupabaseAuthClient.APIError(status: 0, code: nil, message: "The passkey had no attestation data.")
            }
            let credentialID = Base64URL.encode(registration.credentialID)
            let credential: [String: Any] = [
                "id": credentialID,
                "rawId": credentialID,
                "type": "public-key",
                "response": [
                    "clientDataJSON": Base64URL.encode(registration.rawClientDataJSON),
                    "attestationObject": Base64URL.encode(attestation),
                    "transports": ["internal", "hybrid"],
                ],
                "clientExtensionResults": [String: Any](),
                "authenticatorAttachment": "platform",
            ]
            let token = try await self.validAccessToken()
            try await self.client.verifyPasskeyRegistration(challengeID: challengeID, credential: credential, accessToken: token)
            self.passkeys = try await self.client.listPasskeys(accessToken: token)
        }
    }

    func refreshPasskeys() async {
        guard isSignedIn else { passkeys = []; return }
        await run {
            let token = try await self.validAccessToken()
            self.passkeys = try await self.client.listPasskeys(accessToken: token)
        }
    }

    func deletePasskey(_ passkey: SupabaseAuthClient.Passkey) async {
        await run {
            let token = try await self.validAccessToken()
            try await self.client.deletePasskey(id: passkey.id, accessToken: token)
            self.passkeys.removeAll { $0.id == passkey.id }
        }
    }

    // MARK: - Session

    /// Access token for Stello API calls, refreshed when close to expiry.
    func validAccessToken() async throws -> String {
        guard let current = session else {
            throw SupabaseAuthClient.APIError(status: 401, code: nil, message: "Not signed in.")
        }
        guard current.needsRefresh else { return current.accessToken }
        do {
            let refreshed = try await client.refresh(current.refreshToken)
            store(refreshed)
            return refreshed.accessToken
        } catch let error as SupabaseAuthClient.APIError where (400..<500).contains(error.status) {
            // Refresh token revoked or expired: drop the link so the UI asks again.
            clearSession()
            throw error
        }
    }

    func signOut() async {
        if let token = session?.accessToken {
            await client.signOut(accessToken: token)
        }
        clearSession()
    }

    /// Records a failed or cancelled authorization from the system sheet.
    func report(_ error: Error) {
        if let auth = error as? ASAuthorizationError, auth.code == .canceled { return }
        lastError = error.localizedDescription
    }

    private func store(_ newSession: SupabaseAuthClient.Session) {
        session = newSession
        keychain.save(newSession)
    }

    private func clearSession() {
        session = nil
        passkeys = []
        keychain.delete()
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) async {
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            try await work()
        } catch {
            report(error)
        }
    }

    // MARK: - Nonce

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Stores the Supabase session in the Keychain (this device only, not iCloud Keychain).
private struct SessionKeychain {
    private let service = "com.phloxpage.Stello.account"
    private let account = "supabase-session"

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    func load() -> SupabaseAuthClient.Session? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(SupabaseAuthClient.Session.self, from: data)
    }

    func save(_ session: SupabaseAuthClient.Session) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add.merge(attributes) { $1 }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
