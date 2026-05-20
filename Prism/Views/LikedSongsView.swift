import AppKit
import SwiftUI

// Liked-songs management: multi-select rows, group by Prism category,
// and bulk-remove from library or move to a playlist.
struct LikedSongsView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Set<String> = []
    @State private var query: String = ""
    @State private var grouping: Grouping = .category
    @State private var showMoveSheet = false

    enum Grouping: String, CaseIterable, Identifiable {
        case category
        case artist
        case none

        var id: String { rawValue }
        var label: String {
            switch self {
            case .category: return "Category"
            case .artist: return "Artist"
            case .none: return "None"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .sheet(isPresented: $showMoveSheet) {
            MoveToPlaylistSheet(
                trackIDs: selection,
                onDone: { selection.removeAll() }
            )
            .environment(model)
        }
    }

    // MARK: - Header

    private var header: some View {
        let liked = model.likedTracks
        return HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(PrismTheme.spectrum)
                Image(systemName: "heart.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
            }
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 3) {
                Text("Liked Songs")
                    .font(.title2.weight(.semibold))
                Text("\(liked.count) tracks · \(selection.count) selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Picker("Group by", selection: $grouping) {
                ForEach(Grouping.allCases) { value in
                    Text(value.label).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            actionButtons
        }
        .padding(16)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                showMoveSheet = true
            } label: {
                Label("Move to Playlist…", systemImage: "text.badge.plus")
            }
            .disabled(selection.isEmpty || model.isWorking)

            Button(role: .destructive) {
                Task { await confirmAndRemove() }
            } label: {
                Label("Remove from Library", systemImage: "heart.slash.fill")
            }
            .disabled(selection.isEmpty || model.isWorking)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let liked = filteredLikedTracks()
        if liked.isEmpty {
            ContentUnavailableView(
                "No liked songs",
                systemImage: "heart",
                description: Text("Sync your Spotify library to see your Liked Songs here.")
            )
        } else {
            VStack(spacing: 0) {
                selectionBar(total: liked.count)
                List {
                    ForEach(groupedSections(from: liked), id: \.title) { section in
                        Section {
                            ForEach(section.tracks) { track in
                                SelectableTrackRow(
                                    track: track,
                                    queue: section.tracks,
                                    isSelected: selection.contains(track.id),
                                    toggle: { toggle(track.id) }
                                )
                            }
                        } header: {
                            sectionHeader(title: section.title, tracks: section.tracks)
                        }
                    }
                }
                .listStyle(.inset)
            }
            .searchable(text: $query, prompt: "Search Liked Songs")
        }
    }

    private func selectionBar(total: Int) -> some View {
        HStack(spacing: 14) {
            Button {
                let ids = filteredLikedTracks().map(\.id)
                if selection.count == ids.count {
                    selection.removeAll()
                } else {
                    selection = Set(ids)
                }
            } label: {
                Text(selection.count == total && total > 0 ? "Deselect All" : "Select All")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)

            if !selection.isEmpty {
                Button("Clear Selection") { selection.removeAll() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.4))
    }

    private func sectionHeader(title: String, tracks: [LibraryTrack]) -> some View {
        let ids = tracks.map(\.id)
        let allSelected = !ids.isEmpty && ids.allSatisfy { selection.contains($0) }
        return HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text("· \(tracks.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button(allSelected ? "Deselect" : "Select") {
                if allSelected {
                    for id in ids { selection.remove(id) }
                } else {
                    for id in ids { selection.insert(id) }
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.tint)
        }
    }

    // MARK: - Data

    private func filteredLikedTracks() -> [LibraryTrack] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let liked = model.likedTracks
        guard !trimmed.isEmpty else { return liked }
        return liked.filter { track in
            track.name.lowercased().contains(trimmed)
                || track.displayArtist.lowercased().contains(trimmed)
                || track.albumName.lowercased().contains(trimmed)
        }
    }

    private struct GroupedSection {
        let title: String
        let tracks: [LibraryTrack]
    }

    private func groupedSections(from tracks: [LibraryTrack]) -> [GroupedSection] {
        switch grouping {
        case .none:
            let sorted = tracks.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return [GroupedSection(title: "All", tracks: sorted)]
        case .artist:
            let groups = Dictionary(grouping: tracks) { $0.artistNames.first ?? "Unknown Artist" }
            return groups
                .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                .map { key, value in
                    GroupedSection(
                        title: key,
                        tracks: value.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    )
                }
        case .category:
            var byCategory: [String: [LibraryTrack]] = [:]
            var orderedNames: [String] = model.library.categories.map(\.name)
            for track in tracks {
                let name = model.categoryName(for: track.id) ?? "Uncategorized"
                if byCategory[name] == nil, !orderedNames.contains(name) {
                    orderedNames.append(name)
                }
                byCategory[name, default: []].append(track)
            }
            return orderedNames.compactMap { name in
                guard let bucket = byCategory[name], !bucket.isEmpty else { return nil }
                let sorted = bucket.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                let emoji = model.library.categories.first { $0.name == name }?.emoji
                let title = emoji.map { "\($0) \(name)" } ?? name
                return GroupedSection(title: title, tracks: sorted)
            }
        }
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
        alert.messageText = "Remove \(count) track\(count == 1 ? "" : "s") from your library?"
        alert.informativeText = "They will be un-liked in your Spotify account. You can re-like them later, but this can't be undone from Prism."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let ids = selection
        selection.removeAll()
        await model.removeFromLibrary(trackIDs: ids)
    }
}

struct SelectableTrackRow: View {
    let track: LibraryTrack
    let queue: [LibraryTrack]
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .onTapGesture(perform: toggle)
            TrackRowView(track: track, queue: queue)
                .contentShape(Rectangle())
                .onTapGesture(perform: toggle)
        }
    }
}

