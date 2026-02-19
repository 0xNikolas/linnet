import MediaPlayer
import AppKit

@MainActor
public final class NowPlayingManager {
    public static let shared = NowPlayingManager()

    private init() {}

    public func update(title: String, artist: String?, album: String?, duration: Double, currentTime: Double, artwork: Data?) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
        ]
        if let artist { info[MPMediaItemPropertyArtist] = artist }
        if let album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let artworkData = artwork, let image = NSImage(data: artworkData) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    public func setupRemoteCommands(
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onPrevious: @escaping () -> Void,
        onSeek: @escaping (Double) -> Void
    ) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { _ in onPlay(); return .success }
        center.pauseCommand.addTarget { _ in onPause(); return .success }
        center.nextTrackCommand.addTarget { _ in onNext(); return .success }
        center.previousTrackCommand.addTarget { _ in onPrevious(); return .success }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            onSeek(event.positionTime)
            return .success
        }
    }
}
