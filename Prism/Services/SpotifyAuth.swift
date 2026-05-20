import AppKit
import CryptoKit
import Foundation

// Spotify OAuth using the Authorization Code flow with PKCE.
// PKCE needs only a Client ID (no secret), so nothing sensitive is ever committed.
@MainActor
final class SpotifyAuth {
    static let shared = SpotifyAuth()

    enum AuthError: LocalizedError {
        case missingClientID
        case portInUse
        case denied(String)
        case stateMismatch
        case timedOut
        case tokenExchangeFailed(String)
        case notAuthorized

        var errorDescription: String? {
            switch self {
            case .missingClientID:
                return "No Spotify Client ID is set. Add one in Settings."
            case .portInUse:
                return "Port 8888 is in use. Quit whatever is using it and try again."
            case .denied(let reason):
                return "Spotify authorization was declined (\(reason))."
            case .stateMismatch:
                return "The authorization response failed a security check. Please try again."
            case .timedOut:
                return "The Spotify connection timed out. Please try again."
            case .tokenExchangeFailed(let detail):
                return "Could not complete the Spotify sign-in. \(detail)"
            case .notAuthorized:
                return "Not connected to Spotify."
            }
        }
    }

    private let redirectPort: UInt16 = 8888
    var redirectURI: String { "http://127.0.0.1:\(redirectPort)/callback" }

    private let scopes = [
        "user-library-read",
        "user-library-modify",
        "playlist-read-private",
        "playlist-read-collaborative",
        "user-top-read",
        "user-read-recently-played",
        "user-follow-read",
        "playlist-modify-private",
        "playlist-modify-public",
        "streaming",
        "user-read-email",
        "user-read-private",
        "user-modify-playback-state",
    ]

    private let clientIDKey = "spotifyClientID"
    private let tokenAccount = "refreshToken"
    private let grantedScopesKey = "spotifyGrantedScopes"

    private var accessToken: String?
    private var refreshToken: String?
    private var expiresAt: Date?
    private var server: LoopbackServer?

    var clientID: String {
        get { UserDefaults.standard.string(forKey: clientIDKey) ?? "" }
        set {
            UserDefaults.standard.set(
                newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: clientIDKey
            )
        }
    }

    var isAuthorized: Bool { refreshToken != nil }

    // The scope string Spotify actually granted at the last authorization.
    var grantedScopes: String { UserDefaults.standard.string(forKey: grantedScopesKey) ?? "" }

    // Write scopes Prism needs for creating playlists and editing the library.
    var missingWriteScopes: [String] {
        let granted = Set(grantedScopes.split(separator: " ").map(String.init))
        return ["playlist-modify-private", "playlist-modify-public", "user-library-modify"]
            .filter { !granted.contains($0) }
    }

    private init() {
        refreshToken = Keychain.get(tokenAccount)
    }

    // MARK: - Authorization

    func authorize() async throws {
        let clientID = self.clientID
        guard !clientID.isEmpty else { throw AuthError.missingClientID }

        let verifier = Self.randomString(64)
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomString(24)

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
        ]

        let code = try await waitForCode(authURL: components.url!, expectedState: state)
        try await exchangeCode(code, verifier: verifier, clientID: clientID)
    }

    private func waitForCode(authURL: URL, expectedState: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            let finish: (Result<String, Error>) -> Void = { [weak self] result in
                guard !didResume else { return }
                didResume = true
                self?.server?.stop()
                self?.server = nil
                continuation.resume(with: result)
            }

            let server = LoopbackServer(port: redirectPort)
            self.server = server

            do {
                try server.start { components in
                    Task { @MainActor in
                        guard components.path == "/callback" else { return }
                        let items = components.queryItems ?? []
                        let value: (String) -> String? = { name in
                            items.first { $0.name == name }?.value
                        }
                        if let error = value("error") {
                            finish(.failure(AuthError.denied(error)))
                        } else if value("state") != expectedState {
                            finish(.failure(AuthError.stateMismatch))
                        } else if let code = value("code") {
                            finish(.success(code))
                        }
                    }
                }
            } catch {
                finish(.failure(AuthError.portInUse))
                return
            }

            NSWorkspace.shared.open(authURL)

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300 * 1_000_000_000)
                finish(.failure(AuthError.timedOut))
            }
        }
    }

    // MARK: - Tokens

    func validAccessToken() async throws -> String {
        if let accessToken, let expiresAt, expiresAt > Date() {
            return accessToken
        }
        return try await refreshAccessToken()
    }

    func invalidateAccessToken() {
        expiresAt = nil
    }

    func signOut() {
        accessToken = nil
        refreshToken = nil
        expiresAt = nil
        Keychain.delete(tokenAccount)
        UserDefaults.standard.removeObject(forKey: grantedScopesKey)
    }

    private func exchangeCode(_ code: String, verifier: String, clientID: String) async throws {
        let token = try await postToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
        store(token)
    }

    private func refreshAccessToken() async throws -> String {
        guard let refreshToken else { throw AuthError.notAuthorized }
        let token = try await postToken([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ])
        store(token)
        guard let accessToken else { throw AuthError.notAuthorized }
        return accessToken
    }

    private func postToken(_ body: [String: String]) async throws -> SPTokenResponse {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.tokenExchangeFailed("No response from Spotify.")
        }
        guard http.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw AuthError.tokenExchangeFailed(detail)
        }
        return try JSONDecoder().decode(SPTokenResponse.self, from: data)
    }

    private func store(_ token: SPTokenResponse) {
        accessToken = token.accessToken
        expiresAt = Date().addingTimeInterval(TimeInterval(token.expiresIn) - 60)
        if let newRefresh = token.refreshToken {
            refreshToken = newRefresh
            Keychain.set(newRefresh, account: tokenAccount)
        }
        if let scope = token.scope {
            UserDefaults.standard.set(scope, forKey: grantedScopesKey)
        }
    }

    // MARK: - PKCE helpers

    private static func randomString(_ length: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<length).map { _ in alphabet.randomElement()! })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncoded()
    }

    private static func formEncode(_ body: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = body.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }
}
