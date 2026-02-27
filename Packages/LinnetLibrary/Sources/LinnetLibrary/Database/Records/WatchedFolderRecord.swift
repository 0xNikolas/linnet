import Foundation
import GRDB

public struct WatchedFolderRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: Int64?
    public var path: String
    public var lastScanned: Date?
    public var isEnabled: Bool
    public var bookmarkData: Data?

    public init(
        id: Int64? = nil,
        path: String,
        lastScanned: Date? = nil,
        isEnabled: Bool = true,
        bookmarkData: Data? = nil
    ) {
        self.id = id
        self.path = path
        self.lastScanned = lastScanned
        self.isEnabled = isEnabled
        self.bookmarkData = bookmarkData
    }
}

extension WatchedFolderRecord: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "watchedFolder"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
