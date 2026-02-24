import SwiftUI
import SwiftData
import LinnetLibrary

struct ListenNowView: View {
    @Query(sort: \Album.name) private var albums: [Album]
    @Query(sort: \Track.dateAdded, order: .reverse) private var recentTracks: [Track]
    @Environment(PlayerViewModel.self) private var player

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
                    if !recentTracks.isEmpty {
                        let displayedTracks = Array(recentTracks.prefix(10))
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
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    player.playTrack(track, queue: displayedTracks, startingAt: index)
                                }
                                .contextMenu {
                                    Button("Play") {
                                        player.playTrack(track, queue: displayedTracks, startingAt: index)
                                    }
                                }
                            }
                        }
                    }

                    if !albums.isEmpty {
                        HorizontalScrollRow(title: "Albums") {
                            ForEach(albums.prefix(10)) { album in
                                NavigationLink(value: album) {
                                    AlbumCard(
                                        name: album.name,
                                        artist: album.artistName ?? "Unknown",
                                        artwork: album.artworkData.flatMap { NSImage(data: $0) }
                                    )
                                    .frame(width: 160)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

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
            .padding(.bottom, 20)
        }
    }
}
