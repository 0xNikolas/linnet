import SwiftUI
import LinnetLibrary

struct ListenNowView: View {
    @Environment(\.appDatabase) private var appDatabase
    @Environment(PlayerViewModel.self) private var player
    @Environment(ArtworkService.self) private var artworkService
    @Environment(\.navigationPath) private var navigationPath
    @State private var albums: [AlbumInfo] = []
    @State private var recentTracks: [TrackInfo] = []
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var selectedTrackID: Int64?
    @State private var selectedAlbumID: Int64?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text("Listen Now")
                    .font(.largeTitle.bold())
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                if albums.isEmpty && recentTracks.isEmpty {
                    ContentUnavailableView("Welcome to Linnet", systemImage: "music.note.house", description: Text("Add a music folder in Settings to get started."))
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    if !recentTracks.isEmpty {
                        let displayedTracks = Array(recentTracks.prefix(10))
                        HorizontalScrollRow(title: "Recently Added") {
                            ForEach(Array(displayedTracks.enumerated()), id: \.element.id) { index, track in
                                ListenNowTrackCard(
                                    track: track,
                                    isSelected: selectedTrackID == track.id,
                                    onSelect: {
                                        selectedTrackID = track.id
                                        selectedAlbumID = nil
                                    },
                                    onPlay: {
                                        player.playTrack(track, queue: displayedTracks, startingAt: index)
                                    },
                                    onPlayNext: { player.addNext(track) },
                                    onPlayLater: { player.addLater(track) },
                                    displayedTracks: displayedTracks,
                                    index: index,
                                    onRemove: {
                                        removeTrack(track)
                                    }
                                )
                            }
                        }
                    }

                    if !albums.isEmpty {
                        HorizontalScrollRow(title: "Albums") {
                            ForEach(albums.prefix(10)) { album in
                                ListenNowAlbumCard(
                                    album: album,
                                    isSelected: selectedAlbumID == album.id,
                                    onSelect: {
                                        selectedAlbumID = album.id
                                        selectedTrackID = nil
                                    },
                                    onNavigate: {
                                        let record = AlbumRecord(id: album.id, name: album.name, artistName: album.artistName, year: album.year, artistId: album.artistId)
                                        navigationPath.wrappedValue.append(record)
                                    },
                                    onRemove: { removeAlbum(album) }
                                )
                            }
                        }
                    }

                    if searchText.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.app(size: 28))
                                .foregroundStyle(.secondary)
                            Text("AI Suggestions")
                                .font(.app(size: 15, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("Set up AI in Settings to get personalized recommendations.")
                                .font(.app(size: 13))
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                            Button("Open Settings...") {
                                NotificationCenter.default.post(name: .openSettings, object: nil)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search...")
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            isSearchPresented = true
        }
        .task { loadData() }
        .onChange(of: searchText) { _, _ in loadData() }
    }

    private func loadData() {
        guard let db = appDatabase else { return }
        if searchText.isEmpty {
            albums = (try? db.albums.fetchAllInfo()) ?? []
            recentTracks = (try? db.tracks.fetchRecentlyAddedInfo(limit: 20)) ?? []
        } else {
            albums = (try? db.albums.searchInfo(query: searchText)) ?? []
            recentTracks = (try? db.tracks.searchAllInfo(query: searchText, limit: 20)) ?? []
        }
    }

    private func removeTrack(_ track: TrackInfo) {
        guard let db = appDatabase else { return }
        try? db.tracks.delete(id: track.id)
        try? db.albums.deleteOrphaned()
        try? db.artists.deleteOrphaned()
        loadData()
    }

    private func removeAlbum(_ album: AlbumInfo) {
        guard let db = appDatabase else { return }
        let tracks = (try? db.tracks.fetchInfoByAlbum(id: album.id)) ?? []
        for track in tracks {
            try? db.tracks.delete(id: track.id)
        }
        try? db.albums.delete(id: album.id)
        try? db.artwork.delete(ownerType: "album", ownerId: album.id)
        try? db.artists.deleteOrphaned()
        loadData()
    }
}

// MARK: - Track Card

private struct ListenNowTrackCard: View {
    let track: TrackInfo
    let isSelected: Bool
    let onSelect: () -> Void
    let onPlay: () -> Void
    let onPlayNext: () -> Void
    let onPlayLater: () -> Void
    let displayedTracks: [TrackInfo]
    let index: Int
    let onRemove: () -> Void

