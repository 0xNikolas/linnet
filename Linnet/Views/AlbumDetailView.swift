import SwiftUI
import LinnetLibrary
import UniformTypeIdentifiers

private func formatTime(_ seconds: Double) -> String {
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%d:%02d", mins, secs)
}

struct AlbumDetailView: View {
    let album: AlbumRecord
    @Environment(PlayerViewModel.self) private var player
    @Environment(ArtworkService.self) private var artworkService
    @Environment(\.appDatabase) private var appDatabase
    @State private var isFetchingArtwork = false
    @State private var showEditSheet = false
    @State private var artworkImage: NSImage?
    @State private var tracks: [TrackInfo] = []

    private var sortedTracks: [TrackInfo] {
        tracks.sorted {
            ($0.discNumber, $0.trackNumber) < ($1.discNumber, $1.trackNumber)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .bottom, spacing: 20) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: 200, height: 200)
                    .overlay {
                        if let img = artworkImage {
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFill()
                        } else if isFetchingArtwork {
                            ProgressView()
                        } else {
                            Image(systemName: "music.note")
                                .font(.app(size: 40))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .task {
                        loadArtwork()
                        guard artworkImage == nil, let db = appDatabase, let albumId = album.id else { return }
                        isFetchingArtwork = true
                        let _ = await artworkService.fetchAlbumArtwork(
                            albumId: albumId,
                            albumName: album.name,
                            artistName: album.artistName,
                            db: db
                        )
                        loadArtwork()
                        isFetchingArtwork = false
                    }
                    .contextMenu {
                        Button("Find Artwork") {
                            Task {
                                guard let db = appDatabase, let albumId = album.id else { return }
                                artworkImage = nil
                                isFetchingArtwork = true
                                let _ = await artworkService.fetchAlbumArtwork(
                                    albumId: albumId,
                                    albumName: album.name,
                                    artistName: album.artistName,
                                    db: db,
                                    force: true
                                )
                                loadArtwork()
                                isFetchingArtwork = false
                            }
                        }
                        Button("Choose Artwork...") {
                            chooseArtworkFile()
                        }
                        Divider()
                        Button("Edit Album...") { showEditSheet = true }
                    }
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text(album.name)
                        .font(.app(size: 28, weight: .bold))
                    if let artistId = album.artistId, let artistName = album.artistName {
                        Button {
                            NotificationCenter.default.post(name: .navigateToArtist, object: nil, userInfo: ["artistId": artistId, "artistName": artistName])
                        } label: {
                            Text(artistName)
                                .font(.app(size: 18))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    } else {
                        Text(album.artistName ?? "Unknown Artist")
                            .font(.app(size: 18))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        if let year = album.year {
                            Text(String(year))
                                .font(.app(size: 13))
                                .foregroundStyle(.tertiary)
                        }
                        Text("\(sortedTracks.count) songs")
                            .font(.app(size: 13))
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 12) {
                        Button("Play") {
                            if let first = sortedTracks.first {
                                player.playTrack(first, queue: sortedTracks, startingAt: 0)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                        .disabled(sortedTracks.isEmpty)

                        Button("Shuffle") {
                            let shuffled = sortedTracks.shuffled()
                            if let first = shuffled.first {
                                player.playTrack(first, queue: shuffled, startingAt: 0)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(sortedTracks.isEmpty)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(20)

            Divider()

            AlbumTrackListView(
                sortedTracks: sortedTracks,
                onPlay: { track, queue, index in
                    player.playTrack(track, queue: queue, startingAt: index)
                },
                onPlayNext: { track in
                    player.addNext(track)
                },
                onPlayLater: { track in
                    player.addLater(track)
                },
                onRemove: { trackIDs in
                    removeTracks(ids: trackIDs)
                }
            )
        }
        .task {
            loadTracks()
        }
        .sheet(isPresented: $showEditSheet) {
            EditAlbumSheet(album: album)
        }
    }

    private func loadTracks() {
        guard let albumId = album.id else { return }
        tracks = (try? appDatabase?.tracks.fetchInfoByAlbum(id: albumId)) ?? []
    }

    private func loadArtwork() {
        guard let albumId = album.id, let db = appDatabase,
              let data = try? db.artwork.fetchImageData(ownerType: "album", ownerId: albumId),
              let img = NSImage(data: data) else {
            artworkImage = nil
            return
        }
        artworkImage = img
    }

    private func chooseArtworkFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose artwork for \"\(album.name)\""
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url) {
            guard let albumId = album.id, let db = appDatabase else { return }
            try? db.artwork.upsert(ownerType: "album", ownerId: albumId, imageData: data, thumbnailData: nil)
            artworkImage = NSImage(data: data)
        }
    }

    private func removeTracks(ids: Set<Int64>) {
        guard let db = appDatabase else { return }
        for id in ids {
            try? db.tracks.delete(id: id)
        }
        try? db.albums.deleteOrphaned()
        try? db.artists.deleteOrphaned()
        loadTracks()
    }
}

// MARK: - AlbumTrackListView (no player environment -- immune to timer-driven redraws)

private struct AlbumTrackListView: View {
    let sortedTracks: [TrackInfo]
    let onPlay: (TrackInfo, [TrackInfo], Int) -> Void
    let onPlayNext: (TrackInfo) -> Void
    let onPlayLater: (TrackInfo) -> Void
    let onRemove: (Set<Int64>) -> Void

    @State private var selectedTrackIDs: Set<Int64> = []

    var body: some View {
        List(sortedTracks, selection: $selectedTrackIDs) { track in
            HStack {
                Text("\(track.trackNumber)")
                    .font(.app(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)

                Text(track.title)
                    .font(.app(size: 13))

                Spacer()

                Text(formatTime(track.duration))
                    .font(.app(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: Int64.self) { ids in
            contextMenuContent(for: ids)
        } primaryAction: { ids in
            if let id = ids.first, let index = sortedTracks.firstIndex(where: { $0.id == id }) {
                onPlay(sortedTracks[index], sortedTracks, index)
            }
        }
    }

    @ViewBuilder
    private func contextMenuContent(for ids: Set<Int64>) -> some View {
        if let id = ids.first, let index = sortedTracks.firstIndex(where: { $0.id == id }) {
            let track = sortedTracks[index]
            Button { onPlay(track, sortedTracks, index) } label: { Label("Play", systemImage: "play") }
            Button { onPlayNext(track) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button { onPlayLater(track) } label: { Label("Play Later", systemImage: "text.line.last.and.arrowtriangle.forward") }
            Divider()
            AddToPlaylistMenu(tracks: selectedTracks(for: ids))
            LikeDislikeMenu(tracks: selectedTracks(for: ids))
            Divider()
            if let artistId = track.artistId, let artistName = track.artistName {
                Button {
                    NotificationCenter.default.post(name: .navigateToArtist, object: nil, userInfo: ["artistId": artistId, "artistName": artistName])
                } label: { Label("Go to Artist", systemImage: "music.mic") }
            }
            Divider()
            Button(role: .destructive) { onRemove(ids) } label: { Label("Remove from Library", systemImage: "trash") }
        }
    }

    private func selectedTracks(for ids: Set<Int64>) -> [TrackInfo] {
        sortedTracks.filter { ids.contains($0.id) }
    }
}
