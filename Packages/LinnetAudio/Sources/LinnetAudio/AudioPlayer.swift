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
    /// Suppresses `onTrackFinished` during seek / load to prevent queue cascade.
    private var suppressFinishCallback = false

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
        // Stop current playback; suppress the completion callback so it doesn't
        // fire onTrackFinished and cascade through the queue.
        suppressFinishCallback = true
        scheduler.activeNode.stop()
        if engine.isRunning {
            engine.stop()
        }
        suppressFinishCallback = false

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
            guard let self, !self.suppressFinishCallback else { return }
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
        scheduler.scheduleNext(file: file, at: nil)
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
        suppressFinishCallback = true
        scheduler.activeNode.stop()
        suppressFinishCallback = false
        scheduledStartFrame = 0
        // Re-schedule from start if we have a file
        if let file = currentFile {
            file.framePosition = 0
            scheduler.activeNode.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                guard let self, !self.suppressFinishCallback else { return }
                self.onTrackFinished?()
            }
        }
    }

    public func seek(to time: Double) {
        guard let file = currentFile else { return }

        let activeNode = scheduler.activeNode
        let wasPlaying = activeNode.isPlaying

        // Suppress the completion callback — stopping the node fires it
        // immediately, which would cascade through the queue.
        suppressFinishCallback = true
        activeNode.stop()
        suppressFinishCallback = false

        let targetFrame = AVAudioFramePosition(time * sampleRate)
        let clampedFrame = max(0, min(targetFrame, file.length))

        file.framePosition = clampedFrame
        let remainingFrames = AVAudioFrameCount(file.length - clampedFrame)

        guard remainingFrames > 0 else { return }

        scheduledStartFrame = clampedFrame
        activeNode.scheduleSegment(file, startingFrame: clampedFrame, frameCount: remainingFrames, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self, !self.suppressFinishCallback else { return }
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
