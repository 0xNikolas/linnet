import SwiftUI
import SwiftData
import LinnetLibrary

struct SongsListView: View {
    @Query(sort: \Track.title) private var tracks: [Track]
    @Environment(PlayerViewModel.self) private var player

    var body: some View {
        if tracks.isEmpty {
            ContentUnavailableView("No Songs", systemImage: "music.note", description: Text("Add a music folder in Settings to get started."))
        } else {
            List {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    HStack {
                        Text("\(track.trackNumber)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .trailing)

                        Text(track.title)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(track.artist?.name ?? "Unknown")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 150, alignment: .leading)

                        Text(track.album?.name ?? "Unknown")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 150, alignment: .leading)

                        Text(player.formatTime(track.duration))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        player.playTrack(track, queue: tracks, startingAt: index)
                    }
                    .contextMenu {
                        Button("Play") {
                            player.playTrack(track, queue: tracks, startingAt: index)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}
