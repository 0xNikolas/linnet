import SwiftUI
import SwiftData
import LinnetLibrary
import UniformTypeIdentifiers

// File-level storage — survives SwiftUI view lifecycle
private nonisolated(unsafe) var _albumCardLastClickTime: Date = .distantPast

struct ArtistDetailView: View {
    let artist: Artist
    @Binding var navigationPath: NavigationPath
    @Environment(PlayerViewModel.self) private var player
    @Environment(ArtworkService.self) private var artworkService
    @Environment(\.modelContext) private var modelContext
    @State private var selectedAlbumID: PersistentIdentifier?
    @State private var selectedTrackID: PersistentIdentifier?
    @State private var isFetchingArtwork = false
    @State private var allTracks: [Track] = []

    private func sortedTracks() -> [Track] {
        artist.tracks.sorted { lhs, rhs in
            let lhsYear = lhs.album?.year ?? 0
            let rhsYear = rhs.album?.year ?? 0
            if lhsYear != rhsYear { return lhsYear > rhsYear }
            let lhsAlbum = lhs.album?.name ?? ""
            let rhsAlbum = rhs.album?.name ?? ""
            if lhsAlbum != rhsAlbum { return lhsAlbum < rhsAlbum }
            if lhs.discNumber != rhs.discNumber { return lhs.discNumber < rhs.discNumber }
            return lhs.trackNumber < rhs.trackNumber
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hero
                HStack(spacing: 16) {
                    Circle()
                        .fill(.quaternary)
                        .frame(width: 120, height: 120)
                        .overlay {
                            if let artData = artist.artworkData, let img = NSImage(data: artData) {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFill()
                            } else if isFetchingArtwork {
                                ProgressView()
                            } else {
                                Image(systemName: "music.mic")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .clipShape(Circle())
                        .task {
                            guard artist.artworkData == nil else { return }
                            isFetchingArtwork = true
                            await artworkService.fetchArtistArtwork(for: artist, context: modelContext)
                            isFetchingArtwork = false
                        }
                        .contextMenu {
                            Button("Find Artwork") {
                                Task {
                                    artist.artworkData = nil
                                    isFetchingArtwork = true
                                    await artworkService.fetchArtistArtwork(for: artist, context: modelContext, force: true)
                                    isFetchingArtwork = false
                                }
                            }
                            Button("Choose Artwork...") {
                                chooseArtistArtwork()
                            }
                        }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(artist.name)
                            .font(.system(size: 28, weight: .bold))

                        Text("\(artist.albums.count) albums, \(artist.tracks.count) songs")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)

                        HStack(spacing: 12) {
                            Button("Play") {
                                if let first = allTracks.first {
                                    player.playTrack(first, queue: allTracks, startingAt: 0)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(allTracks.isEmpty)

                            Button("Shuffle") {
                                let shuffled = allTracks.shuffled()
                                if let first = shuffled.first {
                                    player.playTrack(first, queue: shuffled, startingAt: 0)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(allTracks.isEmpty)
                        }
                    }
                }
                .padding(20)

                // Albums section
                if !artist.albums.isEmpty {
                    Text("Albums")
                        .font(.headline)
                        .padding(.horizontal, 20)

                    let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)]
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(artist.albums.sorted(by: { ($0.year ?? Int.min) > ($1.year ?? Int.min) })) { album in
                            ArtistAlbumCard(
                                album: album,
                                artistName: artist.name,
                                isSelected: selectedAlbumID == album.persistentModelID,
                                onSelect: {
                                    selectedAlbumID = album.persistentModelID
                                    selectedTrackID = nil
                                },
                                onNavigate: {
                                    navigationPath.append(album)
                                },
                                onRemove: { removeAlbum(album) }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // Songs section
                if !allTracks.isEmpty {
                    Text("Songs")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(allTracks.enumerated()), id: \.element.id) { index, track in
                            ArtistTrackRow(
                                track: track,
                                index: index,
                                isSelected: selectedTrackID == track.persistentModelID,
                                allTracks: allTracks,
                                onSelect: {
                                    selectedTrackID = track.persistentModelID
                                    selectedAlbumID = nil
                                },
                                onPlay: { t, q, i in player.playTrack(t, queue: q, startingAt: i) },
                                onPlayNext: { player.addNext($0) },
                                onPlayLater: { player.addLater($0) },
                                onRemove: { removeTrack($0) }
                            )
                            .id(track.persistentModelID)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .task { allTracks = sortedTracks() }
        .onChange(of: artist.tracks.count) { _, _ in allTracks = sortedTracks() }
        .onReceive(NotificationCenter.default.publisher(for: .highlightTrackInDetail)) { notification in
            guard let trackID = notification.userInfo?["trackID"] as? PersistentIdentifier else { return }
            // Only act if this track belongs to this artist
            guard allTracks.contains(where: { $0.persistentModelID == trackID }) else { return }
            selectedTrackID = trackID
            selectedAlbumID = nil
            withAnimation {
                proxy.scrollTo(trackID, anchor: .center)
            }
        }
        } // ScrollViewReader
    }

    private func removeTrack(_ track: Track) {
        let album = track.album
        modelContext.delete(track)
        if let album, album.tracks.isEmpty {
            modelContext.delete(album)
        }
        if artist.tracks.isEmpty {
            modelContext.delete(artist)
        }
        try? modelContext.save()
    }

    private func removeAlbum(_ album: Album) {
        for track in album.tracks {
            modelContext.delete(track)
        }
        modelContext.delete(album)
        if artist.tracks.isEmpty {
            modelContext.delete(artist)
        }
        try? modelContext.save()
    }

    private func chooseArtistArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose artwork for \"\(artist.name)\""
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url) {
            artist.artworkData = data
            try? modelContext.save()
        }
    }
}

// MARK: - Artist Track Row

private func formatTime(_ seconds: Double) -> String {
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%d:%02d", mins, secs)
}

// MARK: - Artist Album Card

private struct ArtistAlbumCard: View {
    let album: Album
    let artistName: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onNavigate: () -> Void
    let onRemove: () -> Void

    @Environment(ArtworkService.self) private var artworkService
    @Environment(\.modelContext) private var modelContext
    @State private var isFetching = false
    @State private var showEditSheet = false
    @State private var artwork: NSImage?

    var body: some View {
        Button {
            let now = Date()
            if now.timeIntervalSince(_albumCardLastClickTime) < NSEvent.doubleClickInterval {
                _albumCardLastClickTime = .distantPast
                onNavigate()
            } else {
                _albumCardLastClickTime = now
                onSelect()
            }
        } label: {
            AlbumCard(
                name: album.name,
                artist: artistName,
                artwork: artwork,
                isLoading: isFetching
            )
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .task {
            artwork = album.artworkData.flatMap { NSImage(data: $0) }
            guard artwork == nil else { return }
            isFetching = true
            await artworkService.fetchAlbumArtwork(for: album, context: modelContext)
            artwork = album.artworkData.flatMap { NSImage(data: $0) }
            isFetching = false
        }
        .contextMenu {
            Button("Find Artwork") {
                Task {
                    album.artworkData = nil
                    artwork = nil
                    isFetching = true
                    await artworkService.fetchAlbumArtwork(for: album, context: modelContext, force: true)
                    artwork = album.artworkData.flatMap { NSImage(data: $0) }
                    isFetching = false
                }
            }
            Button("Choose Artwork...") {
                chooseArtworkFile()
            }
            AddToPlaylistMenu(tracks: album.tracks)
            LikeDislikeMenu(tracks: album.tracks)
            Divider()
            Button("Edit Album...") { showEditSheet = true }
            Divider()
            Button("Remove Album from Library", role: .destructive) { onRemove() }
        }
        .sheet(isPresented: $showEditSheet) {
            EditAlbumSheet(album: album)
        }
    }

    private func chooseArtworkFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose artwork for \"\(album.name)\""
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url) {
            album.artworkData = data
            artwork = NSImage(data: data)
            for track in album.tracks where track.artworkData == nil {
                track.artworkData = data
            }
            try? modelContext.save()
        }
    }
}

// MARK: - Artist Track Row

private struct ArtistTrackRow: View {
    let track: Track
    let index: Int
    let isSelected: Bool
    let allTracks: [Track]
    let onSelect: () -> Void
    let onPlay: (Track, [Track], Int) -> Void
    let onPlayNext: (Track) -> Void
    let onPlayLater: (Track) -> Void
    let onRemove: (Track) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text("\(track.trackNumber)")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .frame(width: 30, alignment: .trailing)
                .padding(.trailing, 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(track.album?.name ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if track.likedStatus == 1 {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 12)

            Text(formatTime(track.duration))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .opacity(track.likedStatus == -1 ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .onClicks(single: {
            onSelect()
        }, double: {
            onPlay(track, allTracks, index)
        })
        .contextMenu {
            Button("Play") { onPlay(track, allTracks, index) }
            Button("Play Next") { onPlayNext(track) }
            Button("Play Later") { onPlayLater(track) }
            AddToPlaylistMenu(tracks: [track])
            LikeDislikeMenu(tracks: [track])
            Divider()
            Button("Remove from Library", role: .destructive) { onRemove(track) }
        }
    }
}
