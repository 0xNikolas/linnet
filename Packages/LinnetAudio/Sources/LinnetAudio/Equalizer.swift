import AVFoundation

public final class Equalizer: @unchecked Sendable {

    // MARK: - Band

    public struct Band: Sendable, Codable, Identifiable {
        public var id: Float { frequency }
        public let frequency: Float
        public var gain: Float   // -12 … +12 dB

        public init(frequency: Float, gain: Float = 0) {
            self.frequency = frequency
            self.gain = gain.clamped(to: -12...12)
        }

        public var label: String {
            if frequency >= 1000 {
                return "\(Int(frequency / 1000))k"
            }
            return "\(Int(frequency))"
        }
    }

    // MARK: - Preset

    public enum Preset: String, CaseIterable, Sendable, Identifiable {
        case flat
        case bassBoost
        case trebleBoost
        case vocal
        case electronic
        case acoustic
        case lateNight
        case loudness

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .flat:        return "Flat"
            case .bassBoost:   return "Bass Boost"
            case .trebleBoost: return "Treble Boost"
            case .vocal:       return "Vocal"
            case .electronic:  return "Electronic"
            case .acoustic:    return "Acoustic"
            case .lateNight:   return "Late Night"
            case .loudness:    return "Loudness"
            }
        }

        public var gains: [Float] {
            switch self {
            //                32   64  125  250  500   1k   2k   4k   8k  16k
            case .flat:        return [ 0,  0,  0,  0,  0,  0,  0,  0,  0,  0]
            case .bassBoost:   return [ 6,  5,  4,  2,  0,  0,  0,  0,  0,  0]
            case .trebleBoost: return [ 0,  0,  0,  0,  0,  1,  2,  4,  5,  6]
            case .vocal:       return [-2, -1,  0,  2,  4,  4,  2,  0, -1, -2]
            case .electronic:  return [ 5,  4,  2,  0, -2,  0,  1,  3,  4,  5]
            case .acoustic:    return [ 3,  3,  2,  0, -1,  0,  1,  2,  3,  3]
            case .lateNight:   return [ 4,  3,  1,  0, -1, -1,  0,  1,  3,  4]
            case .loudness:    return [ 5,  4,  1,  0, -1,  0,  1,  2,  4,  5]
            }
        }
    }

    // MARK: - Constants

    public static let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    public static let bandCount = 10
    public static let minGain: Float = -12
    public static let maxGain: Float = 12

    // MARK: - State

    private let lock = NSLock()
    private var _bands: [Band]
    private var _isEnabled: Bool = true
    private weak var _eqNode: AVAudioUnitEQ?

    // MARK: - Init

    public init() {
        _bands = Self.frequencies.map { Band(frequency: $0, gain: 0) }
    }

    // MARK: - Public API

    public var bands: [Band] {
        get {
            lock.lock(); defer { lock.unlock() }
            return _bands
        }
        set {
            lock.lock()
            _bands = newValue
            let enabled = _isEnabled
            lock.unlock()
            if enabled { applyToNode() }
        }
    }

    public var isEnabled: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _isEnabled
        }
        set {
            lock.lock()
            _isEnabled = newValue
            lock.unlock()
            applyToNode()
        }
    }

    public func setGain(_ gain: Float, forBandAt index: Int) {
        lock.lock()
        guard index >= 0 && index < _bands.count else { lock.unlock(); return }
        _bands[index] = Band(frequency: _bands[index].frequency, gain: gain)
        let enabled = _isEnabled
        lock.unlock()
        if enabled { applyToNode() }
    }

    public func applyPreset(_ preset: Preset) {
        let gains = preset.gains
        lock.lock()
        for i in 0..<min(gains.count, _bands.count) {
            _bands[i] = Band(frequency: _bands[i].frequency, gain: gains[i])
        }
        lock.unlock()
        applyToNode()
    }

    // MARK: - Node binding

    /// Called by AudioPlayer to bind the EQ node.
    internal func bind(to eqNode: AVAudioUnitEQ) {
        lock.lock()
        _eqNode = eqNode
        lock.unlock()
        applyToNode()
    }

    private func applyToNode() {
        lock.lock()
        let node = _eqNode
        let currentBands = _bands
        let enabled = _isEnabled
        lock.unlock()

        guard let node else { return }
        for (i, band) in currentBands.enumerated() where i < node.bands.count {
            let eqBand = node.bands[i]
            eqBand.filterType = .parametric
            eqBand.frequency = band.frequency
            eqBand.bandwidth = 1.0
            eqBand.gain = enabled ? band.gain : 0
            eqBand.bypass = false
        }
    }
}

// MARK: - Float clamped helper

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
