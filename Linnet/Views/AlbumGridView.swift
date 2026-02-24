import SwiftUI
import SwiftData
import LinnetLibrary

struct AlbumGridView: View {
    @Query(sort: \Album.name) private var albums: [Album]
    @Environment(\.modelContext) private var modelContext
    @Environment(ArtworkService.self) private var artworkService
    @Environment(\.navigationPath) private var navigationPath
    @State private var selectedAlbumID: PersistentIdentifier?
    @State private var searchText = ""
    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)]

    private var filteredAlbums: [Album] {
        if searchText.isEmpty { return albums }
        let query = searchText
        return albums.filter { album in
            album.name.localizedCaseInsensitiveContains(query) ||
            (album.artistName ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            if filteredAlbums.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Albums" : "No Results",
                    systemImage: searchText.isEmpty ? "square.stack" : "magnifyingglass",
                    description: Text(searchText.isEmpty
                        ? "Add a music folder in Settings to get started."
                        : "No albums matching \"\(searchText)\"")
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(filteredAlbums) { album in
                        AlbumCard(
                            name: album.name,
                            artist: album.artistName ?? "Unknown Artist",
                            artwork: album.artworkData.flatMap { NSImage(data: $0) }
                        )
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedAlbumID == album.persistentModelID
                                      ? Color.accentColor.opacity(0.15)
                                      : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedAlbumID = album.persistentModelID
                        }
                        .onDoubleClick {
                            navigationPath.wrappedValue.append(album)
                        }
                        .task {
                            guard album.artworkData == nil else { return }
                            await artworkService.fetchAlbumArtwork(for: album, context: modelContext)
                        }
                        .contextMenu {
                            Button("Find Artwork") {
                                Task {
                                    await artworkService.fetchAlbumArtwork(for: album, context: modelContext)
                                }
                            }
                            Divider()
                            Button("Remove from Library", role: .destructive) {
                                removeAlbum(album)
                            }
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 60)
                .animation(.default, value: filteredAlbums.count)
            }
        }
        .searchable(text: $searchText, prompt: "Search albums...")
    }

    private func removeAlbum(_ album: Album) {
        let artist = album.artist
        for track in album.tracks {
            modelContext.delete(track)
        }
        modelContext.delete(album)
        if let artist, artist.tracks.isEmpty {
            modelContext.delete(artist)
        }
        try? modelContext.save()
    }
}
