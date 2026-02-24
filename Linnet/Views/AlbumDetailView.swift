import SwiftUI
import LinnetLibrary

struct AlbumDetailView: View {
    let album: Album
    @Environment(PlayerViewModel.self) private var player

    private var sortedTracks: [Track] {
        album.tracks.sorted {
            ($0.discNumber, $0.trackNumber) < ($1.discNumber, $1.trackNumber)
        }
    }

    var body: some View {
        ScrollView {
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
                            } else {
                                Image(systemName: "music.note")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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

                // Track list
                ForEach(Array(sortedTracks.enumerated()), id: \.element.id) { index, track in
                    HStack {
                        Text("\(track.trackNumber)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .trailing)

                        Text(track.title)
                            .font(.system(size: 13))

                        Spacer()

                        Text(player.formatTime(track.duration))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        player.playTrack(track, queue: sortedTracks, startingAt: index)
                    }
                    .contextMenu {
                        Button("Play") {
                            player.playTrack(track, queue: sortedTracks, startingAt: index)
                        }
                    }

                    if index < sortedTracks.count - 1 {
                        Divider()
                            .padding(.leading, 60)
                    }
                }
            }
        }
    }
}
