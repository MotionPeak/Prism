import Foundation

enum CategorizerError: LocalizedError {
    case emptyLibrary
    case appleIntelligenceUnavailable(String)
    case ollamaUnreachable(String)
    case ollamaNoModel
    case ollamaModelMissing(String)
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .emptyLibrary:
            return "There are no tracks to categorize yet. Sync your library first."
        case .appleIntelligenceUnavailable(let reason):
            return "Apple Intelligence is unavailable (\(reason)). Enable it in System Settings, or switch to a local Ollama model in Settings → Categorization."
        case .ollamaUnreachable(let detail):
            return "Couldn't reach Ollama. \(detail) Make sure Ollama is installed and running, then try again."
        case .ollamaNoModel:
            return "No Ollama model is selected. Open Settings → Categorization and choose a model."
        case .ollamaModelMissing(let model):
            return "The model “\(model)” isn't installed in Ollama. Run: ollama pull \(model)"
        case .generationFailed:
            return "The model didn't return a usable result. Try again, or pick a different model."
        }
    }
}

struct CategoryDefinition: Sendable {
    let name: String
    let emoji: String
    // Lowercase substrings used to map a model's free-text answer back to this category.
    let aliases: [String]
}

// A fixed category taxonomy, shared by every engine so results stay consistent
// across batches and whichever model is used.
enum MusicTaxonomy {
    static let other = "Other"

    static let categories: [CategoryDefinition] = [
        .init(name: "Hip-Hop & Rap", emoji: "🎤", aliases: ["hip-hop", "hip hop", "hiphop", "rap", "trap"]),
        .init(name: "Pop", emoji: "✨", aliases: ["pop"]),
        .init(name: "Rock", emoji: "🎸", aliases: ["rock", "punk", "grunge"]),
        .init(name: "Metal", emoji: "🤘", aliases: ["metal"]),
        .init(name: "Electronic & Dance", emoji: "🎛️", aliases: ["electronic", "dance", "edm", "house", "techno"]),
        .init(name: "R&B & Soul", emoji: "💜", aliases: ["r&b", "rnb", "r & b", "soul", "funk"]),
        .init(name: "Indie & Alternative", emoji: "🌙", aliases: ["indie", "alternative", "alt-"]),
        .init(name: "Jazz & Blues", emoji: "🎷", aliases: ["jazz", "blues"]),
        .init(name: "Classical", emoji: "🎻", aliases: ["classical", "orchestral", "opera", "baroque"]),
        .init(name: "Country & Folk", emoji: "🌾", aliases: ["country", "folk", "americana", "bluegrass"]),
        .init(name: "Latin", emoji: "🔥", aliases: ["latin", "reggaeton"]),
        .init(name: "Reggae & Dub", emoji: "🌴", aliases: ["reggae", "dub", "ska", "dancehall"]),
        .init(name: "Soundtrack & Score", emoji: "🎬", aliases: ["soundtrack", "score", "film", "cinematic"]),
        .init(name: "Chill & Ambient", emoji: "🫧", aliases: ["chill", "ambient", "lo-fi", "lofi", "downtempo"]),
        .init(name: "World", emoji: "🌍", aliases: ["world", "afro", "k-pop", "j-pop"]),
        .init(name: "Other", emoji: "🪐", aliases: ["other", "unknown", "misc", "various"]),
    ]

    // Category names in display order ("Other" last).
    static let names: [String] = categories.map(\.name)

    private static let exactLookup: [String: String] = Dictionary(
        uniqueKeysWithValues: categories.map { ($0.name.lowercased(), $0.name) }
    )

    // Maps a model's free-text category to a canonical taxonomy name.
    static func canonical(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = exactLookup[trimmed.lowercased()] { return exact }
        let lower = trimmed.lowercased()
        for category in categories where category.name != other {
            if category.aliases.contains(where: { lower.contains($0) }) {
                return category.name
            }
        }
        return other
    }

    static func emoji(for name: String) -> String {
        categories.first { $0.name == name }?.emoji ?? "🎵"
    }
}

// A model backend that can answer a single text prompt.
@MainActor
protocol LLMRunner {
    // Throws a CategorizerError if the backend isn't ready to use.
    func preflight() async throws
    func complete(_ prompt: String) async throws -> String
}

// Categorizes a library by classifying each artist with an LLM and using
// the artist's category for all of their tracks. Needs no genre data.
struct NameCategorizer {
    private let batchSize = 25

