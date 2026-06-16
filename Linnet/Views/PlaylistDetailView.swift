import SwiftUI
import LinnetLibrary
import GRDB

private struct PlaylistDetailData: Sendable {
    let playlist: PlaylistRecord?
    let tracks: [TrackInfo]
}

struct PlaylistDetailView: View {
    let playlistID: Int64
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.appDatabase) private var appDatabase
    @State private var observer: DatabaseObserver<PlaylistDetailData>?
    @State private var coverImage: NSImage?

    private var playlist: PlaylistRecord? { observer?.value.playlist }
    private var tracks: [TrackInfo] { observer?.value.tracks ?? [] }

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
            guard let db = appDatabase else { return }
            let pid = playlistID
            let initial: PlaylistDetailData = ViewDataCache.value(forKey: "playlistDetail-\(pid)") ?? (
                (try? db.pool.read { db in
                    let playlist = try PlaylistRecord.fetchOne(db, id: pid)
                    let sql = """
                        SELECT
                            track.*,
                            artist.name AS artistName,
                            album.name AS albumName
                        FROM playlistEntry
                        JOIN track ON playlistEntry.trackId = track.id
                        LEFT JOIN artist ON track.artistId = artist.id
                        LEFT JOIN album ON track.albumId = album.id
                        WHERE playlistEntry.playlistId = ?
                        ORDER BY playlistEntry."order"
                        """
                    let tracks = try TrackInfo.fetchAll(db, sql: sql, arguments: [pid])
                    return PlaylistDetailData(playlist: playlist, tracks: tracks)
                }) ?? PlaylistDetailData(playlist: nil, tracks: [])
            )
            observer = DatabaseObserver(
                initial: initial,
                in: db.pool,
                observation: makeObservation()
            )
            if let name = observer?.value.playlist?.name {
                NotificationCenter.default.post(
                    name: .registerBreadcrumb,
                    object: nil,
                    userInfo: ["title": name]
                )
            }
        }
        .onChange(of: tracks.count) {
            if let value = observer?.value {
                ViewDataCache.store(value, forKey: "playlistDetail-\(playlistID)")
            }
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

    @ViewBuilder
    private func playlistContent(_ playlist: PlaylistRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(
                artwork: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .overlay {
                            if let coverImage {
                                Image(nsImage: coverImage)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: playlist.isAIGenerated ? "sparkles" : "music.note.list")
                                    .font(.app(size: 40))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .task(id: playlistID) { loadCover() }
                },
                title: playlist.name,
                subtitle: {
                    if let desc = playlist.description, !desc.isEmpty {
                        Text(desc)
                            .font(.app(size: 14))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                },
                metadata: "\(tracks.count) " + (tracks.count == 1 ? "song" : "songs"),
                playDisabled: tracks.isEmpty,
                onPlay: {
                    guard let first = tracks.first else { return }
                    player.playTrack(first, queue: tracks, startingAt: 0)
                },
                onShuffle: {
                    let shuffled = tracks.shuffled()
                    guard let first = shuffled.first else { return }
                    player.playTrack(first, queue: shuffled, startingAt: 0)
                }
            )

            Divider()

            if tracks.isEmpty {
                ContentUnavailableView(
                    "No Tracks",
                    systemImage: "music.note",
                    description: Text("Add songs to this playlist from their context menu.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SongsListView(
                    tracks: tracks,
                    initialSortOrder: [],
                    removeLabel: "Remove from Playlist",
                    removeIcon: "minus.circle",
                    onRemove: { removeSelectedTracks($0) },
                    highlightedTrackID: .constant(nil)
                )
                TrackListFooter(tracks: tracks)
            }
        }
    }

    private func loadCover() {
        guard let db = appDatabase,
              let data = try? db.artwork.fetchImageData(ownerType: "playlist", ownerId: playlistID),
              let img = NSImage(data: data) else {
            coverImage = nil
            return
        }
        coverImage = img
    }

    private func makeObservation() -> ValueObservation<ValueReducers.Fetch<PlaylistDetailData>> {
        let pid = playlistID
        return ValueObservation.tracking { db in
            let playlist = try PlaylistRecord.fetchOne(db, id: pid)
            let sql = """
                SELECT
                    track.*,
                    artist.name AS artistName,
                    album.name AS albumName
                FROM playlistEntry
                JOIN track ON playlistEntry.trackId = track.id
                LEFT JOIN artist ON track.artistId = artist.id
                LEFT JOIN album ON track.albumId = album.id
                WHERE playlistEntry.playlistId = ?
                ORDER BY playlistEntry."order"
                """
            let tracks = try TrackInfo.fetchAll(db, sql: sql, arguments: [pid])
            return PlaylistDetailData(playlist: playlist, tracks: tracks)
        }
    }

    private func removeSelectedTracks(_ ids: Set<Int64>) {
        do { try appDatabase?.playlists.removeEntries(trackIds: ids, fromPlaylist: playlistID) } catch { Log.database.error("Failed to remove playlist entries: \(error)") }
    }
}
