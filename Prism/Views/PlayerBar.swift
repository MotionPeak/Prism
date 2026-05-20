import SwiftUI

// Bottom-of-window playback bar for the Web Playback SDK player.
struct PlayerBar: View {
    @Environment(WebPlaybackController.self) private var player

    @State private var isScrubbing = false
    @State private var scrubValue = 0.0

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .background(.bar)
    }

    @ViewBuilder
    private var content: some View {
        if player.isActive {
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    artwork
                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.trackName.isEmpty ? "—" : player.trackName)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Text(player.artistName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    controls
                }
                scrubber
            }
        } else {
            HStack(spacing: 8) {
                if player.hasError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(player.statusMessage)
                    .font(.callout)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
        }
    }

    private var scrubber: some View {
        HStack(spacing: 8) {
            Text(timeString(player.positionMs))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)

            Slider(value: positionBinding, in: 0...Double(max(player.durationMs, 1))) { editing in
                if editing {
                    scrubValue = Double(player.positionMs)
                    isScrubbing = true
                } else {
                    player.seek(toMs: Int(scrubValue))
                    isScrubbing = false
                }
            }

            Text(timeString(player.durationMs))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
        }
    }

    private var positionBinding: Binding<Double> {
        Binding(
            get: { isScrubbing ? scrubValue : Double(player.positionMs) },
            set: { scrubValue = $0 }
        )
    }

    private var artwork: some View {
        Group {
            if let urlString = player.artURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
            } else {
                Rectangle().fill(PrismTheme.spectrum)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button { player.previous() } label: {
                Image(systemName: "backward.fill")
            }
            Button { player.togglePlay() } label: {
                Image(systemName: player.isPaused ? "play.fill" : "pause.fill")
                    .font(.title3)
            }
            Button { player.next() } label: {
                Image(systemName: "forward.fill")
            }
        }
        .buttonStyle(.plain)
    }

    private func timeString(_ ms: Int) -> String {
        let seconds = max(0, ms) / 1000
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
