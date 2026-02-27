import SwiftUI
import LinnetLibrary

struct QueuePanel: View {
    @Binding var isShowing: Bool
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.appDatabase) private var appDatabase
    @State private var selectedTrackIDs: Set<Int64> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Queue")
                    .font(.headline)
                Spacer()
                if !selectedTrackIDs.isEmpty {
                    Button("Remove Selected") {
                        removeSelected()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
                Button("Clear") {
                    player.clearQueue()
                    selectedTrackIDs = []
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                Button(action: { isShowing = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            List(selection: $selectedTrackIDs) {
                if player.currentQueueTrack == nil && player.upcomingTracks.isEmpty {
                    ContentUnavailableView("No Songs in Queue", systemImage: "music.note.list", description: Text("Play a song to start the queue."))
                        .frame(maxWidth: .infinity, minHeight: 200)
                }

                // Now Playing
                if let current = player.currentQueueTrack {
                    Section {
                        QueueTrackRow(
                            track: current,
                            isCurrent: true,
                            appDatabase: appDatabase
                        )
                        .tag(current.id)
                    } header: {
                        Text("Now Playing")
                    }
                }

                // Up Next
                let upcoming = player.upcomingTracks
                if !upcoming.isEmpty {
                    Section {
                        ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, track in
                            QueueTrackRow(
                                track: track,
                                isCurrent: false,
                                appDatabase: appDatabase
                            )
                            .tag(track.id)
                            .contextMenu {
                                Button { player.playFromQueue(at: index) } label: { Label("Play", systemImage: "play") }
                                Divider()
                                if let artistId = track.artistId, let artistName = track.artistName {
                                    Button {
                                        NotificationCenter.default.post(name: .navigateToArtist, object: nil, userInfo: ["artistId": artistId, "artistName": artistName])
                                    } label: { Label("Go to Artist", systemImage: "music.mic") }
                                }
                                if let albumId = track.albumId {
                                    Button {
                                        NotificationCenter.default.post(name: .navigateToAlbum, object: nil, userInfo: ["albumId": albumId])
                                    } label: { Label("Go to Album", systemImage: "square.stack") }
                                }
                                Divider()
                                Button(role: .destructive) {
                                    player.removeFromQueue(at: IndexSet(integer: index))
                                } label: { Label("Remove from Queue", systemImage: "minus.circle") }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    player.removeFromQueue(at: IndexSet(integer: index))
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                        .onMove { source, destination in
                            player.moveInQueue(from: source, to: destination)
                        }
                    } header: {
                        Text("Up Next — \(upcoming.count) songs")
                    }
                }
            }
            .listStyle(.plain)
        }
        .frame(width: 300)
        .background(.ultraThinMaterial)
    }

    private func removeSelected() {
        let upcoming = player.upcomingTracks
        var indices = IndexSet()
        for (index, track) in upcoming.enumerated() {
            if selectedTrackIDs.contains(track.id) {
                indices.insert(index)
            }
        }
        player.removeFromQueue(at: indices)
        selectedTrackIDs = []
    }
}

private struct QueueTrackRow: View {
    let track: TrackInfo
    let isCurrent: Bool
    let appDatabase: AppDatabase?
    @State private var artwork: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .frame(width: 36, height: 36)
                .overlay {
                    if let img = artwork {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading) {
                Text(track.title)
                    .font(.app(size: 13, weight: isCurrent ? .semibold : .regular))
                Text(track.artistName ?? "Unknown")
                    .font(.app(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .task {
            guard let albumId = track.albumId, let db = appDatabase,
                  let data = try? db.artwork.fetchImageData(ownerType: "album", ownerId: albumId),
                  let img = NSImage(data: data) else { return }
            artwork = img
        }
    }
}
