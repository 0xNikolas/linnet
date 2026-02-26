import SwiftUI
import SwiftData
import LinnetLibrary

private func formatTime(_ seconds: Double) -> String {
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%d:%02d", mins, secs)
}

struct PlaylistDetailView: View {
    let playlistID: PersistentIdentifier
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.modelContext) private var modelContext
    @State private var playlist: Playlist?
    @State private var tracks: [Track] = []
    @State private var selectedTrackIDs: Set<PersistentIdentifier> = []

    var body: some View {
        Group {
            if let playlist {
                playlistContent(playlist)
            } else {
                ContentUnavailableView(
                    "Playlist Not Found",
                    systemImage: "music.note.list"
                )
            }
        }
        .task(id: playlistID) {
            loadPlaylist()
            if let name = playlist?.name {
                NotificationCenter.default.post(
                    name: .registerBreadcrumb,
                    object: nil,
                    userInfo: ["title": name]
                )
            }
        }
    }

    @ViewBuilder
    private func playlistContent(_ playlist: Playlist) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .bottom, spacing: 16) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: 150, height: 150)
                    .overlay {
                        Image(systemName: playlist.isAIGenerated ? "sparkles" : "music.note.list")
                            .font(.app(size: 30))
                            .foregroundStyle(.secondary)
                    }

                VStack(alignment: .leading, spacing: 8) {
                    Text(playlist.name)
                        .font(.app(size: 24, weight: .bold))
                    Text("\(tracks.count) songs")
                        .font(.app(size: 13))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button("Play") {
                            guard let first = tracks.first else { return }
                            player.playTrack(first, queue: tracks, startingAt: 0)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Shuffle") {
                            let shuffled = tracks.shuffled()
                            guard let first = shuffled.first else { return }
                            player.playTrack(first, queue: shuffled, startingAt: 0)
                        }
                        .buttonStyle(.bordered)
                    }
                    .disabled(tracks.isEmpty)
                }
            }
            .padding(20)

            Divider()

            if tracks.isEmpty {
                ContentUnavailableView(
                    "No Tracks",
                    systemImage: "music.note",
                    description: Text("Add songs to this playlist from their context menu.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                trackTable
            }
        }
    }

    @ViewBuilder
    private var trackTable: some View {
        Table(of: Track.self, selection: $selectedTrackIDs) {
            TableColumn("#") { track in
                if let index = tracks.firstIndex(where: { $0.id == track.id }) {
                    Text("\(index + 1)")
                        .font(.app(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .width(32)

            TableColumn("Title") { track in
                Text(track.title)
                    .font(.app(size: 13))
                    .lineLimit(1)
            }

            TableColumn("Artist") { track in
                Text(track.artist?.name ?? "Unknown Artist")
                    .font(.app(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            TableColumn("Album") { track in
                Text(track.album?.name ?? "")
                    .font(.app(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            TableColumn("Duration") { track in
                if track.duration > 0 {
                    Text(formatTime(track.duration))
                        .font(.app(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .width(50)
        } rows: {
            ForEach(tracks) { track in
                TableRow(track)
            }
        }
        .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
            contextMenuContent(for: ids)
        } primaryAction: { ids in
            if let id = ids.first, let index = tracks.firstIndex(where: { $0.id == id }) {
                player.playTrack(tracks[index], queue: tracks, startingAt: index)
            }
        }
    }

    @ViewBuilder
    private func contextMenuContent(for ids: Set<PersistentIdentifier>) -> some View {
        if let id = ids.first, let index = tracks.firstIndex(where: { $0.id == id }) {
            let track = tracks[index]
            Button("Play") {
                player.playTrack(track, queue: tracks, startingAt: index)
            }
            Button("Play Next") {
                player.addNext(track)
            }
            Button("Play Later") {
                player.addLater(track)
            }
            AddToPlaylistMenu(tracks: selectedTracks(for: ids))
            LikeDislikeMenu(tracks: selectedTracks(for: ids))
            Divider()
            if let artist = track.artist {
                Button("Go to Artist") {
                    NotificationCenter.default.post(name: .navigateToArtist, object: nil, userInfo: ["artist": artist])
                }
            }
            if let album = track.album {
                Button("Go to Album") {
                    NotificationCenter.default.post(name: .navigateToAlbum, object: nil, userInfo: ["album": album])
                }
            }
            Divider()
            Button("Remove from Playlist", role: .destructive) {
                removeSelectedTracks(ids)
            }
        }
    }

    private func selectedTracks(for ids: Set<PersistentIdentifier>) -> [Track] {
        tracks.filter { ids.contains($0.id) }
    }

    private func loadPlaylist() {
        let fetched: Playlist? = modelContext.registeredModel(for: playlistID)
            ?? (modelContext.model(for: playlistID) as? Playlist)
        guard let fetched else { return }
        playlist = fetched
        reloadTracks()
    }

    private func reloadTracks() {
        guard let playlist else {
            tracks = []
            return
        }
        let sortedEntries = playlist.entries.sorted { $0.order < $1.order }
        let trackIDs = sortedEntries.map { $0.track.persistentModelID }

        let allTracks: [Track]
        do {
            let descriptor = FetchDescriptor<Track>()
            allTracks = try modelContext.fetch(descriptor)
        } catch {
            tracks = []
            return
        }

        let tracksByID = Dictionary(uniqueKeysWithValues: allTracks.map { ($0.persistentModelID, $0) })
        tracks = trackIDs.compactMap { tracksByID[$0] }
    }

    private func removeSelectedTracks(_ ids: Set<PersistentIdentifier>) {
        guard let playlist else { return }
        let sorted = playlist.entries.sorted { $0.order < $1.order }
        let entriesToRemove = sorted.filter { entry in
            ids.contains(entry.track.persistentModelID)
        }
        for entry in entriesToRemove {
            playlist.entries.removeAll { $0.id == entry.id }
            modelContext.delete(entry)
        }
        let remaining = playlist.entries.sorted { $0.order < $1.order }
        for (i, e) in remaining.enumerated() {
            e.order = i
        }
        try? modelContext.save()
        selectedTrackIDs = []
        reloadTracks()
    }
}
