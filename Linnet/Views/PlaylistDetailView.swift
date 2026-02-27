import SwiftUI
import LinnetLibrary

private func formatTime(_ seconds: Double) -> String {
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%d:%02d", mins, secs)
}

struct PlaylistDetailView: View {
    let playlistID: Int64
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.appDatabase) private var appDatabase
    @State private var playlist: PlaylistRecord?
    @State private var tracks: [TrackInfo] = []
    @State private var selectedTrackIDs: Set<Int64> = []

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
    private func playlistContent(_ playlist: PlaylistRecord) -> some View {
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
        Table(of: TrackInfo.self, selection: $selectedTrackIDs) {
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
                Text(track.artistName ?? "Unknown Artist")
                    .font(.app(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            TableColumn("Album") { track in
                Text(track.albumName ?? "")
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
        .contextMenu(forSelectionType: Int64.self) { ids in
            contextMenuContent(for: ids)
        } primaryAction: { ids in
            if let id = ids.first, let index = tracks.firstIndex(where: { $0.id == id }) {
                player.playTrack(tracks[index], queue: tracks, startingAt: index)
            }
        }
    }

    @ViewBuilder
    private func contextMenuContent(for ids: Set<Int64>) -> some View {
        if let id = ids.first, let index = tracks.firstIndex(where: { $0.id == id }) {
            let track = tracks[index]
            Button { player.playTrack(track, queue: tracks, startingAt: index) } label: { Label("Play", systemImage: "play") }
            Button { player.addNext(track) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button { player.addLater(track) } label: { Label("Play Later", systemImage: "text.line.last.and.arrowtriangle.forward") }
            AddToPlaylistMenu(tracks: selectedTracks(for: ids))
            LikeDislikeMenu(tracks: selectedTracks(for: ids))
            Divider()
            if let artistId = track.artistId, let artistName = track.artistName {
                Button {
                    NotificationCenter.default.post(name: .navigateToArtist, object: nil, userInfo: ["artistId": artistId, "artistName": artistName])
                } label: { Label("Go to Artist", systemImage: "music.mic") }
            }
            if let albumId = track.albumId {
                Button {
                    NotificationCenter.default.post(name: .navigateToAlbum, object: nil, userInfo: ["albumId": albumId])
                } label: { Label("Go to Album", systemImage: "square.stack") }
            }
            Divider()
            Button(role: .destructive) { removeSelectedTracks(ids) } label: { Label("Remove from Playlist", systemImage: "minus.circle") }
        }
    }

    private func selectedTracks(for ids: Set<Int64>) -> [TrackInfo] {
        tracks.filter { ids.contains($0.id) }
    }

    private func loadPlaylist() {
        playlist = try? appDatabase?.playlists.fetchOne(id: playlistID)
        reloadTracks()
    }

    private func reloadTracks() {
        tracks = (try? appDatabase?.playlists.fetchTrackInfos(playlistId: playlistID)) ?? []
    }

    private func removeSelectedTracks(_ ids: Set<Int64>) {
        try? appDatabase?.playlists.removeEntries(trackIds: ids, fromPlaylist: playlistID)
        selectedTrackIDs = []
        reloadTracks()
    }
}
