import SwiftUI
import SwiftData
import LinnetLibrary

struct ListenNowView: View {
    @Query(sort: \Album.name) private var albums: [Album]
    @Query(sort: \Track.dateAdded, order: .reverse) private var recentTracks: [Track]
    @Environment(PlayerViewModel.self) private var player
    @Environment(ArtworkService.self) private var artworkService
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var selectedTrackID: PersistentIdentifier?
    @State private var selectedAlbumID: PersistentIdentifier?
    @Environment(\.navigationPath) private var navigationPath

    private var filteredRecentTracks: [Track] {
        let source = Array(recentTracks.prefix(20))
        if searchText.isEmpty { return source }
        let query = searchText
        return source.filter { track in
            track.title.localizedCaseInsensitiveContains(query) ||
            (track.artist?.name ?? "").localizedCaseInsensitiveContains(query) ||
            (track.album?.name ?? "").localizedCaseInsensitiveContains(query)
        }
    }

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
            VStack(alignment: .leading, spacing: 30) {
                Text("Listen Now")
                    .font(.largeTitle.bold())
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                if albums.isEmpty && recentTracks.isEmpty {
                    ContentUnavailableView("Welcome to Linnet", systemImage: "music.note.house", description: Text("Add a music folder in Settings to get started."))
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    if !filteredRecentTracks.isEmpty {
                        let displayedTracks = Array(filteredRecentTracks.prefix(10))
                        HorizontalScrollRow(title: "Recently Added") {
                            ForEach(Array(displayedTracks.enumerated()), id: \.element.id) { index, track in
                                VStack(alignment: .leading, spacing: 6) {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.quaternary)
                                        .frame(width: 160, height: 160)
                                        .overlay {
                                            if let artData = track.artworkData, let img = NSImage(data: artData) {
                                                Image(nsImage: img)
                                                    .resizable()
                                                    .scaledToFill()
                                            } else {
                                                Image(systemName: "music.note")
                                                    .font(.system(size: 30))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    Text(track.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                    Text(track.artist?.name ?? "Unknown")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(width: 160)
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(selectedTrackID == track.persistentModelID
                                              ? Color.accentColor.opacity(0.15)
                                              : Color.clear)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedTrackID = track.persistentModelID
                                    selectedAlbumID = nil
                                }
                                .onDoubleClick {
                                    player.playTrack(track, queue: displayedTracks, startingAt: index)
                                }
                                .task {
                                    guard track.artworkData == nil, let album = track.album, album.artworkData == nil else { return }
                                    await artworkService.fetchAlbumArtwork(for: album, context: modelContext)
                                }
                                .contextMenu {
                                    Button("Play") {
                                        player.playTrack(track, queue: displayedTracks, startingAt: index)
                                    }
                                    Button("Play Next") {
                                        player.addNext(track)
                                    }
                                    Button("Play Later") {
                                        player.addLater(track)
                                    }
                                    AddToPlaylistMenu(tracks: [track])
                                    Divider()
                                    Button("Remove from Library", role: .destructive) {
                                        removeTrack(track)
                                    }
                                }
                            }
                        }
                    }

                    if !filteredAlbums.isEmpty {
                        HorizontalScrollRow(title: "Albums") {
                            ForEach(filteredAlbums.prefix(10)) { album in
                                AlbumCard(
                                    name: album.name,
                                    artist: album.artistName ?? "Unknown",
                                    artwork: album.artworkData.flatMap { NSImage(data: $0) }
                                )
                                .frame(width: 160)
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
                                    selectedTrackID = nil
                                }
                                .onDoubleClick {
                                    navigationPath.wrappedValue.append(album)
                                }
                                .task {
                                    guard album.artworkData == nil else { return }
                                    await artworkService.fetchAlbumArtwork(for: album, context: modelContext)
                                }
                                .contextMenu {
                                    Button("Remove from Library", role: .destructive) {
                                        removeAlbum(album)
                                    }
                                }
                            }
                        }
                    }

                    if searchText.isEmpty {
                        HorizontalScrollRow(title: "AI Suggestions") {
                            ForEach(1...6, id: \.self) { _ in
                                VStack(alignment: .leading, spacing: 6) {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.quaternary)
                                        .frame(width: 160, height: 160)
                                        .overlay {
                                            Image(systemName: "sparkles")
                                                .font(.system(size: 30))
                                                .foregroundStyle(.secondary)
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    Text("Set up AI")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    Text("Enable in Settings")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(width: 160)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 80)
        }
        .searchable(text: $searchText, prompt: "Search...")
    }

    private func removeTrack(_ track: Track) {
        let album = track.album
        let artist = track.artist
        modelContext.delete(track)
        if let album, album.tracks.isEmpty {
            modelContext.delete(album)
        }
        if let artist, artist.tracks.isEmpty {
            modelContext.delete(artist)
        }
        try? modelContext.save()
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
