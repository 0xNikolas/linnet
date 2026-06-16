import AVFoundation

public final class AudioPlayer: @unchecked Sendable {
    private let engine: AVAudioEngine
    private let scheduler: GaplessScheduler
    private let eqNode: AVAudioUnitEQ
    public let equalizer: Equalizer

    private var currentFile: AVAudioFile?
    private var _duration: Double = 0
    private var _volume: Float = 0.7
    private var sampleRate: Double = 44100
    private var scheduledStartFrame: AVAudioFramePosition = 0
    /// Monotonic token identifying the currently scheduled playback. Each
    /// load / seek / stop bumps it; a completion callback carrying a stale token
    /// is ignored. This both prevents the queue from cascading on seek/load and
    /// avoids a data race — the token is read on the audio I/O thread (inside the
    /// completion handler) and written on the caller thread, all under a lock.
    private let generationLock = NSLock()
    private var _playbackGeneration: UInt64 = 0

    public var onTrackFinished: (@Sendable () -> Void)?

    public var crossfadeEnabled: Bool {
        get { scheduler.crossfadeManager.isEnabled }
        set { scheduler.crossfadeManager.isEnabled = newValue }
    }

    public var crossfadeDuration: Double {
        get { scheduler.crossfadeManager.duration }
        set { scheduler.crossfadeManager.duration = newValue }
    }

    public init() {
        engine = AVAudioEngine()
        scheduler = GaplessScheduler()
        eqNode = AVAudioUnitEQ(numberOfBands: Equalizer.bandCount)
        equalizer = Equalizer()

        for node in scheduler.allNodes() {
            engine.attach(node)
        }
        engine.attach(eqNode)

        // Initial connection with default format; reconnected per file in load()
        let mainMixer = engine.mainMixerNode
        let format = mainMixer.outputFormat(forBus: 0)
        engine.connect(scheduler.activeNode, to: eqNode, format: format)
        engine.connect(eqNode, to: mainMixer, format: format)

        mainMixer.outputVolume = _volume

        // Bind equalizer to the AVAudioUnitEQ node
        equalizer.bind(to: eqNode)
    }

    // MARK: - Playback generation

    /// Invalidates any pending completion callback and returns the token that
    /// newly scheduled audio must be tagged with.
    private func nextGeneration() -> UInt64 {
        generationLock.lock(); defer { generationLock.unlock() }
        _playbackGeneration += 1
        return _playbackGeneration
    }

    private func isCurrentGeneration(_ generation: UInt64) -> Bool {
        generationLock.lock(); defer { generationLock.unlock() }
        return _playbackGeneration == generation
    }

    // MARK: - Public API

    public var currentTime: Double {
        let node = scheduler.activeNode
        guard let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime) else {
            return 0
        }
        let frames = scheduledStartFrame + playerTime.sampleTime
        let time = Double(frames) / sampleRate
        return time.isFinite && time >= 0 ? min(time, _duration) : 0
    }

    public var duration: Double {
        return _duration
    }

    public func load(url: URL) async throws {
        // Invalidate the previous track's pending completion callback so stopping
        // the node doesn't fire onTrackFinished and cascade through the queue.
        let generation = nextGeneration()
        scheduler.activeNode.stop()
        if engine.isRunning {
            engine.stop()
        }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw NSError(
                domain: "AudioPlayer", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot open file: \(url.lastPathComponent) — \(error.localizedDescription)"]
            )
        }

        currentFile = file
        sampleRate = file.processingFormat.sampleRate
        _duration = Double(file.length) / sampleRate
        scheduledStartFrame = 0

        // Reconnect active node with the file's processing format
        let format = file.processingFormat
        let activeNode = scheduler.activeNode
        engine.disconnectNodeOutput(activeNode)
        engine.disconnectNodeOutput(eqNode)
        engine.connect(activeNode, to: eqNode, format: format)
        engine.connect(eqNode, to: engine.mainMixerNode, format: format)

        // Schedule the file with completion callback
        activeNode.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self, self.isCurrentGeneration(generation) else { return }
            self.onTrackFinished?()
        }

        // Start the engine
        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw NSError(
                domain: "AudioPlayer", code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Audio engine failed to start: \(error.localizedDescription)"]
            )
        }
    }

    public func preloadNext(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        // Forward completion so a track that finishes on the preloaded node (after
        // a gapless transition swaps it active) still advances the queue.
        scheduler.scheduleNext(file: file, at: nil) { [weak self] in
            self?.onTrackFinished?()
        }
    }

    public func play() {
        if !engine.isRunning {
            try? engine.start()
        }
        scheduler.activeNode.play()
    }

    public func pause() {
        scheduler.activeNode.pause()
    }

    public func stop() {
        // Invalidate the in-flight callback that stopping the node fires.
        let generation = nextGeneration()
        scheduler.activeNode.stop()
        scheduledStartFrame = 0
        // Re-schedule from start if we have a file
        if let file = currentFile {
            file.framePosition = 0
            scheduler.activeNode.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                guard let self, self.isCurrentGeneration(generation) else { return }
                self.onTrackFinished?()
            }
        }
    }

    public func seek(to time: Double) {
        guard let file = currentFile else { return }

        let activeNode = scheduler.activeNode
        let wasPlaying = activeNode.isPlaying

        // Invalidate the current segment's callback — stopping the node fires it
        // immediately, which would otherwise cascade through the queue.
        let generation = nextGeneration()
        activeNode.stop()

        let targetFrame = AVAudioFramePosition(time * sampleRate)
        let clampedFrame = max(0, min(targetFrame, file.length))

        file.framePosition = clampedFrame
        let remainingFrames = AVAudioFrameCount(file.length - clampedFrame)

        guard remainingFrames > 0 else {
            // Seeked to/past the end — treat as natural completion so the queue advances.
            onTrackFinished?()
            return
        }

        scheduledStartFrame = clampedFrame
        activeNode.scheduleSegment(file, startingFrame: clampedFrame, frameCount: remainingFrames, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self, self.isCurrentGeneration(generation) else { return }
            self.onTrackFinished?()
        }

        if wasPlaying {
            activeNode.play()
        }
    }

    public func setVolume(_ vol: Float) {
        _volume = vol
        engine.mainMixerNode.outputVolume = vol
    }

    public var volume: Float {
        get { _volume }
        set { setVolume(newValue) }
    }
}
