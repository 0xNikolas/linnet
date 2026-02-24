import SwiftUI
import SwiftData
import LinnetLibrary
import UniformTypeIdentifiers

struct AlbumGridView: View {
    @Query(sort: \Album.name) private var albums: [Album]
    @Environment(\.modelContext) private var modelContext
    @Environment(ArtworkService.self) private var artworkService
    @Environment(\.navigationPath) private var navigationPath
    @State private var selectedAlbumID: PersistentIdentifier?
    @State private var searchText = ""
    @State private var isSearchPresented = false
    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)]

    private var filteredAlbums: [Album] {
        if searchText.isEmpty { return albums }
        let query = searchText
        return albums.filter { album in
            album.name.searchContains(query) ||
            (album.artistName ?? "").searchContains(query)
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
                        AlbumGridItem(
                            album: album,
                            isSelected: selectedAlbumID == album.persistentModelID,
                            onSelect: { selectedAlbumID = album.persistentModelID },
                            onNavigate: { navigationPath.wrappedValue.append(album) },
                            onRemove: { removeAlbum(album) }
                        )
                    }
                }
                .padding(20)
                .animation(.default, value: filteredAlbums.count)
            }
        }
        .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search albums...")
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            isSearchPresented = true
        }
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

// MARK: - Per-item wrapper with its own loading state

private struct AlbumGridItem: View {
    let album: Album
    let isSelected: Bool
    let onSelect: () -> Void
    let onNavigate: () -> Void
    let onRemove: () -> Void

    @Environment(ArtworkService.self) private var artworkService
    @Environment(\.modelContext) private var modelContext
    @State private var isFetching = false
    @State private var showEditSheet = false

    var body: some View {
        AlbumCard(
            name: album.name,
            artist: album.artistName ?? "Unknown Artist",
            artwork: album.artworkData.flatMap { NSImage(data: $0) },
            isLoading: isFetching
        )
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .onClicks(single: { onSelect() }, double: { onNavigate() })
        .task {
            guard album.artworkData == nil else { return }
            isFetching = true
            await artworkService.fetchAlbumArtwork(for: album, context: modelContext)
            isFetching = false
        }
        .contextMenu {
            Button("Find Artwork") {
                Task {
                    album.artworkData = nil
                    isFetching = true
                    await artworkService.fetchAlbumArtwork(for: album, context: modelContext, force: true)
                    isFetching = false
                }
            }
            Button("Choose Artwork...") {
                chooseArtworkFile(for: album)
            }
            Divider()
            Button("Edit Album...") { showEditSheet = true }
            Divider()
            Button("Remove from Library", role: .destructive) { onRemove() }
        }
        .sheet(isPresented: $showEditSheet) {
            EditAlbumSheet(album: album)
        }
    }

    private func chooseArtworkFile(for album: Album) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose artwork for \"\(album.name)\""
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url) {
            album.artworkData = data
            for track in album.tracks where track.artworkData == nil {
                track.artworkData = data
            }
            try? modelContext.save()
        }
    }
}
