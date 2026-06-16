import SwiftUI
import LinnetLibrary
import GRDB
import UniformTypeIdentifiers

struct AlbumDetailView: View {
    let album: AlbumRecord
    @Environment(PlayerViewModel.self) private var player
    @Environment(ArtworkService.self) private var artworkService
    @Environment(\.appDatabase) private var appDatabase
    @State private var isFetchingArtwork = false

    @State private var showEditSheet = false
    @State private var artworkImage: NSImage?
    @State private var query: CachedQuery<[TrackInfo]>

    init(album: AlbumRecord) {
        self.album = album
        _query = State(initialValue: CachedQuery(cacheKey: "albumDetail-\(album.id ?? -1)", default: []))
    }

    private var tracks: [TrackInfo] { query.value }

    private var sortedTracks: [TrackInfo] {
        tracks.sorted {
            ($0.discNumber, $0.trackNumber) < ($1.discNumber, $1.trackNumber)
        }
    }

    private var metadataLine: String {
        var parts: [String] = []
        if let year = album.year { parts.append(String(year)) }
        parts.append("\(sortedTracks.count) " + (sortedTracks.count == 1 ? "song" : "songs"))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(
                artwork: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
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
                            Button("Choose Artwork...") { chooseArtworkFile() }
                            Divider()
                            Button("Edit Album...") { showEditSheet = true }
                        }
                },
                title: album.name,
                subtitle: {
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
                            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                    } else {
                        Text(album.artistName ?? "Unknown Artist")
                            .font(.app(size: 18))
                            .foregroundStyle(.secondary)
                    }
                },
                metadata: metadataLine,
                playDisabled: sortedTracks.isEmpty,
                onPlay: {
                    if let first = sortedTracks.first {
                        player.playTrack(first, queue: sortedTracks, startingAt: 0)
                    }
                },
                onShuffle: {
                    let shuffled = sortedTracks.shuffled()
                    if let first = shuffled.first {
                        player.playTrack(first, queue: shuffled, startingAt: 0)
                    }
                }
            )

            Divider()

            SongsListView(tracks: sortedTracks, initialSortOrder: [], highlightedTrackID: .constant(nil))

            TrackListFooter(tracks: sortedTracks)
        }
        .task {
            guard let db = appDatabase, let albumId = album.id else { return }
            query.activate(
                in: db.pool,
                seed: { db in
                    try TrackInfo.fetchAll(db, sql: TrackInfo.baseSQL + """
                         WHERE track.albumId = ?
                        ORDER BY track.discNumber, track.trackNumber
                        """, arguments: [albumId])
                },
                observation: makeObservation(albumId: albumId)
            )
        }
        .onChange(of: tracks) { query.persist() }
        .sheet(isPresented: $showEditSheet) {
            EditAlbumSheet(album: album)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    NotificationCenter.default.post(name: .toggleQueueSidePane, object: nil)
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
            }
        }
    }

    private func makeObservation(albumId: Int64) -> ValueObservation<ValueReducers.Fetch<[TrackInfo]>> {
        ValueObservation.tracking { db in
            let sql = """
                SELECT
                    track.*,
                    artist.name AS artistName,
                    album.name AS albumName
                FROM track
                LEFT JOIN artist ON track.artistId = artist.id
                LEFT JOIN album ON track.albumId = album.id
                WHERE track.albumId = ?
                ORDER BY track.discNumber, track.trackNumber
                """
            return try TrackInfo.fetchAll(db, sql: sql, arguments: [albumId])
        }
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
            do { try db.artwork.upsert(ownerType: "album", ownerId: albumId, imageData: data, thumbnailData: nil) } catch { Log.database.error("Failed to upsert album artwork \(albumId): \(error)") }
            artworkImage = NSImage(data: data)
        }
    }

}
