import SwiftUI
import SwiftData
import LinnetLibrary

struct AddToPlaylistMenu: View {
    let tracks: [Track]

    @Query(sort: \Playlist.name) private var playlists: [Playlist]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Menu("Add to Playlist") {
            ForEach(playlists) { playlist in
                Button(playlist.name) {
                    addTracks(to: playlist)
                }
            }
            if !playlists.isEmpty { Divider() }
            Button("New Playlist...") {
                let playlist = Playlist(name: "New Playlist")
                modelContext.insert(playlist)
                addTracks(to: playlist)
                try? modelContext.save()
            }
        }
    }

    private func addTracks(to playlist: Playlist) {
        let startOrder = playlist.entries.count
        for (i, track) in tracks.enumerated() {
            let entry = PlaylistEntry(track: track, order: startOrder + i)
            entry.playlist = playlist
            playlist.entries.append(entry)
            modelContext.insert(entry)
        }
        try? modelContext.save()
    }
}
