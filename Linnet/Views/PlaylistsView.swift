import SwiftUI
import LinnetLibrary

struct PlaylistsView: View {
    @Environment(\.appDatabase) private var appDatabase
    @Environment(\.navigationPath) private var navigationPath
    @State private var playlists: [PlaylistRecord] = []
    @State private var entryCounts: [Int64: Int] = [:]
    @State private var selectedPlaylistID: Int64?
    @AppStorage("playlistSortOption") private var sortOption: PlaylistSortOption = .dateCreated
    @AppStorage("playlistSortDirection") private var sortDirection: SortDirection = .ascending
    @State private var searchText = ""
    @State private var isSearchPresented = false

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
        .task { loadPlaylists() }
        .onChange(of: searchText) { _, _ in loadPlaylists() }
        .onChange(of: sortOption) { _, _ in loadPlaylists() }
        .onChange(of: sortDirection) { _, _ in loadPlaylists() }
    }

    private func loadPlaylists() {
        guard let db = appDatabase else { return }
        if searchText.isEmpty {
            let results = (try? db.playlists.fetchAllSorted(orderedBy: sortOption.sqlColumn, direction: sortDirection.sql)) ?? []
            playlists = results.map(\.playlist)
            var counts: [Int64: Int] = [:]
            for result in results {
                if let id = result.playlist.id {
                    counts[id] = result.songCount
                }
            }
            entryCounts = counts
        } else {
            playlists = (try? db.playlists.search(query: searchText)) ?? []
            var counts: [Int64: Int] = [:]
            for playlist in playlists {
                if let id = playlist.id {
                    counts[id] = (try? db.playlists.entryCount(playlistId: id)) ?? 0
                }
            }
            entryCounts = counts
        }
    }

    private func createPlaylist() {
        var playlist = PlaylistRecord(name: "New Playlist")
        _ = try? appDatabase?.playlists.insert(&playlist)
        loadPlaylists()
    }

    private func deletePlaylist(_ playlist: PlaylistRecord) {
        guard let id = playlist.id else { return }
        try? appDatabase?.playlists.delete(id: id)
        loadPlaylists()
    }
}
