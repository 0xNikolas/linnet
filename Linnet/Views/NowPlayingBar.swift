import SwiftUI

struct NowPlayingBar: View {
    @Environment(PlayerViewModel.self) private var player

    var body: some View {
        @Bindable var player = player

        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 16) {
                // Album art
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(width: 40, height: 40)
                    .overlay {
                        if let artworkData = player.currentArtworkData,
                           let image = NSImage(data: artworkData) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "music.note")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                // Track info
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentTrackTitle)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(player.currentTrackArtist)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 160, alignment: .leading)

                Spacer()

                // Playback controls
                HStack(spacing: 20) {
                    Button(action: { player.previous() }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)

                    Button(action: { player.togglePlayPause() }) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)

                    Button(action: { player.next() }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Progress
                HStack(spacing: 8) {
                    Text(player.formatTime(player.currentTime))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Slider(value: $player.progress)
                        .frame(width: 200)

                    Text(player.formatTime(player.duration))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                // Volume
                HStack(spacing: 4) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Slider(value: $player.volume, in: 0...1)
                        .frame(width: 80)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                // Queue button
                Button(action: {}) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }
}
