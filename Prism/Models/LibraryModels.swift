import Foundation

// Where a track was discovered while syncing the account.
enum TrackSource: String, Codable, Sendable, Hashable, CaseIterable {
    case saved
    case playlist
    case top
    case recent

    var label: String {
        switch self {
        case .saved: return "Liked Songs"
        case .playlist: return "Playlists"
        case .top: return "Top Tracks"
        case .recent: return "Recently Played"
        }
    }
}

// A single track in the user's library, normalized for display and categorization.
struct LibraryTrack: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let uri: String
    let name: String
    let artistNames: [String]
    let artistIDs: [String]
    let albumName: String
    let albumArtURL: String?
    let durationMs: Int
    let popularity: Int
    let explicit: Bool
    let releaseYear: Int?
    var genres: [String]
    var sources: Set<TrackSource>

    var displayArtist: String {
        artistNames.isEmpty ? "Unknown Artist" : artistNames.joined(separator: ", ")
    }

    var durationText: String {
        let total = durationMs / 1000
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var spotifyURL: URL? {
        URL(string: "https://open.spotify.com/track/\(id)")
    }
}

// A categorized bucket of tracks. `name` doubles as the stable identifier.
struct Category: Identifiable, Codable, Sendable, Hashable {
    var id: String { name }
    let name: String
    let emoji: String
    var trackIDs: [String]

    var displayName: String { "\(emoji) \(name)" }
}

// The user profile, persisted alongside the library cache.
struct StoredProfile: Codable, Sendable {
    let id: String
    let displayName: String
    let imageURL: String?
}

// The full cached state: profile, tracks, and the most recent categorization.
struct PrismLibrary: Codable, Sendable {
    var profile: StoredProfile?
    var tracks: [LibraryTrack]
    var categories: [Category]
    var lastSynced: Date?
    var lastCategorized: Date?

    static let empty = PrismLibrary(profile: nil, tracks: [], categories: [], lastSynced: nil, lastCategorized: nil)

    var allGenres: [String] {
        Set(tracks.flatMap(\.genres)).sorted()
    }
}
