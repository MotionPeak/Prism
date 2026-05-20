import SwiftUI

struct CategoryDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if !model.hasLibrary {
                EmptyLibraryView()
            } else if let category = model.selectedCategory {
                categoryView(category)
            } else {
                ContentUnavailableView(
                    "Select a category",
                    systemImage: "square.grid.2x2",
                    description: Text("Pick a category from the sidebar to see its tracks.")
                )
            }
        }
    }

    private func categoryView(_ category: Category) -> some View {
        @Bindable var model = model
        let tracks = model.filteredTracks(in: category)
        return VStack(spacing: 0) {
            header(category)
            Divider()
            if tracks.isEmpty {
                ContentUnavailableView.search
            } else {
                List {
                    ForEach(tracks) { track in
                        TrackRowView(track: track)
                    }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $model.searchText, prompt: "Search this category")
    }

    private func header(_ category: Category) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(category.emoji)
                .font(.system(size: 38))
                .frame(width: 62, height: 62)
                .background(
                    PrismTheme.color(for: category.name).opacity(0.18),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(category.name)
                    .font(.title2.weight(.semibold))
                Text("\(category.trackIDs.count) tracks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await model.createPlaylist(for: category) }
            } label: {
                Label("Create Playlist", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isWorking)
            .help("Save this category as a private playlist in your Spotify account")

            Menu {
                Button("Export This Category…") { model.exportCSV(for: category) }
                Button("Export Entire Library…") { model.exportCSV(for: nil) }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .fixedSize()
        }
        .padding(16)
    }
}

struct EmptyLibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            PrismMark(size: 86)
            Text("Your library is empty")
                .font(.title2.weight(.semibold))
            Text("Sync pulls your liked songs, playlists, top tracks and recent plays from Spotify, then sorts them into categories on your Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 390)
            Button {
                Task { await model.refreshEverything() }
            } label: {
                Label("Sync & Categorize", systemImage: "sparkles")
                    .frame(width: 210)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(model.isWorking)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
