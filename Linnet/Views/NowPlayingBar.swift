import SwiftUI

extension Notification.Name {
    static let navigateToCurrentTrack = Notification.Name("navigateToCurrentTrack")
    static let navigateToCurrentArtist = Notification.Name("navigateToCurrentArtist")
    static let highlightTrackInDetail = Notification.Name("highlightTrackInDetail")
    static let focusSearch = Notification.Name("focusSearch")
    static let toggleQueueSidePane = Notification.Name("toggleQueueSidePane")
    static let registerBreadcrumb = Notification.Name("registerBreadcrumb")
    static let navigateToArtist = Notification.Name("navigateToArtist")
    static let navigateToAlbum = Notification.Name("navigateToAlbum")
    static let navigateToPlaylist = Notification.Name("navigateToPlaylist")
}

struct NowPlayingBar: View {
    @Environment(PlayerViewModel.self) private var player
    @State private var showQueue = false
    @State private var showEqualizer = false
    @AppStorage("nowPlayingBarHeight") private var storedBarHeight: Double = 85
    @State private var liveBarHeight: Double?
    private var barHeight: Double { max(72, liveBarHeight ?? storedBarHeight) }

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
                            liveBarHeight = max(72, min(160, barHeight - value.translation.height))
                        }
                        .onEnded { _ in
                            storedBarHeight = barHeight
                            liveBarHeight = nil
                        }
                )

            HStack(spacing: 16) {
                // LEFT: playback controls
                HStack(spacing: 8) {
                    Button(action: { player.shuffleQueue() }) {
                        Image(systemName: "shuffle")
                            .font(.app(size: transportIcon))
                            .frame(width: transportHit, height: transportHit)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(action: { player.previous() }) {
                        Image(systemName: "backward.fill")
                            .font(.app(size: transportIcon))
                            .frame(width: transportHit, height: transportHit)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(action: { player.togglePlayPause() }) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.app(size: playIcon))
                            .frame(width: playHit, height: playHit)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(action: { player.next() }) {
                        Image(systemName: "forward.fill")
                            .font(.app(size: transportIcon))
                            .frame(width: transportHit, height: transportHit)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(action: { player.toggleRepeatMode() }) {
                        Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                            .font(.app(size: transportIcon))
                            .foregroundColor(player.repeatMode == .off ? .primary : .accentColor)
                            .frame(width: transportHit, height: transportHit)
                            .contentShape(Rectangle())
                            .overlay(alignment: .bottom) {
                                if player.repeatMode != .off {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 4, height: 4)
                                        .offset(y: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                // CENTER: now-playing "LCD" pill (art + title/artist + like/dislike, scrubber underneath)
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .frame(width: pillArtworkSize, height: pillArtworkSize)
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

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(player.currentTrackTitle)
                                    .font(.app(size: titleFontSize, weight: .medium))
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
                                        .font(.app(size: subtitleFontSize))
                                        .foregroundStyle(.red)
                                        .lineLimit(1)
                                } else {
                                    Text(player.currentTrackArtist)
                                        .font(.app(size: subtitleFontSize))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .onTapGesture {
                                            guard player.currentQueueTrack?.artistId != nil else { return }
                                            NotificationCenter.default.post(name: .navigateToCurrentArtist, object: nil)
                                        }
                                        .onHover { hovering in
                                            if hovering && player.currentQueueTrack?.artistId != nil {
                                                NSCursor.pointingHand.push()
                                            } else {
                                                NSCursor.pop()
                                            }
                                        }
                                }
                            }

                            Spacer(minLength: 8)

                            Button(action: { player.toggleLike() }) {
                                Image(systemName: player.currentQueueTrack?.likedStatus == 1 ? "bolt.fill" : "bolt")
                                    .font(.app(size: utilityIcon))
                                    .foregroundColor(player.currentQueueTrack?.likedStatus == 1 ? .accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(player.currentQueueTrack == nil)

                            Button(action: { player.toggleDislike() }) {
                                Image(systemName: player.currentQueueTrack?.likedStatus == -1 ? "bolt.slash.fill" : "bolt.slash")
                                    .font(.app(size: utilityIcon))
                                    .foregroundStyle(player.currentQueueTrack?.likedStatus == -1 ? .red : .secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(player.currentQueueTrack == nil)
                        }

                        HStack(spacing: 6) {
                            Text(player.formatTime(player.currentTime))
                                .font(.app(size: timeFontSize, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Slider(value: $player.progress)
                                .controlSize(.mini)
                                .frame(maxWidth: .infinity)

                            Text(player.formatTime(player.duration))
                                .font(.app(size: timeFontSize, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4)))
                .frame(width: 800)

                // RIGHT: queue + audio settings (EQ + volume)
                HStack(spacing: 14) {
                    Button(action: { showQueue.toggle() }) {
                        Image(systemName: "list.bullet")
                            .font(.app(size: utilityIcon))
                            .foregroundColor(showQueue ? .accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showQueue, arrowEdge: .top) {
                        QueuePanel(isShowing: $showQueue)
                    }

                    Button(action: { showEqualizer.toggle() }) {
                        Image(systemName: "slider.vertical.3")
                            .font(.app(size: utilityIcon))
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

                    HStack(spacing: 4) {
                        Image(systemName: "speaker.fill")
                            .font(.app(size: glyphSize))
                            .foregroundStyle(.secondary)
                        Slider(value: $player.volume, in: 0...1)
                            .frame(width: 80)
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.app(size: glyphSize))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .frame(height: barHeight)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Uniform icon & type scale
    //
    // One scale for the whole bar so every control feels balanced:
    //  • transportIcon — all transport glyphs (shuffle, prev, next, repeat)
    //  • playIcon      — the single primary play/pause glyph (one step up)
    //  • utilityIcon   — like/dislike, queue, EQ
    //  • glyphSize     — small inline glyphs (volume speakers)
    // Tap targets follow the same hierarchy via the button frames below.

    private var pillArtworkSize: CGFloat { min(barHeight - 40, 64) }
    private var transportIcon: CGFloat { 16 }
    private var playIcon: CGFloat { 22 }
    private var utilityIcon: CGFloat { 13 }
    private var glyphSize: CGFloat { 10 }
    private var titleFontSize: CGFloat { 13 }
    private var subtitleFontSize: CGFloat { 11 }
    private var timeFontSize: CGFloat { 10 }

    // Tap-target sizes
    private var transportHit: CGFloat { 30 }
    private var playHit: CGFloat { 34 }
}

// MARK: - Cursor helper

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
