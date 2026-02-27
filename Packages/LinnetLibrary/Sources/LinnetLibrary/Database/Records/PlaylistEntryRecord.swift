import Foundation
import GRDB

public struct PlaylistEntryRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: Int64?
    public var order: Int
    public var trackId: Int64
    public var playlistId: Int64

    public init(
        id: Int64? = nil,
        order: Int,
        trackId: Int64,
        playlistId: Int64
    ) {
        self.id = id
        self.order = order
        self.trackId = trackId
        self.playlistId = playlistId
    }
}

extension PlaylistEntryRecord: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "playlistEntry"

    public static let track = belongsTo(TrackRecord.self)
    public static let playlist = belongsTo(PlaylistRecord.self)

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
