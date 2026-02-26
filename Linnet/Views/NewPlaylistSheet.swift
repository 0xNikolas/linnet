import SwiftUI
import SwiftData
import LinnetLibrary

struct NewPlaylistSheet: View {
    let tracks: [Track]
    @Environment(\.modelContext) private var modelContext
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

                    List(tracks) { track in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(track.title)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                Text(track.artist?.name ?? "Unknown Artist")
                                    .font(.system(size: 11))
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
        let artists = Set(tracks.compactMap { $0.artist?.name })
        let albums = Set(tracks.compactMap { $0.album?.name })

        if artists.count == 1, let artist = artists.first {
            return "Best of \(artist)"
        } else if albums.count == 1, let album = albums.first {
            return "\(album) Selection"
        }
        return "New Playlist"
    }

    private func createPlaylist() {
        let name = playlistName.trimmingCharacters(in: .whitespaces)
        let playlist = Playlist(name: name)
        modelContext.insert(playlist)

        for (i, track) in tracks.enumerated() {
            let entry = PlaylistEntry(track: track, order: i)
            entry.playlist = playlist
            playlist.entries.append(entry)
            modelContext.insert(entry)
        }
        try? modelContext.save()
    }
}
