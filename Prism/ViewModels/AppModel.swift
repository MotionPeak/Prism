import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

// Central app state: holds the library, drives sync and categorization,
// and exposes everything the SwiftUI views observe.
@MainActor
@Observable
final class AppModel {
    enum Phase {
        case needsClientID
        case needsConnection
        case ready
    }

    enum Engine: String, CaseIterable, Identifiable {
        case appleIntelligence
        case ollama

        var id: String { rawValue }
        var label: String {
            switch self {
            case .appleIntelligence: return "Apple Intelligence (on-device)"
            case .ollama: return "Local Model (Ollama)"
            }
        }
    }

    struct Banner: Identifiable {
        enum Kind { case info, success, error }
        let id = UUID()
        let kind: Kind
        let message: String
    }

    var library = PrismLibrary.empty {
        didSet { rebuildIndex() }
    }
    private(set) var tracksByID: [String: LibraryTrack] = [:]

    var phase: Phase = .needsClientID
    var selectedCategoryID: String?
    var searchText = ""

    // Sentinel sidebar selection that opens the Liked Songs management view.
    static let likedSongsID = "__prism_liked_songs__"

    // Sidebar playlist selections are tagged "<prefix><playlistID>".
    static let playlistTagPrefix = "__prism_playlist__"
    static func playlistTag(_ playlistID: String) -> String { playlistTagPrefix + playlistID }

    var isWorking = false
    var statusMessage = ""
    var progress = 0.0
    var banner: Banner?

    var clientIDDraft = ""
    var engine: Engine = .appleIntelligence {
        didSet { UserDefaults.standard.set(engine.rawValue, forKey: Self.engineKey) }
    }
    var ollamaModel = "" {
        didSet { UserDefaults.standard.set(ollamaModel, forKey: Self.ollamaModelKey) }
    }
    var availableOllamaModels: [String] = []

    private static let engineKey = "categorizationEngine"
    private static let ollamaModelKey = "ollamaModel"

    init() {
        clientIDDraft = SpotifyAuth.shared.clientID
        if let stored = UserDefaults.standard.string(forKey: Self.engineKey),
           let restored = Engine(rawValue: stored) {
            engine = restored
        }
        ollamaModel = UserDefaults.standard.string(forKey: Self.ollamaModelKey) ?? ""
        if let cached = LibraryStore.load() {
            library = cached
        }
        refreshPhase()
        selectedCategoryID = library.categories.first?.id
    }

    // MARK: - Derived state

    var hasLibrary: Bool { !library.tracks.isEmpty }

    var selectedCategory: Category? {
        library.categories.first { $0.id == selectedCategoryID }
    }

    func tracks(in category: Category) -> [LibraryTrack] {
        category.trackIDs.compactMap { tracksByID[$0] }
    }

