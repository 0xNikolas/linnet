import Foundation
import GRDB

public struct AlbumRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: Int64?
    public var name: String
    public var artistName: String?
    public var year: Int?
    public var artistId: Int64?

    public init(
        id: Int64? = nil,
        name: String,
        artistName: String? = nil,
        year: Int? = nil,
        artistId: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.artistName = artistName
        self.year = year
        self.artistId = artistId
    }
}

extension AlbumRecord: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "album"

    public static let artist = belongsTo(ArtistRecord.self)
    public static let tracks = hasMany(TrackRecord.self)

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
