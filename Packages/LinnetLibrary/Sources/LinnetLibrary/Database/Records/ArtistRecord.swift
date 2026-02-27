import Foundation
import GRDB

public struct ArtistRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: Int64?
    public var name: String

    public init(id: Int64? = nil, name: String) {
        self.id = id
        self.name = name
    }
}

extension ArtistRecord: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "artist"

    public static let albums = hasMany(AlbumRecord.self)
    public static let tracks = hasMany(TrackRecord.self)

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
