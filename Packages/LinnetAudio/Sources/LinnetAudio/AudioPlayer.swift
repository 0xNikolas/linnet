import AVFoundation
import Combine

public actor AudioPlayer {
    private var engine: AVAudioEngine
    private var playerNode: AVAudioPlayerNode
    private var eqNode: AVAudioUnitEQ
    private var audioFile: AVAudioFile?

    public private(set) var state: PlaybackState = .stopped
    public var currentTime: Double {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return 0
        }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }
    public private(set) var duration: Double = 0

    public init() {
        self.engine = AVAudioEngine()
        self.playerNode = AVAudioPlayerNode()
        self.eqNode = AVAudioUnitEQ(numberOfBands: 10)

        engine.attach(playerNode)
        engine.attach(eqNode)
        engine.connect(playerNode, to: eqNode, format: nil)
        engine.connect(eqNode, to: engine.mainMixerNode, format: nil)
    }

    public func load(url: URL) throws {
        state = .loading
        stop()

        let file = try AVAudioFile(forReading: url)
        self.audioFile = file
        self.duration = Double(file.length) / file.processingFormat.sampleRate

        playerNode.scheduleFile(file, at: nil)
        state = .stopped
    }

    public func play() throws {
        if !engine.isRunning {
            try engine.start()
        }
        playerNode.play()
        state = .playing
    }

    public func pause() {
        playerNode.pause()
        state = .paused
    }

    public func stop() {
        playerNode.stop()
        engine.stop()
        state = .stopped
    }

    public func seek(to time: Double) throws {
        guard let file = audioFile else { return }
        let sampleRate = file.processingFormat.sampleRate
        let targetFrame = AVAudioFramePosition(time * sampleRate)
        let remainingFrames = AVAudioFrameCount(file.length - targetFrame)

        playerNode.stop()
        playerNode.scheduleSegment(file, startingFrame: targetFrame, frameCount: remainingFrames, at: nil)
        if state == .playing {
            playerNode.play()
        }
    }

    public func setVolume(_ vol: Float) {
        engine.mainMixerNode.outputVolume = vol
    }

    public var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }
}
