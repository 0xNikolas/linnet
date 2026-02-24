import SwiftUI
import SwiftData
import LinnetLibrary
import UniformTypeIdentifiers

private func formatTime(_ seconds: Double) -> String {
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%d:%02d", mins, secs)
}

struct AlbumDetailView: View {
    let album: Album
    @Environment(PlayerViewModel.self) private var player
    @Environment(ArtworkService.self) private var artworkService
    @Environment(\.modelContext) private var modelContext
    @State private var isFetchingArtwork = false
    @State private var showEditSheet = false
    @AppStorage("nowPlayingBarHeight") private var barHeight: Double = 56

    private var sortedTracks: [Track] {
        album.tracks.sorted {
            ($0.discNumber, $0.trackNumber) < ($1.discNumber, $1.trackNumber)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .bottom, spacing: 20) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: 200, height: 200)
                    .overlay {
                        if let artData = album.artworkData, let img = NSImage(data: artData) {
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFill()
                        } else if isFetchingArtwork {
                            ProgressView()
                        } else {
                            Image(systemName: "music.note")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .task {
                        guard album.artworkData == nil else { return }
                        isFetchingArtwork = true
                        await artworkService.fetchAlbumArtwork(for: album, context: modelContext)
                        isFetchingArtwork = false
                    }
                    .contextMenu {
                        Button("Find Artwork") {
                            Task {
                                album.artworkData = nil
                                isFetchingArtwork = true
                                await artworkService.fetchAlbumArtwork(for: album, context: modelContext, force: true)
                                isFetchingArtwork = false
                            }
                        }
                        Button("Choose Artwork...") {
                            chooseArtworkFile()
                        }
                        Divider()
                        Button("Edit Album...") { showEditSheet = true }
                    }
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text(album.name)
                        .font(.system(size: 28, weight: .bold))
                    Text(album.artistName ?? "Unknown Artist")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        if let year = album.year {
                            Text(String(year))
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                        }
                        Text("\(sortedTracks.count) songs")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 12) {
                        Button("Play") {
                            if let first = sortedTracks.first {
                                player.playTrack(first, queue: sortedTracks, startingAt: 0)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                        .disabled(sortedTracks.isEmpty)

                        Button("Shuffle") {
                            let shuffled = sortedTracks.shuffled()
                            if let first = shuffled.first {
                                player.playTrack(first, queue: shuffled, startingAt: 0)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(sortedTracks.isEmpty)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(20)

            Divider()

            // Track list with native multi-selection
            AlbumTrackListView(
                sortedTracks: sortedTracks,
                onPlay: { track, queue, index in
                    player.playTrack(track, queue: queue, startingAt: index)
                },
                onPlayNext: { track in
                    player.addNext(track)
                },
                onPlayLater: { track in
                    player.addLater(track)
                },
                onRemove: { trackIDs in
                    removeTracks(ids: trackIDs)
                }
            )
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
            for track in album.tracks where track.artworkData == nil {
                track.artworkData = data
            }
            try? modelContext.save()
        }
    }

    private func removeTracks(ids: Set<PersistentIdentifier>) {
        for id in ids {
            if let track = sortedTracks.first(where: { $0.id == id }) {
                let album = track.album
                let artist = track.artist
                modelContext.delete(track)
                if let album, album.tracks.isEmpty {
                    modelContext.delete(album)
                }
                if let artist, artist.tracks.isEmpty {
                    modelContext.delete(artist)
                }
            }
        }
        try? modelContext.save()
    }
}

// MARK: - AlbumTrackListView (no player environment -- immune to timer-driven redraws)

private struct AlbumTrackListView: View {
    let sortedTracks: [Track]
    let onPlay: (Track, [Track], Int) -> Void
    let onPlayNext: (Track) -> Void
    let onPlayLater: (Track) -> Void
    let onRemove: (Set<PersistentIdentifier>) -> Void

    @State private var selectedTrackIDs: Set<PersistentIdentifier> = []
    @AppStorage("nowPlayingBarHeight") private var barHeight: Double = 56

    var body: some View {
        List(sortedTracks, selection: $selectedTrackIDs) { track in
            HStack {
                Text("\(track.trackNumber)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)

                Text(track.title)
                    .font(.system(size: 13))

                Spacer()

                Text(formatTime(track.duration))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.inset)
        .contentMargins(.bottom, barHeight + 20, for: .scrollContent)
        .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
            contextMenuContent(for: ids)
        } primaryAction: { ids in
            if let id = ids.first, let index = sortedTracks.firstIndex(where: { $0.id == id }) {
                onPlay(sortedTracks[index], sortedTracks, index)
            }
        }
    }

    @ViewBuilder
    private func contextMenuContent(for ids: Set<PersistentIdentifier>) -> some View {
        if let id = ids.first, let index = sortedTracks.firstIndex(where: { $0.id == id }) {
            let track = sortedTracks[index]
            Button("Play") {
                onPlay(track, sortedTracks, index)
            }
            Button("Play Next") {
                onPlayNext(track)
            }
            Button("Play Later") {
                onPlayLater(track)
            }
            Divider()
            AddToPlaylistMenu(tracks: selectedTracks(for: ids))
            Divider()
            Button("Remove from Library", role: .destructive) {
                onRemove(ids)
            }
        }
    }

    private func selectedTracks(for ids: Set<PersistentIdentifier>) -> [Track] {
        sortedTracks.filter { ids.contains($0.id) }
    }
}
