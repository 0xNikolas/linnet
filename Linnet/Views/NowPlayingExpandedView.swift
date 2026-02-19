import SwiftUI

struct NowPlayingExpandedView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerViewModel.self) private var player

    var body: some View {
        @Bindable var player = player

        VStack(spacing: 24) {
            // Large album art
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
                .frame(width: 300, height: 300)
                .overlay {
                    if let artworkData = player.currentArtworkData,
                       let image = NSImage(data: artworkData) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.2), radius: 16, y: 8)

            // Track info
            VStack(spacing: 4) {
                Text(player.currentTrackTitle)
                    .font(.title2.bold())
                Text(player.currentTrackArtist)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            // Progress
            VStack(spacing: 4) {
                Slider(value: $player.progress)
                    .frame(width: 300)
                HStack {
                    Text(player.formatTime(player.currentTime))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(player.formatTime(player.duration))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 300)
            }

            // Controls
            HStack(spacing: 32) {
                Button(action: {}) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button(action: { player.previous() }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)

                Button(action: { player.togglePlayPause() }) {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }
                .buttonStyle(.plain)

                Button(action: { player.next() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)

                Button(action: {}) {
                    Image(systemName: "repeat")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            // Volume
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Slider(value: $player.volume, in: 0...1)
                    .frame(width: 200)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 550)
        .background(.ultraThinMaterial)
    }
}
