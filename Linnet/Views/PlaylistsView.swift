import SwiftUI
import SwiftData
import LinnetLibrary

struct PlaylistsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.navigationPath) private var navigationPath
    @Query(sort: \Playlist.createdAt) private var playlists: [Playlist]
    @State private var selectedPlaylistID: PersistentIdentifier?
    @State private var searchText = ""
    @State private var isSearchPresented = false

    private var filteredPlaylists: [Playlist] {
        if searchText.isEmpty { return playlists }
        let query = searchText
        return playlists.filter { $0.name.searchContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Playlists")
                    .font(.largeTitle.bold())
                Spacer()
                Button(action: createPlaylist) {
                    Label("New Playlist", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding(20)

            if filteredPlaylists.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Playlists" : "No Results",
                    systemImage: searchText.isEmpty ? "music.note.list" : "magnifyingglass",
                    description: Text(searchText.isEmpty
                        ? "Create a playlist to get started."
                        : "No playlists matching \"\(searchText)\"")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredPlaylists, id: \.persistentModelID, selection: $selectedPlaylistID) { playlist in
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
                            Text("\(playlist.entries.count) songs")
                                .font(.app(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button("Delete Playlist", role: .destructive) {
                            deletePlaylist(playlist)
                        }
                    }
                }
                .contextMenu(forSelectionType: PersistentIdentifier.self, menu: { _ in }, primaryAction: { identifiers in
                    guard let id = identifiers.first else { return }
                    navigationPath.wrappedValue.append(id)
                })
            }
        }
        .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search playlists...")
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            isSearchPresented = true
        }
    }

    private func createPlaylist() {
        let playlist = Playlist(name: "New Playlist")
        modelContext.insert(playlist)
        try? modelContext.save()
    }

    private func deletePlaylist(_ playlist: Playlist) {
        modelContext.delete(playlist)
        try? modelContext.save()
    }
}
