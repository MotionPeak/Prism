import Foundation

// Pulls everything Prism needs from Spotify and normalizes it into a PrismLibrary.
// Also handles caching that library to disk between launches.
enum LibraryStore {
    @MainActor
    static func sync(progress: (String, Double) -> Void) async throws -> PrismLibrary {
        let client = SpotifyClient.shared

        progress("Loading your Spotify profile…", 0.03)
        let user = try await client.currentUser()

        progress("Fetching your liked songs…", 0.10)
        let saved = try await client.savedTracks()

        progress("Listing your playlists…", 0.20)
        let playlists = try await client.playlists()

        var collected: [(track: SPTrack, source: TrackSource)] = saved.map { ($0, .saved) }

        for (index, playlist) in playlists.enumerated() {
            let fraction = 0.22 + 0.34 * Double(index) / Double(max(playlists.count, 1))
            progress("Reading “\(playlist.name)”…", fraction)
            let tracks = try await client.playlistTracks(playlistID: playlist.id)
            collected.append(contentsOf: tracks.map { ($0, .playlist) })
        }

        progress("Fetching your top tracks…", 0.58)
        for range in ["short_term", "medium_term", "long_term"] {
            let top = try await client.topTracks(timeRange: range)
            collected.append(contentsOf: top.map { ($0, .top) })
        }

        progress("Fetching recently played…", 0.64)
        let recent = try await client.recentlyPlayed()
        collected.append(contentsOf: recent.map { ($0, .recent) })

        // Deduplicate by track id, merging the sources each track turned up in.
        progress("Organizing your tracks…", 0.70)
        var byID: [String: LibraryTrack] = [:]
        for entry in collected {
            guard let id = entry.track.id, entry.track.isLocal != true else { continue }
            if var existing = byID[id] {
                existing.sources.insert(entry.source)
                byID[id] = existing
            } else {
                byID[id] = LibraryTrack(from: entry.track, source: entry.source)
            }
        }

        // Genres live on the artist, not the track — resolve them in one pass.
        progress("Resolving genres…", 0.78)
        let artistIDs = Array(Set(byID.values.flatMap(\.artistIDs)))
        let artists = try await client.artists(ids: artistIDs)
        var genresByArtist: [String: [String]] = [:]
        for artist in artists {
            if let id = artist.id { genresByArtist[id] = artist.genres ?? [] }
        }

        progress("Finalizing your library…", 0.94)
        var tracks: [LibraryTrack] = []
        for var track in byID.values {
            let genres = track.artistIDs.flatMap { genresByArtist[$0] ?? [] }
            track.genres = Array(Set(genres)).sorted()
            tracks.append(track)
        }
        tracks.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        progress("Done", 1.0)
        return PrismLibrary(
            profile: StoredProfile(
                id: user.id,
                displayName: user.displayName ?? user.id,
                imageURL: user.images?.first?.url
            ),
            tracks: tracks,
            categories: [],
            lastSynced: Date(),
            lastCategorized: nil
        )
    }

    // MARK: - Disk cache

    private static var cacheURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("Prism", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("library.json")
    }

    static func load() -> PrismLibrary? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(PrismLibrary.self, from: data)
    }

    static func save(_ library: PrismLibrary) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(library) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}

extension LibraryTrack {
    init(from track: SPTrack, source: TrackSource) {
        let resolvedID = track.id ?? track.uri ?? UUID().uuidString
        self.init(
            id: resolvedID,
            uri: track.uri ?? "spotify:track:\(resolvedID)",
            name: track.name,
            artistNames: track.artists.map(\.name),
            artistIDs: track.artists.compactMap(\.id),
            albumName: track.album?.name ?? "",
            albumArtURL: track.album?.images?.last?.url,
            durationMs: track.durationMs ?? 0,
            popularity: track.popularity ?? 0,
            explicit: track.explicit ?? false,
            releaseYear: track.album?.releaseDate.flatMap { Int($0.prefix(4)) },
            genres: [],
            sources: [source]
        )
    }
}
