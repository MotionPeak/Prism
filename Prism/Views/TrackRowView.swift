import AppKit
import SwiftUI

struct TrackRowView: View {
    @Environment(WebPlaybackController.self) private var player
    let track: LibraryTrack
    let queue: [LibraryTrack]

    @State private var isHovering = false

    private var isCurrent: Bool {
        player.currentURI != nil && player.currentURI == track.uri
    }

    var body: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if isCurrent {
                        NowPlayingBars(isAnimating: !player.isPaused)
                    }
                    Text(track.name)
                        .font(.body)
                        .foregroundStyle(isCurrent ? Color.accentColor : .primary)
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
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Play") { play() }
            if let url = track.spotifyURL {
                Button("Open in Spotify") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    // Album art doubles as a play button — a play icon appears on hover.
    private var artwork: some View {
        Button(action: play) {
            ZStack {
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
                if isHovering {
                    Color.black.opacity(0.5)
                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 46, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Play this track")
    }

    private func play() {
        Task { await player.play(track: track, in: queue) }
    }
}

// Animated equalizer shown on the track that is currently playing.
struct NowPlayingBars: View {
    var isAnimating: Bool

    @State private var lifted = false

    private let heights: [CGFloat] = [6, 13, 9, 12]
    private let durations: [Double] = [0.52, 0.40, 0.63, 0.47]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(.tint)
                    .frame(width: 2.5, height: lifted ? heights[index] : 3)
                    .animation(
                        isAnimating
                            ? .easeInOut(duration: durations[index]).repeatForever(autoreverses: true)
                            : .easeOut(duration: 0.2),
                        value: lifted
                    )
            }
        }
        .frame(width: 18, height: 13, alignment: .bottom)
        .onAppear { lifted = isAnimating }
        .onChange(of: isAnimating) { _, newValue in lifted = newValue }
    }
}
