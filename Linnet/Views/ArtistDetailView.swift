import SwiftUI
import LinnetLibrary
import GRDB
import UniformTypeIdentifiers

// File-level storage -- survives SwiftUI view lifecycle
private nonisolated(unsafe) var _albumCardLastClickTime: Date = .distantPast
private nonisolated(unsafe) var _artistDetailCache: [Int64: ArtistDetailData] = [:]

private struct ArtistDetailData: Sendable {
    let allTracks: [TrackInfo]
    let albums: [AlbumInfo]
}

struct ArtistDetailView: View {
    let artist: ArtistRecord
    @Binding var navigationPath: NavigationPath
    @Environment(PlayerViewModel.self) private var player
    @Environment(ArtworkService.self) private var artworkService
    @Environment(\.appDatabase) private var appDatabase
    @State private var selectedAlbumID: Int64?
    @State private var selectedTrackID: Int64?
    @State private var isFetchingArtwork = false
    @State private var observer: DatabaseObserver<ArtistDetailData>?
    @State private var artworkImage: NSImage?
    @State private var hasLoaded = false

    private var allTracks: [TrackInfo] {
        var tracks = observer?.value.allTracks ?? []
        tracks.sort { lhs, rhs in
            let lhsYear = lhs.year ?? 0
            let rhsYear = rhs.year ?? 0
            if lhsYear != rhsYear { return lhsYear > rhsYear }
            let lhsAlbum = lhs.albumName ?? ""
            let rhsAlbum = rhs.albumName ?? ""
            if lhsAlbum != rhsAlbum { return lhsAlbum < rhsAlbum }
            if lhs.discNumber != rhs.discNumber { return lhs.discNumber < rhs.discNumber }
            return lhs.trackNumber < rhs.trackNumber
        }
        return tracks
    }

