import Foundation

// Deterministic fallback categorizer. Maps Spotify's fine-grained genre tags
// to broad categories using ordered keyword rules — no model required.
struct RuleBasedCategorizer: Categorizer {
    var displayName: String { "Genre Rules" }

    func categorize(tracks: [LibraryTrack], progress: @escaping (String) -> Void) async throws -> [Category] {
        guard !tracks.isEmpty else { throw CategorizerError.emptyLibrary }
        progress("Sorting tracks by genre rules…")

        var genreToCategory: [String: String] = [:]
        for track in tracks {
            for genre in track.genres {
                let key = genre.lowercased()
                if genreToCategory[key] == nil {
                    genreToCategory[key] = Self.category(for: key)
                }
            }
        }
        return buildCategories(tracks: tracks, definitions: Self.definitions, genreToCategory: genreToCategory)
    }

    static let definitions: [CategoryDefinition] = [
        CategoryDefinition(name: "Hip-Hop & Rap", emoji: "🎤"),
        CategoryDefinition(name: "Electronic & Dance", emoji: "🎛️"),
        CategoryDefinition(name: "R&B & Soul", emoji: "💜"),
        CategoryDefinition(name: "Metal", emoji: "🤘"),
        CategoryDefinition(name: "Jazz & Blues", emoji: "🎷"),
        CategoryDefinition(name: "Classical", emoji: "🎻"),
        CategoryDefinition(name: "Country & Folk", emoji: "🌾"),
        CategoryDefinition(name: "Latin", emoji: "🔥"),
        CategoryDefinition(name: "Reggae & Dub", emoji: "🌴"),
        CategoryDefinition(name: "Chill & Ambient", emoji: "🫧"),
        CategoryDefinition(name: "World", emoji: "🌍"),
        CategoryDefinition(name: "Indie & Alternative", emoji: "🌙"),
        CategoryDefinition(name: "Rock", emoji: "🎸"),
        CategoryDefinition(name: "Pop", emoji: "✨"),
    ]

    // Ordered keyword rules: the first category with a matching keyword wins,
    // so specific genres are caught before broad ones ("indie rock" → Indie).
    private static let rules: [(category: String, keywords: [String])] = [
        ("Hip-Hop & Rap", ["hip hop", "hip-hop", "rap", "trap", "drill", "grime"]),
        ("Metal", ["metal", "metalcore", "deathcore", "doom", "thrash", "djent", "hardcore"]),
        ("Electronic & Dance", ["edm", "house", "techno", "trance", "dubstep", "electro",
                                 "drum and bass", "dnb", "synthwave", "idm", "breakbeat", "electronica"]),
        ("R&B & Soul", ["r&b", "rnb", "soul", "funk", "motown", "neo soul"]),
        ("Jazz & Blues", ["jazz", "blues", "bebop", "swing", "bossa nova"]),
        ("Classical", ["classical", "orchestra", "baroque", "opera", "romanticism", "compositional", "early music"]),
        ("Country & Folk", ["country", "folk", "americana", "bluegrass", "singer-songwriter"]),
        ("Latin", ["latin", "reggaeton", "salsa", "bachata", "cumbia", "tango", "mariachi", "bossa"]),
        ("Reggae & Dub", ["reggae", "dancehall", "ska", "dub", "rocksteady"]),
        ("Chill & Ambient", ["ambient", "lo-fi", "lofi", "chill", "downtempo", "new age", "drone", "sleep"]),
        ("World", ["afrobeat", "afro", "k-pop", "j-pop", "bollywood", "celtic", "flamenco", "highlife", "worldbeat"]),
        ("Indie & Alternative", ["indie", "alternative", "shoegaze", "art pop", "dream pop", "emo", "post-punk"]),
        ("Rock", ["rock", "punk", "grunge", "britpop", "psychedelic", "garage"]),
        ("Pop", ["pop", "boy band", "girl group", "hyperpop"]),
    ]

    static func category(for genre: String) -> String {
        for rule in rules where rule.keywords.contains(where: { genre.contains($0) }) {
            return rule.category
        }
        return "Uncategorized"
    }
}
