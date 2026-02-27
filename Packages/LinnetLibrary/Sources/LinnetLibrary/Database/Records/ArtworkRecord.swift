import Foundation
import GRDB

public struct ArtworkRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: Int64?
    public var ownerType: String  // "track", "album", "artist"
    public var ownerId: Int64
    public var imageData: Data?
    public var thumbnailData: Data?

    public init(
        id: Int64? = nil,
        ownerType: String,
        ownerId: Int64,
        imageData: Data? = nil,
        thumbnailData: Data? = nil
    ) {
        self.id = id
        self.ownerType = ownerType
        self.ownerId = ownerId
        self.imageData = imageData
        self.thumbnailData = thumbnailData
    }
}

extension ArtworkRecord: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "artwork"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
