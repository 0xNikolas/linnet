import SwiftUI
import LinnetLibrary
import GRDB
import UniformTypeIdentifiers

struct ArtistListView: View {
    @Environment(\.appDatabase) private var appDatabase
    @Environment(\.navigationPath) private var navigationPath
    @State private var observer: DatabaseObserver<[ArtistInfo]>?
    @State private var selectedArtistID: Int64?
    @AppStorage("artistSortOption") private var sortOption: ArtistSortOption = .name
    @AppStorage("artistSortDirection") private var sortDirection: SortDirection = .ascending
    @State private var searchText = ""
    @State private var isSearchPresented = false

    private var artists: [ArtistInfo] { observer?.value ?? [] }

    var body: some View {
        List(selection: $selectedArtistID) {
            if artists.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Artists" : "No Results",
                    systemImage: searchText.isEmpty ? "music.mic" : "magnifyingglass",
                    description: Text(searchText.isEmpty
                        ? "Add a music folder in Settings to get started."
                        : "No artists matching \"\(searchText)\"")
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                ForEach(artists) { artist in
                    ArtistRow(artist: artist, onRemove: { removeArtist(artist) })
                        .tag(artist.id)
                }
            }
        }
        .contextMenu(forSelectionType: Int64.self, menu: { _ in }, primaryAction: { identifiers in
            guard let id = identifiers.first,
                  let artist = artists.first(where: { $0.id == id }) else { return }
            let artistRecord = ArtistRecord(id: artist.id, name: artist.name)
            navigationPath.wrappedValue.append(artistRecord)
        })
        .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search artists...")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                SortFilterMenuButton(sortOption: $sortOption, sortDirection: $sortDirection)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            isSearchPresented = true
        }
        .task {
            guard let db = appDatabase else { return }
            observer = DatabaseObserver(
                initial: [],
                in: db.pool,
                observation: makeObservation()
            )
        }
        .onChange(of: searchText) { _, _ in reobserve() }
        .onChange(of: sortOption) { _, _ in reobserve() }
        .onChange(of: sortDirection) { _, _ in reobserve() }
    }

    private func makeObservation() -> ValueObservation<ValueReducers.Fetch<[ArtistInfo]>> {
        let ordering = sortOption.sqlColumn
        let dir = sortDirection.sql
        let search = searchText
        return ValueObservation.tracking { db in
            if search.isEmpty {
                let sql = """
                    SELECT
                        artist.id, artist.name,
                        COUNT(DISTINCT album.id) AS albumCount,
                        COUNT(DISTINCT track.id) AS trackCount
                    FROM artist
                    LEFT JOIN album ON album.artistId = artist.id
                    LEFT JOIN track ON track.artistId = artist.id
                    GROUP BY artist.id
                    ORDER BY \(ordering) \(dir)
                    """
                return try ArtistInfo.fetchAll(db, sql: sql)
            } else {
                let pattern = "%\(search)%"
                let sql = """
                    SELECT
                        artist.id, artist.name,
                        COUNT(DISTINCT album.id) AS albumCount,
                        COUNT(DISTINCT track.id) AS trackCount
                    FROM artist
                    LEFT JOIN album ON album.artistId = artist.id
                    LEFT JOIN track ON track.artistId = artist.id
                    WHERE artist.name LIKE ?
                    GROUP BY artist.id
                    ORDER BY artist.name
                    """
                return try ArtistInfo.fetchAll(db, sql: sql, arguments: [pattern])
            }
        }
    }

    private func reobserve() {
        guard let db = appDatabase else { return }
        observer?.reobserve(in: db.pool, observation: makeObservation())
    }

    private func removeArtist(_ artist: ArtistInfo) {
        guard let db = appDatabase else { return }
        let tracks = (try? db.tracks.fetchInfoByArtist(id: artist.id)) ?? []
        do {
            for track in tracks {
                try db.tracks.delete(id: track.id)
            }
            try db.albums.deleteOrphaned()
            try db.artists.delete(id: artist.id)
            try db.artwork.delete(ownerType: "artist", ownerId: artist.id)
        } catch {
            Log.database.error("Failed to remove artist \(artist.id): \(error)")
        }
    }
}

// MARK: - Per-row wrapper with loading state

private struct ArtistRow: View {
    let artist: ArtistInfo
    let onRemove: () -> Void

    @Environment(ArtworkService.self) private var artworkService
    @Environment(\.appDatabase) private var appDatabase
    @State private var isFetching = false
    @State private var artwork: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.quaternary)
                .frame(width: 40, height: 40)
                .overlay {
                    if let artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .scaledToFill()
                    } else if isFetching {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "music.mic")
                            .foregroundStyle(.secondary)
                    }
                }
                .clipShape(Circle())
                .allowsHitTesting(false)

            VStack(alignment: .leading) {
                Text(artist.name)
                    .font(.app(size: 14))
                Text("\(artist.albumCount) albums")
                    .font(.app(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .task {
            loadArtwork()
            guard artwork == nil, let db = appDatabase else { return }
            isFetching = true
            let found = await artworkService.fetchArtistArtwork(artistId: artist.id, artistName: artist.name, db: db)
            if found { loadArtwork() }
            isFetching = false
        }
        .contextMenu {
            Button {
                Task {
                    guard let db = appDatabase else { return }
                    do { try db.artwork.delete(ownerType: "artist", ownerId: artist.id) } catch { Log.database.error("Failed to delete artist artwork \(artist.id): \(error)") }
                    artwork = nil
                    isFetching = true
                    let found = await artworkService.fetchArtistArtwork(artistId: artist.id, artistName: artist.name, db: db, force: true)
                    if found { loadArtwork() }
                    isFetching = false
                }
            } label: { Label("Find Artwork", systemImage: "photo") }
            Button { chooseArtworkFile() } label: { Label("Choose Artwork...", systemImage: "folder") }
            Divider()
            Button(role: .destructive) { onRemove() } label: { Label("Remove from Library", systemImage: "trash") }
        }
    }

    private func loadArtwork() {
        guard let db = appDatabase,
              let data = try? db.artwork.fetchImageData(ownerType: "artist", ownerId: artist.id),
              let img = NSImage(data: data) else { return }
        artwork = img
    }

    private func chooseArtworkFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose artwork for \"\(artist.name)\""
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url) {
            do { try appDatabase?.artwork.upsert(ownerType: "artist", ownerId: artist.id, imageData: data, thumbnailData: nil) } catch { Log.database.error("Failed to upsert artist artwork \(artist.id): \(error)") }
            artwork = NSImage(data: data)
        }
    }
}