    @MainActor
    func categorize(
        tracks: [LibraryTrack],
        runner: LLMRunner,
        progress: @escaping (String) -> Void
    ) async throws -> [Category] {
        guard !tracks.isEmpty else { throw CategorizerError.emptyLibrary }

        progress("Checking the model…")
        try await runner.preflight()

        let artists = Self.uniquePrimaryArtists(tracks)
        guard !artists.isEmpty else { throw CategorizerError.generationFailed }

        var artistToCategory: [String: String] = [:]
        let batches = artists.chunked(into: batchSize)
        for (index, batch) in batches.enumerated() {
            progress("Classifying artists… (\(index + 1)/\(batches.count))")
            let assignments = try await classify(batch: batch, runner: runner)
            for (artist, category) in assignments {
                artistToCategory[artist] = category
            }
        }

        progress("Sorting your tracks…")
        return Self.build(tracks: tracks, artistToCategory: artistToCategory)
    }

    @MainActor
    private func classify(batch: [String], runner: LLMRunner) async throws -> [String: String] {
        let prompt = Self.prompt(artists: batch)
        for _ in 0..<2 {
            let raw = try await runner.complete(prompt)
            if let parsed = Self.parse(raw), !parsed.isEmpty {
                return parsed
            }
        }
        return [:]   // Unparseable batch — its artists fall through to "Other".
    }

    // MARK: - Prompt

    private static func prompt(artists: [String]) -> String {
        """
        Classify each music artist below into exactly one of these categories:
        \(MusicTaxonomy.names.joined(separator: ", "))

        Base it on the artist's best-known musical style. Use "Other" only if you \
        genuinely do not recognize the artist.

        Reply with ONLY a JSON object mapping every artist name, exactly as written, \
        to its category. No prose, no markdown.
        Example: {"Drake":"Hip-Hop & Rap","Hans Zimmer":"Soundtrack & Score"}

        Artists:
        \(artists.joined(separator: "\n"))
        """
    }

    // MARK: - Parsing

    private struct Assignment: Decodable {
        let artist: String
        let category: String
    }

    static func parse(_ text: String) -> [String: String]? {
        guard let json = extractJSON(from: text), let data = json.data(using: .utf8) else {
            return nil
        }
        let decoder = JSONDecoder()

        if let dictionary = try? decoder.decode([String: String].self, from: data), !dictionary.isEmpty {
            var result: [String: String] = [:]
            for (artist, category) in dictionary {
                result[artist.lowercased()] = MusicTaxonomy.canonical(category)
            }
            return result
        }
        if let wrapped = try? decoder.decode([String: [Assignment]].self, from: data),
           let list = wrapped.values.first, !list.isEmpty {
            return Dictionary(list.map { ($0.artist.lowercased(), MusicTaxonomy.canonical($0.category)) },
                              uniquingKeysWith: { first, _ in first })
        }
        if let list = try? decoder.decode([Assignment].self, from: data), !list.isEmpty {
            return Dictionary(list.map { ($0.artist.lowercased(), MusicTaxonomy.canonical($0.category)) },
                              uniquingKeysWith: { first, _ in first })
        }
        return nil
    }

    private static func extractJSON(from text: String) -> String? {
        let object = text.firstIndex(of: "{")
        let array = text.firstIndex(of: "[")
        let preferObject: Bool
        switch (object, array) {
        case let (objectStart?, arrayStart?): preferObject = objectStart < arrayStart
        case (.some, .none): preferObject = true
        case (.none, .some): preferObject = false
        case (.none, .none): return nil
        }
        if preferObject, let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end {
            return String(text[start...end])
        }
        if !preferObject, let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"), start < end {
            return String(text[start...end])
        }
        return nil
    }

    // MARK: - Helpers

    // Primary (first) artist of every track, deduplicated, most-common first.
    static func uniquePrimaryArtists(_ tracks: [LibraryTrack]) -> [String] {
        var counts: [String: Int] = [:]
        var displayName: [String: String] = [:]
        for track in tracks {
            guard let raw = track.artistNames.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty
            else { continue }
            let key = raw.lowercased()
            counts[key, default: 0] += 1
            if displayName[key] == nil { displayName[key] = raw }
        }
        return counts
            .sorted { $0.value > $1.value }
            .compactMap { displayName[$0.key] }
    }

    static func build(tracks: [LibraryTrack], artistToCategory: [String: String]) -> [Category] {
        var idsByCategory: [String: [String]] = [:]
        for track in tracks {
            let key = track.artistNames.first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            let category = artistToCategory[key] ?? MusicTaxonomy.other
            idsByCategory[category, default: []].append(track.id)
        }
        return MusicTaxonomy.names.compactMap { name in
            guard let ids = idsByCategory[name], !ids.isEmpty else { return nil }
            return Category(name: name, emoji: MusicTaxonomy.emoji(for: name), trackIDs: ids)
        }
    }
}
