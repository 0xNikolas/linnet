import SwiftUI
import LinnetLibrary

struct NewPlaylistSheet: View {
    let tracks: [TrackInfo]
    @Environment(\.appDatabase) private var appDatabase
    @Environment(\.dismiss) private var dismiss
    @State private var playlistName: String = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Playlist")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Playlist name", text: $playlistName)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFieldFocused)
            }
            .padding()

            Divider()

            if !tracks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(tracks.count) songs")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    List(tracks, id: \.id) { track in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(track.title)
                                    .font(.app(size: 13))
                                    .lineLimit(1)
                                Text(track.artistName ?? "Unknown Artist")
                                    .font(.app(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                    }
                    .listStyle(.plain)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Create Playlist") {
                    createPlaylist()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(playlistName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 450)
        .onAppear {
            playlistName = suggestedName()
            nameFieldFocused = true
        }
    }

    private func suggestedName() -> String {
        let artists = Set(tracks.compactMap { $0.artistName })
        let albums = Set(tracks.compactMap { $0.albumName })

        if artists.count == 1, let artist = artists.first {
            return "Best of \(artist)"
        } else if albums.count == 1, let album = albums.first {
            return "\(album) Selection"
        }
        return "New Playlist"
    }

    private func createPlaylist() {
        guard let db = appDatabase else { return }
        let name = playlistName.trimmingCharacters(in: .whitespaces)
        var playlist = PlaylistRecord(name: name)
        try? db.playlists.insert(&playlist)

        if let playlistId = playlist.id {
            let trackIds = tracks.compactMap { $0.id as Int64? }
            try? db.playlists.addTracks(trackIds: trackIds, toPlaylist: playlistId)
        }
    }
}
