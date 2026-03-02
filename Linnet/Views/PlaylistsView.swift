import SwiftUI
import LinnetLibrary
import GRDB

private struct PlaylistWithCount: Sendable {
    let playlist: PlaylistRecord
    let songCount: Int
}

struct PlaylistsView: View {
    @Environment(\.appDatabase) private var appDatabase
    @Environment(\.navigationPath) private var navigationPath
    @State private var observer: DatabaseObserver<[PlaylistWithCount]>?
    @State private var selectedPlaylistID: Int64?
    @AppStorage("playlistSortOption") private var sortOption: PlaylistSortOption = .dateCreated
    @AppStorage("playlistSortDirection") private var sortDirection: SortDirection = .ascending
    @State private var searchText = ""
    @State private var isSearchPresented = false

    private var playlists: [PlaylistRecord] {
        (observer?.value ?? []).map(\.playlist)
    }

    private var entryCounts: [Int64: Int] {
        var counts: [Int64: Int] = [:]
        for item in observer?.value ?? [] {
            if let id = item.playlist.id {
                counts[id] = item.songCount
            }
        }
        return counts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Playlists")
                    .font(.largeTitle.bold())
                Spacer()
                SortFilterMenuButton(sortOption: $sortOption, sortDirection: $sortDirection)

                Button(action: createPlaylist) {
                    Label("New Playlist", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding(20)

            if playlists.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Playlists" : "No Results",
                    systemImage: searchText.isEmpty ? "music.note.list" : "magnifyingglass",
                    description: Text(searchText.isEmpty
                        ? "Create a playlist to get started."
                        : "No playlists matching \"\(searchText)\"")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(playlists, id: \.id, selection: $selectedPlaylistID) { playlist in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.quaternary)
                            .frame(width: 40, height: 40)
                            .overlay {
                                Image(systemName: playlist.isAIGenerated ? "sparkles" : "music.note.list")
                                    .foregroundStyle(.secondary)
                            }

                        VStack(alignment: .leading) {
                            Text(playlist.name)
                                .font(.app(size: 14))
                            Text("\(entryCounts[playlist.id!] ?? 0) songs")
                                .font(.app(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button(role: .destructive) { deletePlaylist(playlist) } label: { Label("Delete Playlist", systemImage: "trash") }
                    }
                }
                .contextMenu(forSelectionType: Int64.self, menu: { _ in }, primaryAction: { identifiers in
                    guard let id = identifiers.first else { return }
                    navigationPath.wrappedValue.append(id)
                })
            }
        }
        .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search playlists...")
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            isSearchPresented = true
        }
        .task {
            guard let db = appDatabase else { return }
            observer = DatabaseObserver(
                initial: [],
                in: db.pool,
                observation: makeObservation()
            )
        }
        .onChange(of: searchText) { _, _ in reobserve() }
        .onChange(of: sortOption) { _, _ in reobserve() }
        .onChange(of: sortDirection) { _, _ in reobserve() }
    }

    private func makeObservation() -> ValueObservation<ValueReducers.Fetch<[PlaylistWithCount]>> {
        let ordering = sortOption.sqlColumn
        let dir = sortDirection.sql
        let search = searchText
        return ValueObservation.tracking { db in
            if search.isEmpty {
                let sql = """
                    SELECT
                        playlist.*,
                        COUNT(playlistEntry.id) AS songCount
                    FROM playlist
                    LEFT JOIN playlistEntry ON playlistEntry.playlistId = playlist.id
                    GROUP BY playlist.id
                    ORDER BY \(ordering) \(dir)
                    """
                let rows = try Row.fetchAll(db, sql: sql)
                return rows.map { row in
                    let record = PlaylistRecord(
                        id: row["id"],
                        name: row["name"],
                        isAIGenerated: row["isAIGenerated"],
                        createdAt: row["createdAt"]
                    )
                    let count: Int = row["songCount"]
                    return PlaylistWithCount(playlist: record, songCount: count)
                }
            } else {
                let pattern = "%\(search)%"
                let sql = """
                    SELECT
                        playlist.*,
                        COUNT(playlistEntry.id) AS songCount
                    FROM playlist
                    LEFT JOIN playlistEntry ON playlistEntry.playlistId = playlist.id
                    WHERE playlist.name LIKE ?
                    GROUP BY playlist.id
                    ORDER BY playlist.createdAt
                    """
                let rows = try Row.fetchAll(db, sql: sql, arguments: [pattern])
                return rows.map { row in
                    let record = PlaylistRecord(
                        id: row["id"],
                        name: row["name"],
                        isAIGenerated: row["isAIGenerated"],
                        createdAt: row["createdAt"]
                    )
                    let count: Int = row["songCount"]
                    return PlaylistWithCount(playlist: record, songCount: count)
                }
            }
        }
    }

    private func reobserve() {
        guard let db = appDatabase else { return }
        observer?.reobserve(in: db.pool, observation: makeObservation())
    }

    private func createPlaylist() {
        var playlist = PlaylistRecord(name: "New Playlist")
        do { try appDatabase?.playlists.insert(&playlist) } catch { Log.database.error("Failed to create playlist: \(error)") }
    }

    private func deletePlaylist(_ playlist: PlaylistRecord) {
        guard let id = playlist.id else { return }
        do { try appDatabase?.playlists.delete(id: id) } catch { Log.database.error("Failed to delete playlist \(id): \(error)") }
    }
}
