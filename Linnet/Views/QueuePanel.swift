import SwiftUI
import LinnetLibrary

struct QueuePanel: View {
    @Binding var isShowing: Bool
    @Environment(PlayerViewModel.self) private var player

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Queue")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    player.clearQueue()
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

            List {
                // Now Playing
                if let current = player.currentQueueTrack {
                    Section {
                        queueRow(title: current.title, artist: current.artist?.name ?? "Unknown", artwork: current.artworkData, isCurrent: true)
                    } header: {
                        Text("Now Playing")
                    }
                }

                // Up Next
                let upcoming = player.upcomingTracks
                if !upcoming.isEmpty {
                    Section {
                        ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, track in
                            queueRow(title: track.title, artist: track.artist?.name ?? "Unknown", artwork: track.artworkData, isCurrent: false)
                                .contextMenu {
                                    Button("Play") {
                                        player.playFromQueue(at: index)
                                    }
                                    Divider()
                                    Button("Remove from Queue", role: .destructive) {
                                        player.removeFromQueue(at: IndexSet(integer: index))
                                    }
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

    private func queueRow(title: String, artist: String, artwork: Data?, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .frame(width: 36, height: 36)
                .overlay {
                    if let data = artwork, let img = NSImage(data: data) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading) {
                Text(title)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                Text(artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
