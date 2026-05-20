import AppKit
import SwiftUI

struct TrackRowView: View {
    let track: LibraryTrack

    var body: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(track.name)
                        .font(.body)
                        .lineLimit(1)
                    if track.explicit {
                        Text("E")
                            .font(.system(size: 8, weight: .bold))
                            .padding(2)
                            .background(.secondary.opacity(0.3), in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text(track.displayArtist)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !track.genres.isEmpty {
                    Text(track.genres.prefix(3).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(track.durationText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let year = track.releaseYear {
                    Text(String(year))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .contextMenu {
            if let url = track.spotifyURL {
                Button("Open in Spotify") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private var artwork: some View {
        Group {
            if let urlString = track.albumArtURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
            } else {
                Rectangle().fill(PrismTheme.spectrum)
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
