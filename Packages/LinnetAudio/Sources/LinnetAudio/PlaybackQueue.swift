public enum RepeatMode: Sendable {
    case off
    case one
    case all
}

public struct PlaybackQueue: Sendable {
    private var tracks: [String] = []
    public private(set) var currentIndex: Int = 0
    private var history: [Int] = []
    public var repeatMode: RepeatMode = .off

    public init() {}

    public var current: String? {
        guard !tracks.isEmpty, currentIndex < tracks.count else { return nil }
        return tracks[currentIndex]
    }

    public var count: Int { tracks.count }

    public var upcoming: [String] {
        guard currentIndex + 1 < tracks.count else { return [] }
        return Array(tracks[(currentIndex + 1)...])
    }

    public mutating func add(tracks newTracks: [String]) {
        tracks.append(contentsOf: newTracks)
    }

    public mutating func advance() -> String? {
        guard !tracks.isEmpty else { return nil }

        if repeatMode == .one {
            return tracks[currentIndex]
        }

        history.append(currentIndex)

        if currentIndex + 1 < tracks.count {
            currentIndex += 1
        } else if repeatMode == .all {
            currentIndex = 0
        } else {
            return nil
        }
        return tracks[currentIndex]
    }

    public mutating func goBack() -> String? {
        guard let prevIndex = history.popLast() else { return nil }
        currentIndex = prevIndex
        return tracks[currentIndex]
    }

    public mutating func playNext(_ track: String) {
        tracks.insert(track, at: currentIndex + 1)
    }

    public mutating func playLater(_ track: String) {
        tracks.append(track)
    }

    public mutating func shuffle() {
        guard tracks.count > 1 else { return }
        var upcoming = Array(tracks[(currentIndex + 1)...])
        upcoming.shuffle()
        tracks = Array(tracks[...currentIndex]) + upcoming
    }

    public mutating func move(from source: Int, to destination: Int) {
        let adjustedSource = currentIndex + 1 + source
        let adjustedDest = currentIndex + 1 + destination
        guard adjustedSource < tracks.count, adjustedDest < tracks.count else { return }
        let item = tracks.remove(at: adjustedSource)
        tracks.insert(item, at: adjustedDest)
    }

    public mutating func clear() {
        let current = tracks.indices.contains(currentIndex) ? tracks[currentIndex] : nil
        tracks = current.map { [$0] } ?? []
        currentIndex = 0
        history = []
    }
}