    func filteredTracks(in category: Category) -> [LibraryTrack] {
        let all = tracks(in: category)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return all }
        return all.filter { track in
            track.name.lowercased().contains(query)
                || track.displayArtist.lowercased().contains(query)
                || track.albumName.lowercased().contains(query)
        }
    }

    var selectedPlaylist: StoredPlaylist? {
        guard let id = selectedCategoryID, id.hasPrefix(Self.playlistTagPrefix) else { return nil }
        let playlistID = String(id.dropFirst(Self.playlistTagPrefix.count))
        return library.playlists.first { $0.id == playlistID }
    }

    func tracks(inPlaylist playlist: StoredPlaylist) -> [LibraryTrack] {
        playlist.trackIDs.compactMap { tracksByID[$0] }
    }

    func filteredTracks(inPlaylist playlist: StoredPlaylist) -> [LibraryTrack] {
        let all = tracks(inPlaylist: playlist)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return all }
        return all.filter { track in
            track.name.lowercased().contains(query)
                || track.displayArtist.lowercased().contains(query)
                || track.albumName.lowercased().contains(query)
        }
    }

    private func rebuildIndex() {
        tracksByID = Dictionary(
            library.tracks.map { ($0.id, $0) },
            uniquingKeysWith: { current, _ in current }
        )
    }

    func refreshPhase() {
        if SpotifyAuth.shared.clientID.isEmpty {
            phase = .needsClientID
        } else if !SpotifyAuth.shared.isAuthorized {
            phase = .needsConnection
        } else {
            phase = .ready
        }
    }

    // MARK: - Actions

    func saveClientID() {
        SpotifyAuth.shared.clientID = clientIDDraft
        clientIDDraft = SpotifyAuth.shared.clientID
        refreshPhase()
    }

    func connect() async {
        guard !isWorking else { return }
        isWorking = true
        banner = nil
        progress = 0
        statusMessage = "Waiting for Spotify authorization in your browser…"
        do {
            try await SpotifyAuth.shared.authorize()
            refreshPhase()
            isWorking = false
            await refreshEverything()
        } catch {
            isWorking = false
            statusMessage = ""
            show(.error, error.localizedDescription)
        }
    }

    func reconnect() async {
        SpotifyAuth.shared.signOut()
        await connect()
    }

    func refreshEverything() async {
        await sync()
        if hasLibrary {
            await categorize()
        }
    }

    func sync() async {
        guard !isWorking else { return }
        isWorking = true
        banner = nil
        progress = 0
        statusMessage = "Starting sync…"
        do {
            var synced = try await LibraryStore.sync { message, fraction in
                self.statusMessage = message
                self.progress = fraction
            }
            synced.categories = []
            library = synced
            LibraryStore.save(library)
        } catch {
            show(.error, error.localizedDescription)
        }
        isWorking = false
        statusMessage = ""
    }

    func categorize() async {
        guard !isWorking else { return }
        guard hasLibrary else {
            show(.info, "Sync your library before categorizing.")
            return
        }
        isWorking = true
        banner = nil
        progress = 0
        statusMessage = "Categorizing…"
        do {
            let runner = try makeRunner()
            let categories = try await NameCategorizer().categorize(
                tracks: library.tracks,
                runner: runner
            ) { message in
                self.statusMessage = message
            }
            library.categories = categories
            library.lastCategorized = Date()
            LibraryStore.save(library)
            selectedCategoryID = categories.first?.id
            show(.success, "Organized \(library.tracks.count) tracks into \(categories.count) categories.")
        } catch {
            show(.error, error.localizedDescription)
        }
        isWorking = false
        statusMessage = ""
    }

    private func makeRunner() throws -> LLMRunner {
        switch engine {
        case .appleIntelligence:
            return AppleIntelligenceRunner()
        case .ollama:
            guard !ollamaModel.isEmpty else { throw CategorizerError.ollamaNoModel }
            return OllamaRunner(model: ollamaModel)
        }
    }

    func refreshOllamaModels() async {
        do {
            let models = try await OllamaClient.shared.listModels()
            availableOllamaModels = models
            if ollamaModel.isEmpty || !models.contains(ollamaModel) {
                ollamaModel = models.first ?? ""
            }
        } catch {
            availableOllamaModels = []
        }
    }

    // MARK: - Liked Songs

    var likedTracks: [LibraryTrack] {
        library.tracks.filter { $0.sources.contains(.saved) }
    }

    var ownedPlaylists: [StoredPlaylist] {
        guard let userID = library.profile?.id else { return library.playlists }
        return library.playlists.filter { $0.ownerID == userID }
    }

    func categoryName(for trackID: String) -> String? {
        library.categories.first { $0.trackIDs.contains(trackID) }?.name
    }

    func removeFromLibrary(trackIDs: Set<String>) async {
        guard !isWorking, !trackIDs.isEmpty else { return }
        let ids = Array(trackIDs)
        isWorking = true
        banner = nil
        statusMessage = "Removing \(ids.count) track\(ids.count == 1 ? "" : "s") from your library…"
        do {
            try await SpotifyClient.shared.removeSavedTracks(ids: ids)
            applyLocalRemoval(of: trackIDs)
            show(.success, "Removed \(ids.count) track\(ids.count == 1 ? "" : "s") from your library.")
        } catch {
            show(.error, error.localizedDescription)
        }
        isWorking = false
        statusMessage = ""
    }

    func addToNewPlaylist(name: String, trackIDs: Set<String>, removeFromLiked: Bool) async {
        guard !isWorking, !trackIDs.isEmpty else { return }
        guard let userID = library.profile?.id else {
            show(.error, "Connect your Spotify account first.")
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            show(.error, "Pick a name for the new playlist.")
            return
        }
        let uris = trackIDs.compactMap { tracksByID[$0]?.uri }
        guard !uris.isEmpty else { return }

        isWorking = true
        banner = nil
        statusMessage = "Creating “\(trimmed)” in Spotify…"
        do {
            let playlistID = try await SpotifyClient.shared.createPlaylist(
                name: trimmed,
                description: "Created with Prism.",
                isPublic: false
            )
            try await SpotifyClient.shared.addTracks(playlistID: playlistID, uris: uris)
            library.playlists.append(
                StoredPlaylist(id: playlistID, name: trimmed, ownerID: userID, trackIDs: Array(trackIDs))
            )
            if removeFromLiked {
                try await SpotifyClient.shared.removeSavedTracks(ids: Array(trackIDs))
                applyLocalRemoval(of: trackIDs)
            }
            LibraryStore.save(library)
            let suffix = removeFromLiked ? " (and removed them from Liked Songs)" : ""
            show(.success, "Added \(uris.count) track\(uris.count == 1 ? "" : "s") to “\(trimmed)”\(suffix).")
        } catch {
            show(.error, error.localizedDescription)
        }
        isWorking = false
        statusMessage = ""
    }

    func addToExistingPlaylist(playlistID: String, trackIDs: Set<String>, removeFromLiked: Bool) async {
        guard !isWorking, !trackIDs.isEmpty else { return }
        let uris = trackIDs.compactMap { tracksByID[$0]?.uri }
        guard !uris.isEmpty else { return }
        let playlistName = library.playlists.first { $0.id == playlistID }?.name ?? "playlist"

        isWorking = true
        banner = nil
        statusMessage = "Adding to “\(playlistName)”…"
        do {
            try await SpotifyClient.shared.addTracks(playlistID: playlistID, uris: uris)
            if removeFromLiked {
                try await SpotifyClient.shared.removeSavedTracks(ids: Array(trackIDs))
                applyLocalRemoval(of: trackIDs)
                LibraryStore.save(library)
            }
            let suffix = removeFromLiked ? " (and removed them from Liked Songs)" : ""
            show(.success, "Added \(uris.count) track\(uris.count == 1 ? "" : "s") to “\(playlistName)”\(suffix).")
        } catch {
            show(.error, error.localizedDescription)
        }
        isWorking = false
        statusMessage = ""
    }

    private func applyLocalRemoval(of trackIDs: Set<String>) {
        var updated = library
        for index in updated.tracks.indices where trackIDs.contains(updated.tracks[index].id) {
            updated.tracks[index].sources.remove(.saved)
        }
        let droppedIDs = Set(updated.tracks.filter { $0.sources.isEmpty }.map(\.id))
        updated.tracks.removeAll { droppedIDs.contains($0.id) }
        if !droppedIDs.isEmpty {
            for index in updated.categories.indices {
                updated.categories[index].trackIDs.removeAll { droppedIDs.contains($0) }
            }
            updated.categories.removeAll { $0.trackIDs.isEmpty }
        }
        library = updated
        LibraryStore.save(library)
    }

    func createPlaylist(for category: Category) async {
        guard !isWorking else { return }
        guard library.profile != nil else {
            show(.error, "Connect your Spotify account first.")
            return
        }
        isWorking = true
        banner = nil
        statusMessage = "Creating “\(category.name)” in Spotify…"
        let uris = category.trackIDs.compactMap { tracksByID[$0]?.uri }
        do {
            let playlistID = try await SpotifyClient.shared.createPlaylist(
                name: "Prism · \(category.name)",
                description: "Sorted by Prism from your Spotify library.",
                isPublic: false
            )
            try await SpotifyClient.shared.addTracks(playlistID: playlistID, uris: uris)
            show(.success, "Created “Prism · \(category.name)” with \(uris.count) tracks in Spotify.")
        } catch {
            show(.error, error.localizedDescription)
        }
        isWorking = false
        statusMessage = ""
    }

    func exportCSV(for category: Category?) {
        let rows: [Exporter.Row]
        let suggestedName: String
        if let category {
            rows = tracks(in: category).map { Exporter.Row(category: category.name, track: $0) }
            suggestedName = "Prism - \(category.name).csv"
        } else {
            rows = library.categories.flatMap { category in
                tracks(in: category).map { Exporter.Row(category: category.name, track: $0) }
            }
            suggestedName = "Prism Library.csv"
        }
        guard !rows.isEmpty else {
            show(.info, "There is nothing to export yet.")
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Exporter.csv(rows: rows).write(to: url, atomically: true, encoding: .utf8)
            show(.success, "Exported \(rows.count) tracks to \(url.lastPathComponent).")
        } catch {
            show(.error, "Could not write the file: \(error.localizedDescription)")
        }
    }

    func signOut() {
        SpotifyAuth.shared.signOut()
        library = .empty
        selectedCategoryID = nil
        LibraryStore.save(library)
        refreshPhase()
        show(.info, "Disconnected from Spotify.")
    }

    func dismissBanner() {
        banner = nil
    }

    private func show(_ kind: Banner.Kind, _ message: String) {
        let banner = Banner(kind: kind, message: message)
        self.banner = banner
        guard kind != .error else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if self.banner?.id == banner.id {
                self.banner = nil
            }
        }
    }
}
