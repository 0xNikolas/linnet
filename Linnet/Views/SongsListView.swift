import SwiftUI
import SwiftData
import LinnetLibrary

struct SongsListView: View {
    @Query(sort: \Track.title) private var tracks: [Track]

    var body: some View {
        if tracks.isEmpty {
            ContentUnavailableView("No Songs", systemImage: "music.note", description: Text("Add a music folder in Settings to get started."))
        } else {
            Table(tracks) {
                TableColumn("#") { track in
                    Text("\(track.trackNumber)")
                        .foregroundStyle(.secondary)
                }
                .width(min: 30, ideal: 40, max: 50)

                TableColumn("Title") { track in
                    Text(track.title)
                }
                .width(min: 100, ideal: 200)

                TableColumn("Artist") { track in
                    Text(track.artist?.name ?? "Unknown")
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 150)

                TableColumn("Album") { track in
                    Text(track.album?.name ?? "Unknown")
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 150)

                TableColumn("Duration") { track in
                    Text(formatDuration(track.duration))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .width(min: 50, ideal: 60, max: 80)
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
