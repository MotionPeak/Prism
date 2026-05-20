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
        case ruleBased

        var id: String { rawValue }
        var label: String {
            switch self {
            case .appleIntelligence: return "Apple Intelligence (on-device)"
            case .ruleBased: return "Genre Rules"
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

    var isWorking = false
    var statusMessage = ""
    var progress = 0.0
    var banner: Banner?

    var clientIDDraft = ""
    var engine: Engine = .appleIntelligence {
        didSet { UserDefaults.standard.set(engine.rawValue, forKey: Self.engineKey) }
    }

    private static let engineKey = "categorizationEngine"

    init() {
        clientIDDraft = SpotifyAuth.shared.clientID
        if let stored = UserDefaults.standard.string(forKey: Self.engineKey),
           let restored = Engine(rawValue: stored) {
            engine = restored
        }
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
            try await applyCategorizer(engine)
            show(.success, "Organized \(library.tracks.count) tracks into \(library.categories.count) categories.")
        } catch {
            if engine == .appleIntelligence {
                do {
                    try await applyCategorizer(.ruleBased)
                    show(.info, "Apple Intelligence was unavailable, so Prism sorted by genre rules instead.")
                } catch {
                    show(.error, error.localizedDescription)
                }
            } else {
                show(.error, error.localizedDescription)
            }
        }
        isWorking = false
        statusMessage = ""
    }

    private func applyCategorizer(_ engine: Engine) async throws {
        let categorizer: Categorizer = engine == .appleIntelligence
            ? AppleIntelligenceCategorizer()
            : RuleBasedCategorizer()
        let categories = try await categorizer.categorize(tracks: library.tracks) { message in
            self.statusMessage = message
        }
        library.categories = categories
        library.lastCategorized = Date()
        LibraryStore.save(library)
        selectedCategoryID = categories.first?.id
    }

    func createPlaylist(for category: Category) async {
        guard !isWorking else { return }
        guard let userID = library.profile?.id else {
            show(.error, "Connect your Spotify account first.")
            return
        }
        isWorking = true
        banner = nil
        statusMessage = "Creating “\(category.name)” in Spotify…"
        let uris = category.trackIDs.compactMap { tracksByID[$0]?.uri }
        do {
            let playlistID = try await SpotifyClient.shared.createPlaylist(
                userID: userID,
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
