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

    var currentQueueTrack: TrackInfo? {
        guard queue.currentIndex < queuedTracks.count else { return nil }
        return queuedTracks[queue.currentIndex]
    }

    var upcomingTracks: [TrackInfo] {
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
    private var queuedTracks: [TrackInfo] = []
    private var timeUpdateTimer: Timer?
    private var appDatabase: AppDatabase?

    /// Cached watched folders for security-scoped access resolution.
    private var cachedWatchedFolders: [WatchedFolderRecord] = []

    init() {
        eqBands = audioPlayer.equalizer.bands
        setupRemoteCommands()
    }

    func setAppDatabase(_ db: AppDatabase) {
        self.appDatabase = db
        refreshCachedFolders()
    }

    private func refreshCachedFolders() {
        cachedWatchedFolders = (try? appDatabase?.watchedFolders.fetchAll()) ?? []
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

    func playTrack(_ track: TrackInfo, queue: [TrackInfo], startingAt index: Int = 0) {
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

    func addNext(_ track: TrackInfo) {
        queue.playNext(track.filePath)
        queuedTracks.insert(track, at: min(queue.currentIndex + 1, queuedTracks.count))
    }

    func addLater(_ track: TrackInfo) {
        queue.playLater(track.filePath)
        queuedTracks.append(track)
    }

    func clearQueue() {
        let currentTrack = currentQueueTrack
        queue.clear()
        queuedTracks = currentTrack.map { [$0] } ?? []
    }

    var repeatMode: RepeatMode {
        queue.repeatMode
    }

    func toggleRepeatMode() {
        switch queue.repeatMode {
        case .off: queue.repeatMode = .all
        case .all: queue.repeatMode = .one
        case .one: queue.repeatMode = .off
        }
    }

    func removeFromQueue(at offsets: IndexSet) {
        for offset in offsets.sorted().reversed() {
            let trackIndex = queue.currentIndex + 1 + offset
            queue.remove(at: offset)
            if trackIndex < queuedTracks.count {
                queuedTracks.remove(at: trackIndex)
            }
        }
    }

    func moveInQueue(from source: IndexSet, to destination: Int) {
        guard let sourceIndex = source.first else { return }
        let adjustedDest = destination > sourceIndex ? destination - 1 : destination
        queue.move(from: sourceIndex, to: adjustedDest)

        let trackSource = queue.currentIndex + 1 + sourceIndex
        let trackDest = queue.currentIndex + 1 + adjustedDest
        guard trackSource < queuedTracks.count else { return }
        let track = queuedTracks.remove(at: trackSource)
        queuedTracks.insert(track, at: min(trackDest, queuedTracks.count))
    }

    func playFromQueue(at upcomingIndex: Int) {
        let targetIndex = queue.currentIndex + 1 + upcomingIndex
        guard targetIndex < queuedTracks.count else { return }
        queue.jumpTo(index: targetIndex)
        updateMetadata(for: queuedTracks[targetIndex])
        loadAndPlay(filePath: queuedTracks[targetIndex].filePath)
    }

    func toggleLike() {
        guard var track = currentQueueTrack else { return }
        let newStatus = track.likedStatus == 1 ? 0 : 1
        track.likedStatus = newStatus
        queuedTracks[queue.currentIndex] = track
        try? appDatabase?.tracks.updateLikedStatus(filePath: track.filePath, status: newStatus)
    }

    func toggleDislike() {
        guard var track = currentQueueTrack else { return }
        let newStatus = track.likedStatus == -1 ? 0 : -1
        track.likedStatus = newStatus
        queuedTracks[queue.currentIndex] = track
        try? appDatabase?.tracks.updateLikedStatus(filePath: track.filePath, status: newStatus)
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
                Log.player.error("Playback error for \(filePath): \(error)")
            }
        }
    }

    private var activeSecurityScopedURLs: [String: URL] = [:]

    private func restoreFolderAccess(for filePath: String) {
        if cachedWatchedFolders.isEmpty {
            refreshCachedFolders()
        }

        for folder in cachedWatchedFolders {
            if filePath.hasPrefix(folder.path), activeSecurityScopedURLs[folder.path] == nil {
                if let bookmarkData = folder.bookmarkData {
                    var isStale = false
                    if let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                        if url.startAccessingSecurityScopedResource() {
                            activeSecurityScopedURLs[folder.path] = url
                        }
                        if isStale {
                            if let newBookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                                var updated = folder
                                updated.bookmarkData = newBookmark
                                try? appDatabase?.watchedFolders.update(updated)
                                refreshCachedFolders()
                            }
                        }
                    }
                }
                break
            }
        }
    }

    private func updateMetadata(for track: TrackInfo) {
        currentTrackTitle = track.title
        currentTrackArtist = track.artistName ?? "Unknown Artist"
        currentTrackAlbum = track.albumName ?? ""
        // Load artwork from GRDB artwork table
        currentArtworkData = nil
        if let db = appDatabase {
            if let albumId = track.albumId {
                currentArtworkData = try? db.artwork.fetchImageData(ownerType: "album", ownerId: albumId)
            }
            if currentArtworkData == nil, let trackId = try? db.tracks.fetchByFilePath(track.filePath)?.id {
                currentArtworkData = try? db.artwork.fetchImageData(ownerType: "track", ownerId: trackId)
            }
        }
        try? appDatabase?.tracks.updatePlayCount(filePath: track.filePath)
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