struct MoveToPlaylistSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let trackIDs: Set<String>
    let onDone: () -> Void

    enum Mode: String, CaseIterable, Identifiable {
        case create, existing
        var id: String { rawValue }
        var label: String {
            switch self {
            case .create: return "Create New"
            case .existing: return "Pick Existing"
            }
        }
    }

    @State private var mode: Mode = .create
    @State private var newName: String = ""
    @State private var selectedPlaylistID: String?
    @State private var removeFromLiked: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Move \(trackIDs.count) track\(trackIDs.count == 1 ? "" : "s") to playlist")
                .font(.title3.weight(.semibold))

            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            Group {
                switch mode {
                case .create:
                    createSection
                case .existing:
                    existingSection
                }
            }
            .frame(minHeight: 220)

            Toggle("Also remove from Liked Songs", isOn: $removeFromLiked)
                .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(primaryButtonLabel) { Task { await perform() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit || model.isWorking)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { suggestName() }
    }

    private var primaryButtonLabel: String {
        switch mode {
        case .create: return "Create & Add"
        case .existing: return "Add to Playlist"
        }
    }

    private var canSubmit: Bool {
        switch mode {
        case .create:
            return !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .existing:
            return selectedPlaylistID != nil
        }
    }

    private var createSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Playlist name").font(.subheadline).foregroundStyle(.secondary)
            TextField("My new playlist", text: $newName)
                .textFieldStyle(.roundedBorder)
            Text("A new private playlist will be created in your Spotify account.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var existingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your playlists").font(.subheadline).foregroundStyle(.secondary)
            let playlists = model.ownedPlaylists
            if playlists.isEmpty {
                ContentUnavailableView(
                    "No playlists you own yet",
                    systemImage: "music.note.list",
                    description: Text("Create a new playlist instead.")
                )
            } else {
                List(playlists, selection: $selectedPlaylistID) { playlist in
                    Text(playlist.name).tag(playlist.id)
                }
                .frame(minHeight: 180)
            }
        }
    }

    private func suggestName() {
        guard newName.isEmpty else { return }
        let suggestion = dominantCategoryName(for: trackIDs)
        newName = suggestion.map { "Prism · \($0)" } ?? "Prism · Liked Songs"
    }

    private func dominantCategoryName(for ids: Set<String>) -> String? {
        var counts: [String: Int] = [:]
        for id in ids {
            if let name = model.categoryName(for: id) {
                counts[name, default: 0] += 1
            }
        }
        return counts.max { $0.value < $1.value }?.key
    }

    private func perform() async {
        switch mode {
        case .create:
            await model.addToNewPlaylist(name: newName, trackIDs: trackIDs, removeFromLiked: removeFromLiked)
        case .existing:
            guard let id = selectedPlaylistID else { return }
            await model.addToExistingPlaylist(playlistID: id, trackIDs: trackIDs, removeFromLiked: removeFromLiked)
        }
        onDone()
        dismiss()
    }
}
