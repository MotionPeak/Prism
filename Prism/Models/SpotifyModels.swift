import Foundation

// Raw decodable types that mirror the Spotify Web API JSON.
// Snake-case keys are mapped explicitly so decoding stays predictable.

struct SPImage: Decodable, Sendable, Hashable {
    let url: String
    let width: Int?
    let height: Int?
}

struct SPUser: Decodable, Sendable {
    let id: String
    let displayName: String?
    let images: [SPImage]?
    let product: String?

    enum CodingKeys: String, CodingKey {
        case id, images, product
        case displayName = "display_name"
    }
}

struct SPArtist: Decodable, Sendable, Hashable {
    let id: String?
    let name: String
    let uri: String?
    let genres: [String]?
    let images: [SPImage]?
    let popularity: Int?
}

struct SPAlbum: Decodable, Sendable, Hashable {
    let id: String?
    let name: String
    let images: [SPImage]?
    let releaseDate: String?
    let albumType: String?

    enum CodingKeys: String, CodingKey {
        case id, name, images
        case releaseDate = "release_date"
        case albumType = "album_type"
    }
}

struct SPTrack: Decodable, Sendable, Hashable {
    let id: String?
    let name: String
    let uri: String?
    let durationMs: Int?
    let explicit: Bool?
    let popularity: Int?
    let artists: [SPArtist]
    let album: SPAlbum?
    let isLocal: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, uri, explicit, popularity, artists, album
        case durationMs = "duration_ms"
        case isLocal = "is_local"
    }
}

// MARK: - Paging

struct SPPaging<T: Decodable & Sendable>: Decodable, Sendable {
    let items: [T]
    let next: String?
    let total: Int?
}

struct SPSavedTrack: Decodable, Sendable {
    let track: SPTrack?
}

struct SPPlaylistTrackItem: Decodable, Sendable {
    let track: SPTrack?
}

struct SPRecentlyPlayedItem: Decodable, Sendable {
    let track: SPTrack?
}

struct SPTracksRef: Decodable, Sendable {
    let total: Int?
}

struct SPPlaylistOwner: Decodable, Sendable {
    let id: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

struct SPPlaylist: Decodable, Sendable {
    let id: String
    let name: String
    let owner: SPPlaylistOwner?
    let tracks: SPTracksRef?
}

// MARK: - Followed artists (cursor paginated)

struct SPFollowedArtists: Decodable, Sendable {
    let artists: SPArtistCursorPage
}

struct SPCursors: Decodable, Sendable {
    let after: String?
}

struct SPArtistCursorPage: Decodable, Sendable {
    let items: [SPArtist]
    let next: String?
    let cursors: SPCursors?
}

struct SPArtistsResponse: Decodable, Sendable {
    let artists: [SPArtist?]
}

// MARK: - Auth

struct SPTokenResponse: Decodable, Sendable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}
