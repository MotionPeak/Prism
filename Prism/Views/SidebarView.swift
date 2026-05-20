import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedCategoryID) {
            if let profile = model.library.profile {
                Section {
                    profileRow(profile)
                }
            }
            Section("Library") {
                likedSongsRow.tag(AppModel.likedSongsID)
            }
            Section("Categories") {
                if model.library.categories.isEmpty {
                    Text("No categories yet. Sync to get started.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.library.categories) { category in
                        categoryRow(category)
                            .tag(category.id)
                    }
                }
            }
            if !model.library.playlists.isEmpty {
                Section("Playlists") {
                    ForEach(model.library.playlists) { playlist in
                        playlistRow(playlist)
                            .tag(AppModel.playlistTag(playlist.id))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            footer
        }
    }

    private func profileRow(_ profile: StoredProfile) -> some View {
        HStack(spacing: 10) {
            avatar(profile)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(model.library.tracks.count) tracks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func avatar(_ profile: StoredProfile) -> some View {
        Group {
            if let urlString = profile.imageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(.quaternary)
                }
            } else {
                Circle().fill(PrismTheme.spectrum)
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
    }

    private var likedSongsRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.fill")
                .font(.title3)
                .foregroundStyle(.pink)
            VStack(alignment: .leading, spacing: 1) {
                Text("Liked Songs")
                    .font(.body)
                    .lineLimit(1)
                Text("\(model.likedTracks.count) tracks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func categoryRow(_ category: Category) -> some View {
        HStack(spacing: 10) {
            Text(category.emoji)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(category.name)
                    .font(.body)
                    .lineLimit(1)
                Text("\(category.trackIDs.count) tracks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func playlistRow(_ playlist: StoredPlaylist) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(playlist.name)
                    .font(.body)
                    .lineLimit(1)
                Text("\(playlist.trackIDs.count) tracks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            if let synced = model.library.lastSynced {
                Label(
                    "Synced \(synced.formatted(.relative(presentation: .named)))",
                    systemImage: "clock"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if model.library.categories.isEmpty {
                Button {
                    Task { await model.refreshEverything() }
                } label: {
                    Label("Sync & Categorize", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .disabled(model.isWorking)
            }
        }
        .padding(10)
    }
}