    @Environment(ArtworkService.self) private var artworkService
    @Environment(\.appDatabase) private var appDatabase
    @State private var artwork: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(width: 160, height: 160)
                .overlay {
                    if let artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "music.note")
                            .font(.app(size: 30))
                            .foregroundStyle(.secondary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(track.title)
                .font(.app(size: 13, weight: .medium))
                .lineLimit(1)
            Text(track.artistName ?? "Unknown")
                .font(.app(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 160)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .onClicks(single: { onSelect() }, double: { onPlay() })
        .task {
            loadArtwork()
            guard artwork == nil, let albumId = track.albumId, let db = appDatabase else { return }
            let found = await artworkService.fetchAlbumArtwork(albumId: albumId, albumName: track.albumName ?? "", artistName: track.artistName, db: db)
            if found { loadArtwork() }
        }
        .contextMenu {
            Button { onPlay() } label: { Label("Play", systemImage: "play") }
            Button { onPlayNext() } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button { onPlayLater() } label: { Label("Play Later", systemImage: "text.line.last.and.arrowtriangle.forward") }
            AddToPlaylistMenu(tracks: [track])
            LikeDislikeMenu(tracks: [track])
            Divider()
            if let artistId = track.artistId {
                Button {
                    NotificationCenter.default.post(name: .navigateToArtist, object: nil, userInfo: ["artistId": artistId, "artistName": track.artistName ?? ""])
                } label: { Label("Go to Artist", systemImage: "music.mic") }
            }
            if let albumId = track.albumId {
                Button {
                    NotificationCenter.default.post(name: .navigateToAlbum, object: nil, userInfo: ["albumId": albumId])
                } label: { Label("Go to Album", systemImage: "square.stack") }
            }
            Divider()
            Button(role: .destructive) { onRemove() } label: { Label("Remove from Library", systemImage: "trash") }
        }
    }

    private func loadArtwork() {
        guard let db = appDatabase, let albumId = track.albumId,
              let data = try? db.artwork.fetchImageData(ownerType: "album", ownerId: albumId),
              let img = NSImage(data: data) else { return }
        artwork = img
    }
}

// MARK: - Album Card

private struct ListenNowAlbumCard: View {
    let album: AlbumInfo
    let isSelected: Bool
    let onSelect: () -> Void
    let onNavigate: () -> Void
    let onRemove: () -> Void

    @Environment(ArtworkService.self) private var artworkService
    @Environment(\.appDatabase) private var appDatabase
    @State private var artwork: NSImage?

    var body: some View {
        AlbumCard(
            name: album.name,
            artist: album.artistName ?? "Unknown",
            artwork: artwork
        )
        .frame(width: 160)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .onClicks(single: { onSelect() }, double: { onNavigate() })
        .task {
            loadArtwork()
            guard artwork == nil, let db = appDatabase else { return }
            let found = await artworkService.fetchAlbumArtwork(albumId: album.id, albumName: album.name, artistName: album.artistName, db: db)
            if found { loadArtwork() }
        }
        .contextMenu {
            let tracks = (try? appDatabase?.tracks.fetchInfoByAlbum(id: album.id)) ?? []
            LikeDislikeMenu(tracks: tracks)
            Divider()
            if let artistId = album.artistId {
                Button {
                    NotificationCenter.default.post(name: .navigateToArtist, object: nil, userInfo: ["artistId": artistId, "artistName": album.artistName ?? ""])
                } label: { Label("Go to Artist", systemImage: "music.mic") }
            }
            Divider()
            Button(role: .destructive) { onRemove() } label: { Label("Remove from Library", systemImage: "trash") }
        }
    }

    private func loadArtwork() {
        guard let db = appDatabase,
              let data = try? db.artwork.fetchImageData(ownerType: "album", ownerId: album.id),
              let img = NSImage(data: data) else { return }
        artwork = img
    }
}
