import Foundation

// A categorizer turns a flat list of tracks into named, emoji-tagged buckets.
@MainActor
protocol Categorizer {
    var displayName: String { get }
    func categorize(tracks: [LibraryTrack], progress: @escaping (String) -> Void) async throws -> [Category]
}

struct CategoryDefinition: Sendable {
    let name: String
    let emoji: String
}

enum CategorizerError: LocalizedError {
    case emptyLibrary
    case modelUnavailable(String)
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .emptyLibrary:
            return "There are no tracks to categorize yet. Sync your library first."
        case .modelUnavailable(let reason):
            return "Apple Intelligence is unavailable (\(reason))."
        case .generationFailed:
            return "The on-device model did not return a usable result."
        }
    }
}

// Shared assignment step: given a genre→category map, place every track.
// Each track is assigned to the category most of its genres point to.
func buildCategories(
    tracks: [LibraryTrack],
    definitions: [CategoryDefinition],
    genreToCategory: [String: String]
) -> [Category] {
    let uncategorized = "Uncategorized"
    var trackIDsByCategory: [String: [String]] = [:]

    for track in tracks {
        var votes: [String: Int] = [:]
        for genre in track.genres {
            if let category = genreToCategory[genre.lowercased()] {
                votes[category, default: 0] += 1
            }
        }
        let winner = votes.max { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
        }?.key ?? uncategorized
        trackIDsByCategory[winner, default: []].append(track.id)
    }

    var emojiByName = Dictionary(definitions.map { ($0.name, $0.emoji) }, uniquingKeysWith: { first, _ in first })
    emojiByName[uncategorized] = "🪐"

    var order = definitions.map(\.name)
    order.append(uncategorized)

    return order.compactMap { name in
        guard let ids = trackIDsByCategory[name], !ids.isEmpty else { return nil }
        return Category(name: name, emoji: emojiByName[name] ?? "🎵", trackIDs: ids)
    }
}
