import SwiftUI
import SwiftData
import LinnetLibrary

struct PlaylistsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Playlist.createdAt) private var playlists: [Playlist]

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

            if playlists.isEmpty {
                ContentUnavailableView("No Playlists", systemImage: "music.note.list", description: Text("Create a playlist to get started."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(playlists) { playlist in
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
    }

    private func createPlaylist() {
        let playlist = Playlist(name: "New Playlist")
        modelContext.insert(playlist)
        try? modelContext.save()
    }
}
