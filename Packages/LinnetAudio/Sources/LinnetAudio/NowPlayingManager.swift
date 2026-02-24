import MediaPlayer
import AppKit

public final class NowPlayingManager: Sendable {
    public static let shared = NowPlayingManager()

    private init() {}

    public func update(title: String, artist: String?, album: String?, duration: Double, currentTime: Double, artwork: Data?) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
        if let artist { info[MPMediaItemPropertyArtist] = artist }
        if let album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let artworkData = artwork, let image = NSImage(data: artworkData) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    public func setPlaybackState(_ playing: Bool) {
        MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
    }

    public func setupRemoteCommands(
        onPlay: @escaping @Sendable () -> Void,
        onPause: @escaping @Sendable () -> Void,
        onTogglePlayPause: @escaping @Sendable () -> Void,
        onNext: @escaping @Sendable () -> Void,
        onPrevious: @escaping @Sendable () -> Void,
        onSeek: @escaping @Sendable (Double) -> Void
    ) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { _ in onPlay(); return .success }
        center.pauseCommand.addTarget { _ in onPause(); return .success }
        center.togglePlayPauseCommand.addTarget { _ in onTogglePlayPause(); return .success }
        center.nextTrackCommand.addTarget { _ in onNext(); return .success }
        center.previousTrackCommand.addTarget { _ in onPrevious(); return .success }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            onSeek(event.positionTime)
            return .success
        }
    }
}
