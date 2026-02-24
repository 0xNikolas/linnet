import SwiftUI
import SwiftData
import LinnetLibrary

struct ArtistDetailView: View {
    let artist: Artist
    @Environment(PlayerViewModel.self) private var player
    @Environment(ArtworkService.self) private var artworkService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.navigationPath) private var navigationPath
    @State private var selectedAlbumID: PersistentIdentifier?
    @State private var selectedTrackID: PersistentIdentifier?
    @State private var isFetchingArtwork = false
    @AppStorage("nowPlayingBarHeight") private var barHeight: Double = 56

    private var allTracks: [Track] {
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
                                    isFetchingArtwork = true
                                    await artworkService.fetchArtistArtwork(for: artist, context: modelContext, force: true)
                                    isFetchingArtwork = false
                                }
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
                            AlbumCard(
                                name: album.name,
                                artist: artist.name,
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
                            .onClicks(single: {
                                selectedAlbumID = album.persistentModelID
                                selectedTrackID = nil
                            }, double: {
                                navigationPath.wrappedValue.append(album)
                            })
                            .contextMenu {
                                Button("Find Artwork") {
                                    Task {
                                        await artworkService.fetchAlbumArtwork(for: album, context: modelContext, force: true)
                                    }
                                }
                                AddToPlaylistMenu(tracks: album.tracks)
                                Divider()
                                Button("Remove Album from Library", role: .destructive) {
                                    removeAlbum(album)
                                }
                            }
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
            .padding(.bottom, barHeight + 20)
        }
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
}

// MARK: - Artist Track Row

private func formatTime(_ seconds: Double) -> String {
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%d:%02d", mins, secs)
}

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
            Divider()
            Button("Remove from Library", role: .destructive) { onRemove(track) }
        }
    }
}
