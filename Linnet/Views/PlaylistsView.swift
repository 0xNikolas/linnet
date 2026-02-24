import SwiftUI
import SwiftData
import LinnetLibrary

struct PlaylistsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Playlist.createdAt) private var playlists: [Playlist]
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
                List(filteredPlaylists) { playlist in
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
                                .font(.system(size: 14))
                            Text("\(playlist.entries.count) songs")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
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
}
