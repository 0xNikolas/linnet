import SwiftUI
import AppKit
import LinnetLibrary

struct NewPlaylistSheet: View {
    let tracks: [TrackInfo]
    @Environment(\.appDatabase) private var appDatabase
    @Environment(\.dismiss) private var dismiss
    @State private var playlistName: String = ""
    @State private var playlistDescription: String = ""
    @State private var coverImage: NSImage?
    @State private var coverData: Data?
    @FocusState private var nameFieldFocused: Bool

    private var canCreate: Bool {
        !playlistName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("New Playlist")
                .font(.app(size: 15, weight: .semibold))

            // Artwork well with the red "+" picker.
            Button(action: chooseCover) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary)
                    .frame(width: 150, height: 150)
                    .overlay {
                        if let coverImage {
                            Image(nsImage: coverImage)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.accentColor))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .help("Choose a cover image")

            VStack(spacing: 10) {
                TextField("Playlist Title", text: $playlistName)
                    .textFieldStyle(.roundedBorder)
                    .font(.app(size: 14))
                    .focused($nameFieldFocused)
                    .onSubmit { if canCreate { create() } }

                TextField("Description (Optional)", text: $playlistDescription, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.app(size: 13))
                    .lineLimit(2...4)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCreate)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear {
            playlistName = suggestedName()
            nameFieldFocused = true
        }
    }

    private func chooseCover() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a cover image"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        coverData = data
        coverImage = NSImage(data: data)
    }

    private func suggestedName() -> String {
        let artists = Set(tracks.compactMap { $0.artistName })
        let albums = Set(tracks.compactMap { $0.albumName })
        if artists.count == 1, let artist = artists.first {
            return "Best of \(artist)"
        } else if albums.count == 1, let album = albums.first {
            return "\(album) Selection"
        }
        return tracks.isEmpty ? "" : "New Playlist"
    }

    private func create() {
        guard canCreate, let db = appDatabase else { return }
        let name = playlistName.trimmingCharacters(in: .whitespaces)
        let description = playlistDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        var playlist = PlaylistRecord(name: name, description: description.isEmpty ? nil : description)
        do {
            try db.playlists.insert(&playlist)
            if let playlistId = playlist.id {
                if let coverData {
                    try db.artwork.upsert(ownerType: "playlist", ownerId: playlistId, imageData: coverData, thumbnailData: nil)
                }
                let trackIds = tracks.compactMap { $0.id as Int64? }
                if !trackIds.isEmpty {
                    try db.playlists.addTracks(trackIds: trackIds, toPlaylist: playlistId)
                }
            }
        } catch {
            Log.database.error("Failed to create playlist '\(name)': \(error)")
        }
        dismiss()
    }
}
