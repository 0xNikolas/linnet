import Foundation
import GRDB

public struct PlaylistRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: Int64?
    public var name: String
    public var isAIGenerated: Bool
    public var createdAt: Date

    public init(
        id: Int64? = nil,
        name: String,
        isAIGenerated: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isAIGenerated = isAIGenerated
        self.createdAt = createdAt
    }
}

extension PlaylistRecord: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "playlist"

    public static let entries = hasMany(PlaylistEntryRecord.self)
    public static let tracks = hasMany(
        TrackRecord.self,
        through: entries,
        using: PlaylistEntryRecord.track
    )

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
