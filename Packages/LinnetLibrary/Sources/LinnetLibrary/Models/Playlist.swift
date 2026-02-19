import Foundation
import SwiftData

@Model
public final class Playlist {
    public var name: String
    public var isAIGenerated: Bool
    public var createdAt: Date

    @Relationship(deleteRule: .cascade)
    public var entries: [PlaylistEntry]

    public init(name: String, isAIGenerated: Bool = false) {
        self.name = name
        self.isAIGenerated = isAIGenerated
        self.createdAt = Date()
        self.entries = []
    }
}

@Model
public final class PlaylistEntry {
    public var order: Int
    public var track: Track
    public var playlist: Playlist?

    public init(track: Track, order: Int) {
        self.track = track
        self.order = order
    }
}