    private var albums: [AlbumInfo] { observer?.value.albums ?? [] }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hero
                HStack(spacing: 16) {
                    Circle()
                        .fill(.quaternary)
                        .frame(width: 120, height: 120)
                        .overlay {
                            if let img = artworkImage {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFill()
                            } else if isFetchingArtwork {
                                ProgressView()
                            } else {
                                Image(systemName: "music.mic")
                                    .font(.app(size: 40))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .clipShape(Circle())
                        .task {
                            loadArtwork()
                            guard artworkImage == nil, let db = appDatabase, let artistId = artist.id else { return }
                            isFetchingArtwork = true
                            let _ = await artworkService.fetchArtistArtwork(
                                artistId: artistId,
                                artistName: artist.name,
                                db: db
                            )
                            loadArtwork()
                            isFetchingArtwork = false
                        }
                        .contextMenu {
                            Button {
                                Task {
                                    guard let db = appDatabase, let artistId = artist.id else { return }
                                    artworkImage = nil
                                    isFetchingArtwork = true
                                    let _ = await artworkService.fetchArtistArtwork(
                                        artistId: artistId,
                                        artistName: artist.name,
                                        db: db,
                                        force: true
                                    )
                                    loadArtwork()
                                    isFetchingArtwork = false
                                }
                            } label: { Label("Find Artwork", systemImage: "photo") }
                            Button { chooseArtistArtwork() } label: { Label("Choose Artwork...", systemImage: "folder") }
                        }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(artist.name)
                            .font(.app(size: 28, weight: .bold))

                        if hasLoaded {
                            Text("\(albums.count) albums, \(allTracks.count) songs")
                                .font(.app(size: 13))
                                .foregroundStyle(.tertiary)
                        }

                        HStack(spacing: 12) {
                            Button("Play") {
                                if let first = allTracks.first {
                                    player.playTrack(first, queue: allTracks, startingAt: 0)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(allTracks.isEmpty)

                            Button("Shuffle") {
                                let shuffled = allTracks.shuffled()
                                if let first = shuffled.first {
                                    player.playTrack(first, queue: shuffled, startingAt: 0)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(allTracks.isEmpty)
                        }
                    }
                }
                .padding(20)

                if !hasLoaded {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading...")
                            .font(.app(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
                } else {
                    // Albums section
                    if !albums.isEmpty {
                        Text("Albums")
                            .font(.headline)
                            .padding(.horizontal, 20)

                        let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)]
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(albums.sorted(by: { ($0.year ?? Int.min) > ($1.year ?? Int.min) })) { albumInfo in
                                ArtistAlbumCard(
                                    albumInfo: albumInfo,
                                    artistName: artist.name,
                                    isSelected: selectedAlbumID == albumInfo.id,
                                    onSelect: {
                                        selectedAlbumID = albumInfo.id
                                        selectedTrackID = nil
                                    },
                                    onNavigate: {
                                        let record = AlbumRecord(
                                            id: albumInfo.id,
                                            name: albumInfo.name,
                                            artistName: albumInfo.artistName,
                                            year: albumInfo.year,
                                            artistId: albumInfo.artistId
                                        )
                                        navigationPath.append(record)
                                    },
                                    onRemove: { removeAlbum(albumInfo) }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // Songs section
                    if !allTracks.isEmpty {
                        Text("Songs")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.top, 4)

                        VStack(spacing: 0) {
                            ForEach(Array(allTracks.enumerated()), id: \.element.id) { index, track in
                                ArtistTrackRow(
                                    track: track,
                                    index: index,
                                    isSelected: selectedTrackID == track.id,
                                    allTracks: allTracks,
                                    onSelect: {
                                        selectedTrackID = track.id
                                        selectedAlbumID = nil
                                    },
                                    onPlay: { t, q, i in player.playTrack(t, queue: q, startingAt: i) },
                                    onPlayNext: { player.addNext($0) },
                                    onPlayLater: { player.addLater($0) },
                                    onRemove: { removeTrack($0) }
                                )
                                .id(track.id)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .animation(.easeIn(duration: 0.2), value: hasLoaded)
        }
        .task {
            guard let db = appDatabase, let artistId = artist.id else { return }
            // Use cached data for instant display, fall back to DB read
            let initial: ArtistDetailData
            if let cached = _artistDetailCache[artistId] {
                initial = cached
                hasLoaded = true
            } else {
                do {
                    initial = try db.pool.read { db in
                        let trackSql = """
                            SELECT track.*, artist.name AS artistName, album.name AS albumName
                            FROM track
                            LEFT JOIN artist ON track.artistId = artist.id
                            LEFT JOIN album ON track.albumId = album.id
                            WHERE track.artistId = ?
                            ORDER BY track.title
                            """
                        let tracks = try TrackInfo.fetchAll(db, sql: trackSql, arguments: [artistId])
                        let albumSql = """
                            SELECT album.id, album.name, album.artistName, album.year, album.artistId,
                                COUNT(track.id) AS trackCount
                            FROM album
                            LEFT JOIN track ON track.albumId = album.id
                            WHERE album.artistId = ?
                            GROUP BY album.id
                            ORDER BY album.year DESC, album.name
                            """
                        let albums = try AlbumInfo.fetchAll(db, sql: albumSql, arguments: [artistId])
                        return ArtistDetailData(allTracks: tracks, albums: albums)
                    }
                } catch {
                    initial = ArtistDetailData(allTracks: [], albums: [])
                }
            }
            observer = DatabaseObserver(
                initial: initial,
                in: db.pool,
                observation: makeObservation(artistId: artistId)
            )
            hasLoaded = true
        }
        .onChange(of: observer?.value.allTracks.count) {
            guard let artistId = artist.id, let data = observer?.value else { return }
            _artistDetailCache[artistId] = data
        }
        .onChange(of: observer?.value.albums.count) {
            guard let artistId = artist.id, let data = observer?.value else { return }
            _artistDetailCache[artistId] = data
        }
        .onReceive(NotificationCenter.default.publisher(for: .highlightTrackInDetail)) { notification in
            guard let trackID = notification.userInfo?["trackID"] as? Int64 else { return }
            guard allTracks.contains(where: { $0.id == trackID }) else { return }
            selectedTrackID = trackID
            selectedAlbumID = nil
            withAnimation {
                proxy.scrollTo(trackID, anchor: .center)
            }
        }
        } // ScrollViewReader
    }

    private func makeObservation(artistId: Int64) -> ValueObservation<ValueReducers.Fetch<ArtistDetailData>> {
        ValueObservation.tracking { db in
            let trackSql = """
                SELECT
                    track.*,
                    artist.name AS artistName,
                    album.name AS albumName
                FROM track
                LEFT JOIN artist ON track.artistId = artist.id
                LEFT JOIN album ON track.albumId = album.id
                WHERE track.artistId = ?
                ORDER BY track.title
                """
            let tracks = try TrackInfo.fetchAll(db, sql: trackSql, arguments: [artistId])

            let albumSql = """
                SELECT
                    album.id, album.name, album.artistName, album.year, album.artistId,
                    COUNT(track.id) AS trackCount
                FROM album
                LEFT JOIN track ON track.albumId = album.id
                WHERE album.artistId = ?
                GROUP BY album.id
                ORDER BY album.year DESC, album.name
                """
            let albums = try AlbumInfo.fetchAll(db, sql: albumSql, arguments: [artistId])

            return ArtistDetailData(allTracks: tracks, albums: albums)
        }
    }

    private func loadArtwork() {
        guard let artistId = artist.id, let db = appDatabase,
              let data = try? db.artwork.fetchImageData(ownerType: "artist", ownerId: artistId),
              let img = NSImage(data: data) else {
            artworkImage = nil
            return
        }
        artworkImage = img
    }

    private func removeTrack(_ track: TrackInfo) {
        guard let db = appDatabase else { return }
        do {
            try db.tracks.delete(id: track.id)
            try db.albums.deleteOrphaned()
            try db.artists.deleteOrphaned()
        } catch {
            Log.database.error("Failed to remove track \(track.id): \(error)")
        }
    }

    private func removeAlbum(_ albumInfo: AlbumInfo) {
        guard let db = appDatabase else { return }
        let albumTracks = (try? db.tracks.fetchInfoByAlbum(id: albumInfo.id)) ?? []
        do {
            for track in albumTracks {
                try db.tracks.delete(id: track.id)
            }
            try db.albums.delete(id: albumInfo.id)
            try db.artists.deleteOrphaned()
        } catch {
            Log.database.error("Failed to remove album \(albumInfo.id): \(error)")
        }
    }

    private func chooseArtistArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose artwork for \"\(artist.name)\""
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url) {
            guard let artistId = artist.id, let db = appDatabase else { return }
            do { try db.artwork.upsert(ownerType: "artist", ownerId: artistId, imageData: data, thumbnailData: nil) } catch { Log.database.error("Failed to upsert artist artwork \(artistId): \(error)") }
            artworkImage = NSImage(data: data)
        }
    }
}

// MARK: - Artist Track Row

private func formatTime(_ seconds: Double) -> String {
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%d:%02d", mins, secs)
}

// MARK: - Artist Album Card

private struct ArtistAlbumCard: View {
    let albumInfo: AlbumInfo
    let artistName: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onNavigate: () -> Void
    let onRemove: () -> Void

    @Environment(ArtworkService.self) private var artworkService
    @Environment(\.appDatabase) private var appDatabase
    @State private var isFetching = false
    @State private var showEditSheet = false
    @State private var artwork: NSImage?

    var body: some View {
        Button {
            let now = Date()
            if now.timeIntervalSince(_albumCardLastClickTime) < NSEvent.doubleClickInterval {
                _albumCardLastClickTime = .distantPast
                onNavigate()
            } else {
                _albumCardLastClickTime = now
                onSelect()
            }
        } label: {
            AlbumCard(
                name: albumInfo.name,
                artist: artistName,
                artwork: artwork,
                isLoading: isFetching
            )
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .task {
            loadArtwork()
            guard artwork == nil, let db = appDatabase else { return }
            isFetching = true
            let _ = await artworkService.fetchAlbumArtwork(
                albumId: albumInfo.id,
                albumName: albumInfo.name,
                artistName: albumInfo.artistName,
                db: db
            )
            loadArtwork()
            isFetching = false
        }
        .contextMenu {
            Button {
                Task {
                    guard let db = appDatabase else { return }
                    artwork = nil
                    isFetching = true
                    let _ = await artworkService.fetchAlbumArtwork(
                        albumId: albumInfo.id,
                        albumName: albumInfo.name,
                        artistName: albumInfo.artistName,
                        db: db,
                        force: true
                    )
                    loadArtwork()
                    isFetching = false
                }
            } label: { Label("Find Artwork", systemImage: "photo") }
            Button { chooseArtworkFile() } label: { Label("Choose Artwork...", systemImage: "folder") }
            AddToPlaylistMenu(tracks: albumTracks())
            LikeDislikeMenu(tracks: albumTracks())
            Divider()
            Button { showEditSheet = true } label: { Label("Edit Album...", systemImage: "pencil") }
            Divider()
            Button(role: .destructive) { onRemove() } label: { Label("Remove Album from Library", systemImage: "trash") }
        }
        .sheet(isPresented: $showEditSheet) {
            EditAlbumSheet(album: AlbumRecord(
                id: albumInfo.id,
                name: albumInfo.name,
                artistName: albumInfo.artistName,
                year: albumInfo.year,
                artistId: albumInfo.artistId
            ))
        }
    }

    private func loadArtwork() {
        guard let db = appDatabase,
              let data = try? db.artwork.fetchImageData(ownerType: "album", ownerId: albumInfo.id),
              let img = NSImage(data: data) else {
            artwork = nil
            return
        }
        artwork = img
    }

    private func albumTracks() -> [TrackInfo] {
        (try? appDatabase?.tracks.fetchInfoByAlbum(id: albumInfo.id)) ?? []
    }

    private func chooseArtworkFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose artwork for \"\(albumInfo.name)\""
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url) {
            guard let db = appDatabase else { return }
            do { try db.artwork.upsert(ownerType: "album", ownerId: albumInfo.id, imageData: data, thumbnailData: nil) } catch { Log.database.error("Failed to upsert album artwork \(albumInfo.id): \(error)") }
            artwork = NSImage(data: data)
        }
    }
}

// MARK: - Artist Track Row

private struct ArtistTrackRow: View {
    let track: TrackInfo
    let index: Int
    let isSelected: Bool
    let allTracks: [TrackInfo]
    let onSelect: () -> Void
    let onPlay: (TrackInfo, [TrackInfo], Int) -> Void
    let onPlayNext: (TrackInfo) -> Void
    let onPlayLater: (TrackInfo) -> Void
    let onRemove: (TrackInfo) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text("\(track.trackNumber)")
                .font(.app(size: 12))
                .foregroundStyle(.tertiary)
                .frame(width: 30, alignment: .trailing)
                .padding(.trailing, 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.app(size: 13))
                    .lineLimit(1)
                Text(track.albumName ?? "")
                    .font(.app(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if track.likedStatus == 1 {
                Image(systemName: "heart.fill")
                    .font(.app(size: 10))
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 12)

            Text(formatTime(track.duration))
                .font(.app(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .opacity(track.likedStatus == -1 ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .onClicks(single: {
            onSelect()
        }, double: {
            onPlay(track, allTracks, index)
        })
        .contextMenu {
            Button { onPlay(track, allTracks, index) } label: { Label("Play", systemImage: "play") }
            Button { onPlayNext(track) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button { onPlayLater(track) } label: { Label("Play Later", systemImage: "text.line.last.and.arrowtriangle.forward") }
            AddToPlaylistMenu(tracks: [track])
            LikeDislikeMenu(tracks: [track])
            Divider()
            if let albumId = track.albumId {
                Button {
                    NotificationCenter.default.post(name: .navigateToAlbum, object: nil, userInfo: ["albumId": albumId])
                } label: { Label("Go to Album", systemImage: "square.stack") }
            }
            Divider()
            Button(role: .destructive) { onRemove(track) } label: { Label("Remove from Library", systemImage: "trash") }
        }
    }
}
