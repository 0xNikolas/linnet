import AVFoundation

public final class CrossfadeManager: @unchecked Sendable {
    private let lock = NSLock()
    private var _isEnabled: Bool = false
    private var _duration: Double = 3.0
    private var fadeTimer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.linnet.crossfade", qos: .userInteractive)

    public var isEnabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _isEnabled }
        set { lock.lock(); _isEnabled = newValue; lock.unlock() }
    }

    public var duration: Double {
        get { lock.lock(); defer { lock.unlock() }; return _duration }
        set { lock.lock(); _duration = newValue; lock.unlock() }
    }

    public init() {}

    public func crossfade(
        outNode: AVAudioPlayerNode,
        inNode: AVAudioPlayerNode,
        completion: @escaping @Sendable () -> Void
    ) {
        guard isEnabled else {
            outNode.stop()
            inNode.play()
            completion()
            return
        }

        let fadeDuration = duration
        inNode.volume = 0
        inNode.play()

        let steps = Int(fadeDuration * 30)
        let interval = fadeDuration / Double(steps)
        var currentStep = 0

        lock.lock()
        fadeTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            currentStep += 1
            let progress = Float(currentStep) / Float(steps)

            let fadeOut = cos(progress * .pi / 2)
            let fadeIn = sin(progress * .pi / 2)

            outNode.volume = fadeOut
            inNode.volume = fadeIn

            if currentStep >= steps {
                self?.lock.lock()
                self?.fadeTimer?.cancel()
                self?.fadeTimer = nil
                self?.lock.unlock()

                outNode.stop()
                outNode.volume = 1.0
                inNode.volume = 1.0
                completion()
            }
        }
        fadeTimer = timer
        lock.unlock()
        timer.resume()
    }

    public func cancelFade() {
        lock.lock()
        fadeTimer?.cancel()
        fadeTimer = nil
        lock.unlock()
    }
}
