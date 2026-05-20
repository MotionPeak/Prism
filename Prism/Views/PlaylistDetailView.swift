import SwiftUI

// Shows the tracks inside one of the user's Spotify playlists.
struct PlaylistDetailView: View {
    @Environment(AppModel.self) private var model
    let playlist: StoredPlaylist

    var body: some View {
        @Bindable var model = model
        let tracks = model.filteredTracks(inPlaylist: playlist)
        return VStack(spacing: 0) {
            header
            Divider()
            if model.tracks(inPlaylist: playlist).isEmpty {
                ContentUnavailableView(
                    "No tracks to show",
                    systemImage: "music.note.list",
                    description: Text("Spotify only shares the contents of playlists you own or collaborate on. Followed playlists appear here without their tracks.")
                )
            } else if tracks.isEmpty {
                ContentUnavailableView.search
            } else {
                List {
                    ForEach(tracks) { track in
                        TrackRowView(track: track, queue: tracks)
                    }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $model.searchText, prompt: "Search this playlist")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 28))
                .foregroundStyle(.white)
                .frame(width: 62, height: 62)
                .background(
                    PrismTheme.spectrum,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .font(.title2.weight(.semibold))
                Text("\(playlist.trackIDs.count) tracks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }
}
