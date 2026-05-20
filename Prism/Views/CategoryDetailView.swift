import AppKit
import SwiftUI

struct CategoryDetailView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Set<String> = []
    @State private var showMoveSheet = false

    var body: some View {
        Group {
            if !model.hasLibrary {
                EmptyLibraryView()
            } else if model.selectedCategoryID == AppModel.likedSongsID {
                LikedSongsView()
            } else if let playlist = model.selectedPlaylist {
                PlaylistDetailView(playlist: playlist)
            } else if let category = model.selectedCategory {
                categoryView(category)
            } else {
                ContentUnavailableView(
                    "Select a category",
                    systemImage: "square.grid.2x2",
                    description: Text("Pick a category or playlist from the sidebar to see its tracks.")
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
                selectionBar(tracks: tracks)
                List {
                    ForEach(tracks) { track in
                        SelectableTrackRow(
                            track: track,
                            queue: tracks,
                            isSelected: selection.contains(track.id),
                            toggle: { toggle(track.id) }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $model.searchText, prompt: "Search this category")
        .sheet(isPresented: $showMoveSheet) {
            MoveToPlaylistSheet(trackIDs: selection) { selection.removeAll() }
                .environment(model)
        }
        .onChange(of: model.selectedCategoryID) { selection.removeAll() }
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
                Text(subtitle(category))
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
            .help("Save this whole category as a private playlist in Spotify")

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

    private func subtitle(_ category: Category) -> String {
        let base = "\(category.trackIDs.count) tracks"
        return selection.isEmpty ? base : "\(base) · \(selection.count) selected"
    }

    private func selectionBar(tracks: [LibraryTrack]) -> some View {
        let ids = tracks.map(\.id)
        let allSelected = !ids.isEmpty && ids.allSatisfy { selection.contains($0) }
        return HStack(spacing: 14) {
            Button(allSelected ? "Deselect All" : "Select All") {
                if allSelected {
                    selection.subtract(ids)
                } else {
                    selection.formUnion(ids)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)

            if !selection.isEmpty {
                Button("Clear") { selection.removeAll() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showMoveSheet = true
            } label: {
                Label("Move to Playlist…", systemImage: "text.badge.plus")
            }
            .disabled(selection.isEmpty || model.isWorking)

            Button(role: .destructive) {
                Task { await confirmAndRemove() }
            } label: {
                Label("Remove from Liked", systemImage: "heart.slash")
            }
            .disabled(selection.isEmpty || model.isWorking)
            .help("Un-like the selected tracks in your Spotify account")
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.4))
    }

    private func toggle(_ id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    @MainActor
    private func confirmAndRemove() async {
        let count = selection.count
        let alert = NSAlert()
        alert.messageText = "Remove \(count) track\(count == 1 ? "" : "s") from your Liked Songs?"
        alert.informativeText = "They will be un-liked in your Spotify account. Tracks that aren't liked are left untouched."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let ids = selection
        selection.removeAll()
        await model.removeFromLibrary(trackIDs: ids)
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
