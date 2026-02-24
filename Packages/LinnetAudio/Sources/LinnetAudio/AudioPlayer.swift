import AVFoundation

public final class AudioPlayer: @unchecked Sendable {
    private let engine: AVAudioEngine
    private let playerNode: AVAudioPlayerNode
    private let eqNode: AVAudioUnitEQ
    public let equalizer: Equalizer

    private var currentFile: AVAudioFile?
    private var _duration: Double = 0
    private var _volume: Float = 0.7
    private var sampleRate: Double = 44100
    private var scheduledStartFrame: AVAudioFramePosition = 0

    public init() {
        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        eqNode = AVAudioUnitEQ(numberOfBands: Equalizer.bandCount)
        equalizer = Equalizer()

        engine.attach(playerNode)
        engine.attach(eqNode)

        // Initial connection with default format; reconnected per file in load()
        let mainMixer = engine.mainMixerNode
        let format = mainMixer.outputFormat(forBus: 0)
        engine.connect(playerNode, to: eqNode, format: format)
        engine.connect(eqNode, to: mainMixer, format: format)

        mainMixer.outputVolume = _volume

        // Bind equalizer to the AVAudioUnitEQ node
        equalizer.bind(to: eqNode)
    }

    // MARK: - Public API

    public var currentTime: Double {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
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
        // Stop current playback
        playerNode.stop()
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

        // Reconnect nodes with the file's processing format
        let format = file.processingFormat
        engine.disconnectNodeOutput(playerNode)
        engine.disconnectNodeOutput(eqNode)
        engine.connect(playerNode, to: eqNode, format: format)
        engine.connect(eqNode, to: engine.mainMixerNode, format: format)

        // Schedule the file
        playerNode.scheduleFile(file, at: nil, completionHandler: nil)

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

    public func play() {
        if !engine.isRunning {
            try? engine.start()
        }
        playerNode.play()
    }

    public func pause() {
        playerNode.pause()
    }

    public func stop() {
        playerNode.stop()
        scheduledStartFrame = 0
        // Re-schedule from start if we have a file
        if let file = currentFile {
            file.framePosition = 0
            playerNode.scheduleFile(file, at: nil, completionHandler: nil)
        }
    }

    public func seek(to time: Double) {
        guard let file = currentFile else { return }

        let wasPlaying = playerNode.isPlaying
        playerNode.stop()

        let targetFrame = AVAudioFramePosition(time * sampleRate)
        let clampedFrame = max(0, min(targetFrame, file.length))

        file.framePosition = clampedFrame
        let remainingFrames = AVAudioFrameCount(file.length - clampedFrame)

        guard remainingFrames > 0 else { return }

        scheduledStartFrame = clampedFrame
        playerNode.scheduleSegment(file, startingFrame: clampedFrame, frameCount: remainingFrames, at: nil, completionHandler: nil)

        if wasPlaying {
            playerNode.play()
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
