import SwiftUI
import LinnetLibrary
import UniformTypeIdentifiers

struct AlbumGridView: View {
    @Environment(\.appDatabase) private var appDatabase
    @Environment(ArtworkService.self) private var artworkService
    @Environment(\.navigationPath) private var navigationPath
    @State private var albums: [AlbumInfo] = []
    @State private var selectedAlbumID: Int64?
    @AppStorage("albumSortOption") private var sortOption: AlbumSortOption = .name
    @AppStorage("albumSortDirection") private var sortDirection: SortDirection = .ascending
    @State private var searchText = ""
    @State private var isSearchPresented = false
    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)]

    var body: some View {
        ScrollView {
            if albums.isEmpty {
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
                    ForEach(albums) { album in
                        AlbumGridItem(
                            album: album,
                            isSelected: selectedAlbumID == album.id,
                            onSelect: { selectedAlbumID = album.id },
                            onNavigate: {
                                let record = AlbumRecord(id: album.id, name: album.name, artistName: album.artistName, year: album.year, artistId: album.artistId)
                                navigationPath.wrappedValue.append(record)
                            },
                            onRemove: { removeAlbum(album) }
                        )
                    }
                }
                .padding(20)
                .animation(.default, value: albums.count)
            }
        }
        .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search albums...")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                SortFilterMenuButton(sortOption: $sortOption, sortDirection: $sortDirection)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            isSearchPresented = true
        }
        .task { loadAlbums() }
        .onChange(of: searchText) { _, _ in loadAlbums() }
        .onChange(of: sortOption) { _, _ in loadAlbums() }
        .onChange(of: sortDirection) { _, _ in loadAlbums() }
    }

    private func loadAlbums() {
        guard let db = appDatabase else { return }
        if searchText.isEmpty {
            albums = (try? db.albums.fetchAllInfo(orderedBy: sortOption.sqlColumn, direction: sortDirection.sql)) ?? []
        } else {
            albums = (try? db.albums.searchInfo(query: searchText)) ?? []
        }
    }

    private func removeAlbum(_ album: AlbumInfo) {
        guard let db = appDatabase else { return }
        let tracks = (try? db.tracks.fetchInfoByAlbum(id: album.id)) ?? []
        for track in tracks {
            try? db.tracks.delete(id: track.id)
        }
        try? db.albums.delete(id: album.id)
        try? db.artwork.delete(ownerType: "album", ownerId: album.id)
        try? db.artists.deleteOrphaned()
        loadAlbums()
    }
}

// MARK: - Per-item wrapper with its own loading state

private struct AlbumGridItem: View {
    let album: AlbumInfo
    let isSelected: Bool
    let onSelect: () -> Void
    let onNavigate: () -> Void
    let onRemove: () -> Void

    @Environment(ArtworkService.self) private var artworkService
    @Environment(\.appDatabase) private var appDatabase
    @State private var isFetching = false
    @State private var showEditSheet = false
    @State private var artwork: NSImage?

    var body: some View {
        AlbumCard(
            name: album.name,
            artist: album.artistName ?? "Unknown Artist",
            artwork: artwork,
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
            loadArtwork()
            guard artwork == nil, let db = appDatabase else { return }
            isFetching = true
            let found = await artworkService.fetchAlbumArtwork(albumId: album.id, albumName: album.name, artistName: album.artistName, db: db)
            if found { loadArtwork() }
            isFetching = false
        }
        .contextMenu {
            Button {
                Task {
                    guard let db = appDatabase else { return }
                    try? db.artwork.delete(ownerType: "album", ownerId: album.id)
                    artwork = nil
                    isFetching = true
                    let found = await artworkService.fetchAlbumArtwork(albumId: album.id, albumName: album.name, artistName: album.artistName, db: db, force: true)
                    if found { loadArtwork() }
                    isFetching = false
                }
            } label: { Label("Find Artwork", systemImage: "photo") }
            Button { chooseArtworkFile() } label: { Label("Choose Artwork...", systemImage: "folder") }
            let tracks = (try? appDatabase?.tracks.fetchInfoByAlbum(id: album.id)) ?? []
            LikeDislikeMenu(tracks: tracks)
            Divider()
            if let artistId = album.artistId {
                Button {
                    NotificationCenter.default.post(name: .navigateToArtist, object: nil, userInfo: ["artistId": artistId, "artistName": album.artistName ?? ""])
                } label: { Label("Go to Artist", systemImage: "music.mic") }
            }
            Divider()
            Button { showEditSheet = true } label: { Label("Edit Album...", systemImage: "pencil") }
            Divider()
            Button(role: .destructive) { onRemove() } label: { Label("Remove from Library", systemImage: "trash") }
        }
        .sheet(isPresented: $showEditSheet) {
            let record = AlbumRecord(id: album.id, name: album.name, artistName: album.artistName, year: album.year, artistId: album.artistId)
            EditAlbumSheet(album: record)
        }
    }

    private func loadArtwork() {
        guard let db = appDatabase,
              let data = try? db.artwork.fetchImageData(ownerType: "album", ownerId: album.id),
              let img = NSImage(data: data) else { return }
        artwork = img
    }

    private func chooseArtworkFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose artwork for \"\(album.name)\""
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url) {
            try? appDatabase?.artwork.upsert(ownerType: "album", ownerId: album.id, imageData: data, thumbnailData: nil)
            artwork = NSImage(data: data)
        }
    }
}
