import AVFoundation

public final class GaplessScheduler: @unchecked Sendable {
    private let nodes: [AVAudioPlayerNode]
    private var _activeNodeIndex: Int = 0
    private let lock = NSLock()
    public let crossfadeManager = CrossfadeManager()

    public var activeNodeIndex: Int {
        lock.lock(); defer { lock.unlock() }
        return _activeNodeIndex
    }

    public var activeNode: AVAudioPlayerNode {
        lock.lock(); defer { lock.unlock() }
        return nodes[_activeNodeIndex]
    }

    public var nextNode: AVAudioPlayerNode {
        lock.lock(); defer { lock.unlock() }
        return nodes[1 - _activeNodeIndex]
    }

    public init() {
        self.nodes = [AVAudioPlayerNode(), AVAudioPlayerNode()]
    }

    public func swap() {
        lock.lock()
        _activeNodeIndex = 1 - _activeNodeIndex
        lock.unlock()
    }

    public func transitionToNext(completion: @escaping @Sendable () -> Void) {
        let outNode = activeNode
        let inNode = nextNode

        crossfadeManager.crossfade(outNode: outNode, inNode: inNode) { [weak self] in
            self?.swap()
            completion()
        }
    }

    public func scheduleNext(file: AVAudioFile, at time: AVAudioTime?) {
        nextNode.scheduleFile(file, at: time)
    }

    public func allNodes() -> [AVAudioPlayerNode] { nodes }
}
