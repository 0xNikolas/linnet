import SwiftUI
import SwiftData
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
        didSet { audioPlayer.setVolume(volume) }
    }
    var isPlaying: Bool { state == .playing }

    // MARK: - Equalizer

    var eqBands: [Equalizer.Band] = []
    var eqEnabled: Bool = false
    var eqPreset: Equalizer.Preset = .flat

    func setEQEnabled(_ enabled: Bool) {
        eqEnabled = enabled
        audioPlayer.equalizer.isEnabled = enabled
    }

    func setEQPreset(_ preset: Equalizer.Preset) {
        eqPreset = preset
        audioPlayer.equalizer.applyPreset(preset)
        eqBands = audioPlayer.equalizer.bands
    }

    func setEQBands(_ bands: [Equalizer.Band]) {
        eqBands = bands
        audioPlayer.equalizer.bands = bands
    }

    func setEQGain(_ gain: Float, forBandAt index: Int) {
        audioPlayer.equalizer.setGain(gain, forBandAt: index)
        eqBands = audioPlayer.equalizer.bands
    }

    var currentQueueTrack: Track? {
        guard queue.currentIndex < queuedTracks.count else { return nil }
        return queuedTracks[queue.currentIndex]
    }

    var upcomingTracks: [Track] {
        guard queue.currentIndex + 1 < queuedTracks.count else { return [] }
        return Array(queuedTracks[(queue.currentIndex + 1)...])
    }

    var queueCount: Int { queuedTracks.count }

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
    private var timeUpdateTimer: Timer?
    private var modelContext: ModelContext?

    init() {
        eqBands = audioPlayer.equalizer.bands
        setupRemoteCommands()
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func play() {
        audioPlayer.play()
        state = .playing
        nowPlayingManager.setPlaybackState(true)
        startTimeUpdates()
    }

    func pause() {
        audioPlayer.pause()
        state = .paused
        nowPlayingManager.setPlaybackState(false)
        stopTimeUpdates()
    }

    func stop() {
        audioPlayer.stop()
        state = .stopped
        currentTime = 0
        nowPlayingManager.setPlaybackState(false)
        stopTimeUpdates()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func next() {
        if let nextPath = queue.advance() {
            let index = queue.currentIndex
            if index < queuedTracks.count {
                updateMetadata(for: queuedTracks[index])
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
            let index = queue.currentIndex
            if index < queuedTracks.count {
                updateMetadata(for: queuedTracks[index])
            }
            loadAndPlay(filePath: prevPath)
        }
    }

    func seek(to time: Double) {
        audioPlayer.seek(to: time)
        currentTime = time
        updateNowPlayingInfo()
    }

    func playTracks(_ filePaths: [String], startingAt index: Int = 0) {
        queue = PlaybackQueue()
        queue.add(tracks: filePaths)
        for _ in 0..<index {
            _ = queue.advance()
        }
        queuedTracks = []
        if let current = queue.current {
            loadAndPlay(filePath: current)
        }
    }

    func playTrack(_ track: Track, queue: [Track], startingAt index: Int = 0) {
        queuedTracks = queue
        let filePaths = queue.map(\.filePath)
        self.queue = PlaybackQueue()
        self.queue.add(tracks: filePaths)
        for _ in 0..<index {
            _ = self.queue.advance()
        }
        if let current = self.queue.current {
            updateMetadata(for: queuedTracks[self.queue.currentIndex])
            loadAndPlay(filePath: current)
        }
    }

    func addNext(_ track: Track) {
        queue.playNext(track.filePath)
        queuedTracks.insert(track, at: min(queue.currentIndex + 1, queuedTracks.count))
    }

    func addLater(_ track: Track) {
        queue.playLater(track.filePath)
        queuedTracks.append(track)
    }

    func clearQueue() {
        let currentTrack = currentQueueTrack
        queue.clear()
        queuedTracks = currentTrack.map { [$0] } ?? []
    }

    func loadAndPlay(filePath: String) {
        Task {
            do {
                let url = URL(filePath: filePath)
                restoreFolderAccess(for: filePath)
                try await audioPlayer.load(url: url)
                duration = audioPlayer.duration
                currentTime = 0
                audioPlayer.play()
                state = .playing
                nowPlayingManager.setPlaybackState(true)
                if currentTrackTitle == "No Track Playing" {
                    currentTrackTitle = url.deletingPathExtension().lastPathComponent
                }
                errorMessage = nil
                updateNowPlayingInfo()
                startTimeUpdates()
            } catch {
                state = .stopped
                duration = 0
                errorMessage = error.localizedDescription
                print("[Linnet] Playback error for \(filePath): \(error)")
            }
        }
    }

    private var activeSecurityScopedURLs: [String: URL] = [:]

    private func restoreFolderAccess(for filePath: String) {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<WatchedFolder>()
        guard let folders = try? context.fetch(descriptor) else { return }

        for folder in folders {
            if filePath.hasPrefix(folder.path), activeSecurityScopedURLs[folder.path] == nil {
                if let bookmarkData = folder.bookmarkData {
                    var isStale = false
                    if let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                        if url.startAccessingSecurityScopedResource() {
                            activeSecurityScopedURLs[folder.path] = url
                        }
                        if isStale {
                            folder.bookmarkData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                            try? context.save()
                        }
                    }
                }
                break
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
        try? modelContext?.save()
    }

    // MARK: - Time Updates

    private func startTimeUpdates() {
        stopTimeUpdates()
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                self.currentTime = self.audioPlayer.currentTime
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
            onPlay: { [weak self] in Task { @MainActor in self?.play() } },
            onPause: { [weak self] in Task { @MainActor in self?.pause() } },
            onTogglePlayPause: { [weak self] in Task { @MainActor in self?.togglePlayPause() } },
            onNext: { [weak self] in Task { @MainActor in self?.next() } },
            onPrevious: { [weak self] in Task { @MainActor in self?.previous() } },
            onSeek: { [weak self] time in Task { @MainActor in self?.seek(to: time) } }
        )
    }

    func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
