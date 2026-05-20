import Foundation

enum SpotifyError: LocalizedError {
    case invalidResponse
    case unauthorized
    case http(Int, String)
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Spotify returned an unexpected response."
        case .unauthorized:
            return "Spotify rejected the request. Try reconnecting your account."
        case .http(let code, let body):
            return "Spotify request failed (HTTP \(code)). \(body)"
        case .rateLimited:
            return "Spotify is rate limiting requests. Please try again in a few minutes."
        }
    }
}

// Thin async wrapper over the Spotify Web API. Handles auth headers,
// token refresh on 401, rate-limit backoff on 429, and pagination.
final class SpotifyClient {
    static let shared = SpotifyClient()
    private init() {}

    private let base = "https://api.spotify.com/v1"
    private let decoder = JSONDecoder()
    private let session = URLSession.shared

    // MARK: - Core request

    private func fetch(_ url: URL, method: String = "GET", jsonBody: [String: Any]? = nil) async throws -> Data {
        var retries = 0
        while true {
            let token = try await SpotifyAuth.shared.validAccessToken()
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let jsonBody {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
            }

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SpotifyError.invalidResponse
            }

            switch http.statusCode {
            case 200...299:
                return data
            case 401 where retries == 0:
                await SpotifyAuth.shared.invalidateAccessToken()
                retries += 1
            case 401:
                throw SpotifyError.unauthorized
            case 429 where retries < 8:
                let seconds = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "2") ?? 2
                try await Task.sleep(nanoseconds: UInt64((seconds + 0.5) * 1_000_000_000))
                retries += 1
            case 429:
                throw SpotifyError.rateLimited
            default:
                let body = String(data: data, encoding: .utf8) ?? ""
                let path = url.path
                throw SpotifyError.http(http.statusCode, "\(path) — \(String(body.prefix(200)))")
            }
        }
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(string: base + path)!
        if !query.isEmpty { components.queryItems = query }
        let data = try await fetch(components.url!)
        return try decoder.decode(T.self, from: data)
    }

    private func getURL<T: Decodable>(_ url: URL) async throws -> T {
        let data = try await fetch(url)
        return try decoder.decode(T.self, from: data)
    }

    private func allPages<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]) async throws -> [T] {
        var components = URLComponents(string: base + path)!
        components.queryItems = query
        var next: URL? = components.url
        var items: [T] = []
        while let url = next {
            let page: SPPaging<T> = try await getURL(url)
            items.append(contentsOf: page.items)
            next = page.next.flatMap { URL(string: $0) }
        }
        return items
    }

    // MARK: - Reading the library

    func currentUser() async throws -> SPUser {
        try await get("/me")
    }

    func savedTracks() async throws -> [SPTrack] {
        let saved: [SPSavedTrack] = try await allPages(
            "/me/tracks",
            query: [URLQueryItem(name: "limit", value: "50")]
        )
        return saved.compactMap(\.track)
    }

    func playlists() async throws -> [SPPlaylist] {
        try await allPages("/me/playlists", query: [URLQueryItem(name: "limit", value: "50")])
    }

    func playlistTracks(playlistID: String) async throws -> [SPTrack] {
        let items: [SPPlaylistTrackItem] = try await allPages(
            "/playlists/\(playlistID)/items",
            query: [URLQueryItem(name: "limit", value: "100")]
        )
        return items.compactMap(\.track)
    }

    func topTracks(timeRange: String) async throws -> [SPTrack] {
        let page: SPPaging<SPTrack> = try await get(
            "/me/top/tracks",
            query: [
                URLQueryItem(name: "limit", value: "50"),
                URLQueryItem(name: "time_range", value: timeRange),
            ]
        )
        return page.items
    }

    func recentlyPlayed() async throws -> [SPTrack] {
        let page: SPPaging<SPRecentlyPlayedItem> = try await get(
            "/me/player/recently-played",
            query: [URLQueryItem(name: "limit", value: "50")]
        )
        return page.items.compactMap(\.track)
    }

    func followedArtists() async throws -> [SPArtist] {
        var components = URLComponents(string: base + "/me/following")!
        components.queryItems = [
            URLQueryItem(name: "type", value: "artist"),
            URLQueryItem(name: "limit", value: "50"),
        ]
        var next: URL? = components.url
        var artists: [SPArtist] = []
        while let url = next {
            let wrapper: SPFollowedArtists = try await getURL(url)
            artists.append(contentsOf: wrapper.artists.items)
            next = wrapper.artists.next.flatMap { URL(string: $0) }
        }
        return artists
    }

    func artists(ids: [String]) async throws -> [SPArtist] {
        var artists: [SPArtist] = []
        for batch in ids.chunked(into: 50) where !batch.isEmpty {
            let response: SPArtistsResponse = try await get(
                "/artists",
                query: [URLQueryItem(name: "ids", value: batch.joined(separator: ","))]
            )
            artists.append(contentsOf: response.artists.compactMap { $0 })
        }
        return artists
    }

    // MARK: - Writing playlists

    func createPlaylist(name: String, description: String, isPublic: Bool) async throws -> String {
        let url = URL(string: "\(base)/me/playlists")!
        let data = try await fetch(url, method: "POST", jsonBody: [
            "name": name,
            "description": description,
            "public": isPublic,
        ])
        let playlist = try decoder.decode(SPPlaylist.self, from: data)
        return playlist.id
    }

    func addTracks(playlistID: String, uris: [String]) async throws {
        let url = URL(string: "\(base)/playlists/\(playlistID)/items")!
        for batch in uris.chunked(into: 100) where !batch.isEmpty {
            _ = try await fetch(url, method: "POST", jsonBody: ["uris": batch])
        }
    }

    // The Feb 2026 API removes library items via /me/library, taking the
    // Spotify URIs as a comma-separated query parameter (max 40 per call).
    func removeSavedTracks(ids: [String]) async throws {
        let uris = ids.map { "spotify:track:\($0)" }
        for batch in uris.chunked(into: 40) where !batch.isEmpty {
            var components = URLComponents(string: "\(base)/me/library")!
            components.queryItems = [URLQueryItem(name: "uris", value: batch.joined(separator: ","))]
            _ = try await fetch(components.url!, method: "DELETE")
        }
    }

    // MARK: - Playback

    // Starts a track on a specific device — used to play through the
    // Web Playback SDK's device.
    func startPlayback(deviceID: String, uris: [String], offsetPosition: Int) async throws {
        var components = URLComponents(string: "\(base)/me/player/play")!
        components.queryItems = [URLQueryItem(name: "device_id", value: deviceID)]
        _ = try await fetch(components.url!, method: "PUT", jsonBody: [
            "uris": uris,
            "offset": ["position": offsetPosition],
        ])
    }
}
