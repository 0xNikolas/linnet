import SwiftUI
import Observation
import LinnetAudio
import LinnetLibrary

@MainActor
@Observable
public final class PlayerViewModel {
    var state: PlaybackState = .stopped
    var currentTrackTitle: String = "No Track Playing"
    var currentTrackArtist: String = "—"
    var currentTrackAlbum: String = ""
    var currentArtworkData: Data?
    var currentTime: Double = 0
    var duration: Double = 0
    var errorMessage: String?
    var volume: Float = 0.7 {
        didSet { Task { await audioPlayer.setVolume(volume) } }
    }
    var isPlaying: Bool { state == .playing }
    var progress: Double {
        get { duration > 0 ? currentTime / duration : 0 }
        set {
            let newTime = newValue * duration
            seek(to: newTime)
        }
    }

    private let audioPlayer = AudioPlayer()
    private let nowPlayingManager = NowPlayingManager.shared
    var queue = PlaybackQueue()
    private var queuedTracks: [Track] = []
    private var currentTrackIndex: Int = 0
    private var timeUpdateTimer: Timer?

    init() {
        setupRemoteCommands()
    }

    func play() {
        Task {
            do {
                try await audioPlayer.play()
                state = .playing
                startTimeUpdates()
            } catch {
                state = .stopped
                errorMessage = "Playback error: \(error.localizedDescription)"
            }
        }
    }

    func pause() {
        Task {
            await audioPlayer.pause()
            state = .paused
            stopTimeUpdates()
        }
    }

    func stop() {
        Task {
            await audioPlayer.stop()
            state = .stopped
            currentTime = 0
            stopTimeUpdates()
        }
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func next() {
        if let nextPath = queue.advance() {
            currentTrackIndex += 1
            if currentTrackIndex < queuedTracks.count {
                updateMetadata(for: queuedTracks[currentTrackIndex])
            }
            loadAndPlay(filePath: nextPath)
        } else {
            stop()
        }
    }

    func previous() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        if let prevPath = queue.goBack() {
            currentTrackIndex -= 1
            if currentTrackIndex >= 0, currentTrackIndex < queuedTracks.count {
                updateMetadata(for: queuedTracks[currentTrackIndex])
            }
            loadAndPlay(filePath: prevPath)
        }
    }

    func seek(to time: Double) {
        Task {
            do {
                try await audioPlayer.seek(to: time)
                currentTime = time
                updateNowPlayingInfo()
            } catch {
                errorMessage = "Seek error: \(error.localizedDescription)"
            }
        }
    }

    func playTracks(_ filePaths: [String], startingAt index: Int = 0) {
        queue = PlaybackQueue()
        queue.add(tracks: filePaths)
        for _ in 0..<index {
            _ = queue.advance()
        }
        if let current = queue.current {
            loadAndPlay(filePath: current)
        }
    }

    func playTrack(_ track: Track, queue: [Track], startingAt index: Int = 0) {
        queuedTracks = queue
        currentTrackIndex = index
        let filePaths = queue.map(\.filePath)
        self.queue = PlaybackQueue()
        self.queue.add(tracks: filePaths)
        for _ in 0..<index {
            _ = self.queue.advance()
        }
        if let current = self.queue.current {
            updateMetadata(for: queuedTracks[index])
            loadAndPlay(filePath: current)
        }
    }

    func loadAndPlay(filePath: String) {
        Task {
            do {
                let url = URL(filePath: filePath)
                try await audioPlayer.load(url: url)
                try await audioPlayer.play()
                state = .playing
                duration = await audioPlayer.duration
                currentTime = 0
                if currentTrackTitle == "No Track Playing" {
                    currentTrackTitle = url.deletingPathExtension().lastPathComponent
                }
                errorMessage = nil
                updateNowPlayingInfo()
                startTimeUpdates()
            } catch {
                state = .stopped
                errorMessage = "Could not play file: \(error.localizedDescription)"
            }
        }
    }

    private func updateMetadata(for track: Track) {
        currentTrackTitle = track.title
        currentTrackArtist = track.artist?.name ?? "Unknown Artist"
        currentTrackAlbum = track.album?.name ?? ""
        currentArtworkData = track.artworkData
        track.lastPlayed = Date()
        track.playCount += 1
    }

    // MARK: - Time Updates

    private func startTimeUpdates() {
        stopTimeUpdates()
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                self.currentTime = await self.audioPlayer.currentTime
                if self.currentTime >= self.duration && self.duration > 0 {
                    self.next()
                }
            }
        }
    }

    private func stopTimeUpdates() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
    }

    // MARK: - Now Playing

    private func updateNowPlayingInfo() {
        nowPlayingManager.update(
            title: currentTrackTitle,
            artist: currentTrackArtist == "—" ? nil : currentTrackArtist,
            album: currentTrackAlbum.isEmpty ? nil : currentTrackAlbum,
            duration: duration,
            currentTime: currentTime,
            artwork: currentArtworkData
        )
    }

    private func setupRemoteCommands() {
        nowPlayingManager.setupRemoteCommands(
            onPlay: { [weak self] in self?.play() },
            onPause: { [weak self] in self?.pause() },
            onNext: { [weak self] in self?.next() },
            onPrevious: { [weak self] in self?.previous() },
            onSeek: { [weak self] in self?.seek(to: $0) }
        )
    }

    func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
