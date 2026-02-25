import SwiftUI

extension Notification.Name {
    static let navigateToCurrentTrack = Notification.Name("navigateToCurrentTrack")
    static let navigateToCurrentArtist = Notification.Name("navigateToCurrentArtist")
    static let highlightTrackInDetail = Notification.Name("highlightTrackInDetail")
    static let focusSearch = Notification.Name("focusSearch")
    static let openSettings = Notification.Name("openSettings")
}

struct NowPlayingBar: View {
    @Environment(PlayerViewModel.self) private var player
    @State private var showQueue = false
    @State private var showEqualizer = false
    @AppStorage("nowPlayingBarHeight") private var storedBarHeight: Double = 56
    @State private var liveBarHeight: Double?
    private var barHeight: Double { liveBarHeight ?? storedBarHeight }

    var body: some View {
        @Bindable var player = player

        VStack(spacing: 0) {
            // Drag handle for resizing
            Rectangle()
                .fill(Color.clear)
                .frame(height: 4)
                .contentShape(Rectangle())
                .cursor(.resizeUpDown)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            liveBarHeight = max(48, min(120, barHeight - value.translation.height))
                        }
                        .onEnded { _ in
                            storedBarHeight = barHeight
                            liveBarHeight = nil
                        }
                )

            Divider()

            HStack(spacing: 16) {
                // Album art
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(width: artworkSize, height: artworkSize)
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

                // Track info — clickable
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentTrackTitle)
                        .font(.system(size: titleFontSize, weight: .medium))
                        .lineLimit(1)
                        .onTapGesture {
                            guard player.currentQueueTrack != nil else { return }
                            NotificationCenter.default.post(name: .navigateToCurrentTrack, object: nil)
                        }
                        .onHover { hovering in
                            if hovering && player.currentQueueTrack != nil {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    if let error = player.errorMessage {
                        Text(error)
                            .font(.system(size: subtitleFontSize))
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    } else {
                        Text(player.currentTrackArtist)
                            .font(.system(size: subtitleFontSize))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .onTapGesture {
                                guard player.currentQueueTrack?.artist != nil else { return }
                                NotificationCenter.default.post(name: .navigateToCurrentArtist, object: nil)
                            }
                            .onHover { hovering in
                                if hovering && player.currentQueueTrack?.artist != nil {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                    }
                }
                .frame(width: 160, alignment: .leading)

                HStack(spacing: 8) {
                    Button(action: { player.toggleDislike() }) {
                        Image(systemName: player.currentQueueTrack?.likedStatus == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                            .font(.system(size: 14))
                            .foregroundStyle(player.currentQueueTrack?.likedStatus == -1 ? .red : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(player.currentQueueTrack == nil)

                    Button(action: { player.toggleLike() }) {
                        Image(systemName: player.currentQueueTrack?.likedStatus == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.system(size: 14))
                            .foregroundColor(player.currentQueueTrack?.likedStatus == 1 ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(player.currentQueueTrack == nil)
                }

                Spacer()

                // Playback controls
                HStack(spacing: 24) {
                    Button(action: { player.previous() }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: controlSize))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(action: { player.togglePlayPause() }) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: playPauseSize))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(action: { player.next() }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: controlSize))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
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

                // EQ button
                Button(action: { showEqualizer.toggle() }) {
                    Image(systemName: "slider.vertical.3")
                        .font(.system(size: 14))
                        .foregroundColor(player.eqEnabled ? .accentColor : .primary)
                        .overlay(alignment: .topTrailing) {
                            if player.eqEnabled {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 6, height: 6)
                                    .offset(x: 3, y: -3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showEqualizer, arrowEdge: .top) {
                    EqualizerView()
                }

                // Queue button
                Button(action: { showQueue.toggle() }) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 14))
                        .foregroundColor(showQueue ? .accentColor : .primary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showQueue, arrowEdge: .top) {
                    QueuePanel(isShowing: $showQueue)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: barHeight)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Scaled sizes based on bar height

    private var artworkSize: CGFloat { min(barHeight - 16, 80) }
    private var titleFontSize: CGFloat { barHeight > 70 ? 15 : 13 }
    private var subtitleFontSize: CGFloat { barHeight > 70 ? 12 : 11 }
    private var controlSize: CGFloat { barHeight > 70 ? 24 : 20 }
    private var playPauseSize: CGFloat { barHeight > 70 ? 32 : 28 }
}

// MARK: - Cursor helper

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
