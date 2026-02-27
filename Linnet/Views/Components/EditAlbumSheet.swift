import SwiftUI
import LinnetLibrary
import UniformTypeIdentifiers

struct EditAlbumSheet: View {
    let album: AlbumRecord
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appDatabase) private var appDatabase
    @State private var name: String = ""
    @State private var artistName: String = ""
    @State private var yearText: String = ""
    @State private var artworkImage: NSImage?
    @State private var newArtworkData: Data?

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Album")
                .font(.headline)

            HStack(alignment: .top, spacing: 16) {
                // Artwork
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .frame(width: 120, height: 120)
                        .overlay {
                            if let img = artworkImage {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: "music.note")
                                    .font(.app(size: 30))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onDrop(of: [.image], isTargeted: nil) { providers in
                            handleDrop(providers)
                            return true
                        }

                    HStack(spacing: 8) {
                        Button("Choose...") { chooseArtwork() }
                            .controlSize(.small)
                        if artworkImage != nil {
                            Button("Remove") {
                                artworkImage = nil
                                newArtworkData = Data()
                            }
                            .controlSize(.small)
                        }
                    }
                }

                // Fields
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Name") {
                        TextField("Album name", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Artist") {
                        TextField("Artist name", text: $artistName)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Year") {
                        TextField("Year", text: $yearText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            name = album.name
            artistName = album.artistName ?? ""
            yearText = album.year.map { "\($0)" } ?? ""
            if let albumId = album.id, let db = appDatabase,
               let data = try? db.artwork.fetchImageData(ownerType: "album", ownerId: albumId),
               let img = NSImage(data: data) {
                artworkImage = img
            }
        }
    }

    private func save() {
        guard let db = appDatabase, let albumId = album.id else { return }
        var updated = album
        updated.name = name
        updated.artistName = artistName.isEmpty ? nil : artistName
        updated.year = Int(yearText)
        try? db.albums.update(updated)

        if let data = newArtworkData {
            if data.isEmpty {
                try? db.artwork.delete(ownerType: "album", ownerId: albumId)
            } else {
                try? db.artwork.upsert(ownerType: "album", ownerId: albumId, imageData: data, thumbnailData: nil)
            }
        }

        dismiss()
    }

    private func chooseArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url),
           let img = NSImage(data: data) {
            artworkImage = img
            newArtworkData = data
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data, let img = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                artworkImage = img
                newArtworkData = data
            }
        }
    }
}
