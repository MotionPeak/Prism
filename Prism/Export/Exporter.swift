import Foundation

// Renders categorized tracks as CSV for export.
enum Exporter {
    struct Row {
        let category: String
        let track: LibraryTrack
    }

    static func csv(rows: [Row]) -> String {
        var lines = ["Category,Track,Artists,Album,Year,Duration,Genres,Spotify URL"]
        for row in rows {
            let fields = [
                row.category,
                row.track.name,
                row.track.displayArtist,
                row.track.albumName,
                row.track.releaseYear.map(String.init) ?? "",
                row.track.durationText,
                row.track.genres.joined(separator: "; "),
                row.track.spotifyURL?.absoluteString ?? "",
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
