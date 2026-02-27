import SwiftUI
import LinnetLibrary

struct AddToPlaylistMenu: View {
    let tracks: [TrackInfo]

    @Environment(\.appDatabase) private var appDatabase
    @State private var showNewPlaylistSheet = false

    private var playlists: [PlaylistRecord] {
        (try? appDatabase?.playlists.fetchAll()) ?? []
    }

    var body: some View {
        Menu {
            ForEach(playlists, id: \.id) { playlist in
                Button(playlist.name) {
                    addTracks(to: playlist)
                }
            }
            if !playlists.isEmpty { Divider() }
            Button("New Playlist...") {
                showNewPlaylistSheet = true
            }
        } label: {
            Label("Add to Playlist", systemImage: "text.badge.plus")
        }
        .background {
            Color.clear
                .sheet(isPresented: $showNewPlaylistSheet) {
                    NewPlaylistSheet(tracks: tracks)
                }
        }
    }

    private func addTracks(to playlist: PlaylistRecord) {
        guard let db = appDatabase, let playlistId = playlist.id else { return }
        let trackIds = tracks.map(\.id)
        try? db.playlists.addTracks(trackIds: trackIds, toPlaylist: playlistId)
    }
}
