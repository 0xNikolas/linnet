import SwiftUI
import SwiftData
import LinnetLibrary

struct AlbumGridView: View {
    @Query(sort: \Album.name) private var albums: [Album]
    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)]

    var body: some View {
        ScrollView {
            if albums.isEmpty {
                ContentUnavailableView("No Albums", systemImage: "square.stack", description: Text("Add a music folder in Settings to get started."))
                    .frame(maxHeight: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(albums) { album in
                        AlbumCard(
                            name: album.name,
                            artist: album.artistName ?? "Unknown Artist",
                            artwork: album.artworkData.flatMap { NSImage(data: $0) }
                        )
                    }
                }
                .padding(20)
                .animation(.default, value: albums.count)
            }
        }
    }
}
