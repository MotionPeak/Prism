#if canImport(FoundationModels)
import FoundationModels
#endif
import Foundation

// Categorizer backed by the on-device Apple Intelligence model.
// The model groups Spotify's fine-grained genre tags into broad categories;
// every track is then placed by the genres of its artists. Runs fully offline.
struct AppleIntelligenceCategorizer: Categorizer {
    var displayName: String { "Apple Intelligence" }

    private struct ModelCategory: Decodable {
        let name: String
        let emoji: String?
        let genres: [String]
    }

    private struct ModelResponse: Decodable {
        let categories: [ModelCategory]
    }

    func categorize(tracks: [LibraryTrack], progress: @escaping (String) -> Void) async throws -> [Category] {
        guard !tracks.isEmpty else { throw CategorizerError.emptyLibrary }

        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(let reason):
            throw CategorizerError.modelUnavailable("\(reason)")
        @unknown default:
            throw CategorizerError.modelUnavailable("unknown reason")
        }

        progress("Studying the genres in your library…")
        let allGenres = Self.genresByFrequency(tracks)
        guard !allGenres.isEmpty else { throw CategorizerError.generationFailed }
        let topGenres = Array(allGenres.prefix(110))

        progress("Asking Apple Intelligence to group them…")
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(to: Self.prompt(genres: topGenres))

        guard let modelCategories = Self.parse(response.content), !modelCategories.isEmpty else {
            throw CategorizerError.generationFailed
        }

        progress("Sorting your tracks into categories…")
        var definitions: [CategoryDefinition] = []
        var genreToCategory: [String: String] = [:]
        for category in modelCategories {
            let name = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            definitions.append(CategoryDefinition(name: name, emoji: Self.cleanEmoji(category.emoji)))
            for genre in category.genres {
                genreToCategory[genre.lowercased()] = name
            }
        }
        guard !definitions.isEmpty else { throw CategorizerError.generationFailed }

        Self.reconcile(allGenres: allGenres, into: &genreToCategory, definitions: definitions)
        return buildCategories(tracks: tracks, definitions: definitions, genreToCategory: genreToCategory)
        #else
        throw CategorizerError.modelUnavailable("the Foundation Models framework is not available")
        #endif
    }

    // MARK: - Prompt

    private static let instructions = """
    You are a music librarian. You group fine-grained music genres into a small set of \
    broad, friendly categories. You always reply with raw JSON only — no prose, no markdown.
    """

    private static func prompt(genres: [String]) -> String {
        """
        Group every genre below into 8 to 14 broad, human-friendly categories — for example: \
        Hip-Hop & Rap, Pop, Rock, Indie & Alternative, Electronic & Dance, R&B & Soul, \
        Jazz & Blues, Classical, Country & Folk, Latin, Metal, Chill & Ambient, World.
        Each genre must appear in exactly one category. Choose one fitting emoji per category.

        Reply with JSON only, in exactly this shape:
        {"categories":[{"name":"Hip-Hop & Rap","emoji":"🎤","genres":["rap","trap"]}]}

        Genres:
        \(genres.joined(separator: ", "))
        """
    }

    // MARK: - Helpers

    private static func genresByFrequency(_ tracks: [LibraryTrack]) -> [String] {
        var counts: [String: Int] = [:]
        for track in tracks {
            for genre in track.genres { counts[genre, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.map { $0.key }
    }

    private static func cleanEmoji(_ raw: String?) -> String {
        guard let character = raw?.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return "🎵"
        }
        return String(character)
    }

    private static func parse(_ text: String) -> [ModelCategory]? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end
        else { return nil }
        let json = String(text[start...end])
        guard let data = json.data(using: .utf8),
              let response = try? JSONDecoder().decode(ModelResponse.self, from: data)
        else { return nil }
        return response.categories
    }

    // Genres the model left out are matched to a category by shared keywords.
    private static func reconcile(
        allGenres: [String],
        into map: inout [String: String],
        definitions: [CategoryDefinition]
    ) {
        var wordToCategory: [String: String] = [:]
        for (genre, category) in map {
            for word in keywords(genre) where wordToCategory[word] == nil {
                wordToCategory[word] = category
            }
        }
        for definition in definitions {
            for word in keywords(definition.name) where wordToCategory[word] == nil {
                wordToCategory[word] = definition.name
            }
        }
        for genre in allGenres {
            let key = genre.lowercased()
            guard map[key] == nil else { continue }
            var votes: [String: Int] = [:]
            for word in keywords(genre) {
                if let category = wordToCategory[word] { votes[category, default: 0] += 1 }
            }
            if let best = votes.max(by: { $0.value < $1.value })?.key {
                map[key] = best
            }
        }
    }

    private static func keywords(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count > 2 }
    }
}
