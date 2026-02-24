import SwiftUI
import SwiftData
import LinnetLibrary

struct ArtistListView: View {
    @Query(sort: \Artist.name) private var artists: [Artist]
    @Environment(\.modelContext) private var modelContext
    @Environment(ArtworkService.self) private var artworkService
    @Environment(\.navigationPath) private var navigationPath
    @State private var selectedArtistID: PersistentIdentifier?
    @State private var searchText = ""

    private var filteredArtists: [Artist] {
        if searchText.isEmpty { return artists }
        let query = searchText
        return artists.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List(selection: $selectedArtistID) {
            if filteredArtists.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Artists" : "No Results",
                    systemImage: searchText.isEmpty ? "music.mic" : "magnifyingglass",
                    description: Text(searchText.isEmpty
                        ? "Add a music folder in Settings to get started."
                        : "No artists matching \"\(searchText)\"")
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                ForEach(filteredArtists) { artist in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(.quaternary)
                            .frame(width: 40, height: 40)
                            .overlay {
                                if let artData = artist.artworkData, let img = NSImage(data: artData) {
                                    Image(nsImage: img)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Image(systemName: "music.mic")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .clipShape(Circle())
                            .task {
                                guard artist.artworkData == nil else { return }
                                await artworkService.fetchArtistArtwork(for: artist, context: modelContext)
                            }

                        VStack(alignment: .leading) {
                            Text(artist.name)
                                .font(.system(size: 14))
                            Text("\(artist.albums.count) albums")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(artist.persistentModelID)
                    .contextMenu {
                        Button("Find Artwork") {
                            Task {
                                await artworkService.fetchArtistArtwork(for: artist, context: modelContext)
                            }
                        }
                        Divider()
                        Button("Remove from Library", role: .destructive) {
                            removeArtist(artist)
                        }
                    }
                }
            }
        }
        .contentMargins(.bottom, 60, for: .scrollContent)
        .searchable(text: $searchText, prompt: "Search artists...")
        .contextMenu(forSelectionType: PersistentIdentifier.self, menu: { _ in }, primaryAction: { identifiers in
            guard let id = identifiers.first,
                  let artist = filteredArtists.first(where: { $0.persistentModelID == id }) else { return }
            navigationPath.wrappedValue.append(artist)
        })
    }

    private func removeArtist(_ artist: Artist) {
        for album in artist.albums {
            for track in album.tracks {
                modelContext.delete(track)
            }
            modelContext.delete(album)
        }
        for track in artist.tracks where track.album == nil {
            modelContext.delete(track)
        }
        modelContext.delete(artist)
        try? modelContext.save()
    }
}
