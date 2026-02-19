import Foundation

public final class VolumeNormalizer: @unchecked Sendable {
    private var _isEnabled: Bool = false
    private var loudnessCache: [String: LoudnessResult] = [:]
    private let lock = NSLock()

    public var isEnabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _isEnabled }
        set { lock.lock(); _isEnabled = newValue; lock.unlock() }
    }

    public init() {}

    public func store(result: LoudnessResult, forPath path: String) {
        lock.lock()
        loudnessCache[path] = result
        lock.unlock()
    }

    public func gainFor(path: String) -> Float {
        lock.lock()
        let enabled = _isEnabled
        let result = loudnessCache[path]
        lock.unlock()

        guard enabled, let result else { return 1.0 }

        let gain = result.linearGain
        return min(max(gain, 0.1), 4.0)
    }

    public func clearCache() {
        lock.lock()
        loudnessCache.removeAll()
        lock.unlock()
    }
}
