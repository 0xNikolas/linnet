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

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Now Playing
                    if let current = player.currentQueueTrack {
                        Section {
                            queueRow(title: current.title, artist: current.artist?.name ?? "Unknown", artwork: current.artworkData, isCurrent: true)
                                .padding(.horizontal)
                        } header: {
                            sectionHeader("Now Playing")
                        }
                    }

                    // Up Next
                    let upcoming = player.upcomingTracks
                    if !upcoming.isEmpty {
                        Section {
                            ForEach(upcoming) { track in
                                queueRow(title: track.title, artist: track.artist?.name ?? "Unknown", artwork: track.artworkData, isCurrent: false)
                                    .padding(.horizontal)
                            }
                        } header: {
                            sectionHeader("Up Next \u{2014} \(upcoming.count) songs")
                        }
                    }
                }
                .padding(.vertical)
            }
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

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal)
    }
}
