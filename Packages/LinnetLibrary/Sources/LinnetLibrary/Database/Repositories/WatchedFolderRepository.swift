import Foundation
import GRDB

public struct WatchedFolderRepository: Sendable {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    // MARK: - CRUD

    @discardableResult
    public func insert(_ folder: inout WatchedFolderRecord) throws -> WatchedFolderRecord {
        folder = try pool.write { db in
            var record = folder
            try record.insert(db)
            return record
        }
        return folder
    }

    public func update(_ folder: WatchedFolderRecord) throws {
        try pool.write { db in
            try folder.update(db)
        }
    }

    public func delete(id: Int64) throws {
        try pool.write { db in
            _ = try WatchedFolderRecord.deleteOne(db, id: id)
        }
    }

    // MARK: - Queries

    public func fetchOne(id: Int64) throws -> WatchedFolderRecord? {
        try pool.read { db in
            try WatchedFolderRecord.fetchOne(db, id: id)
        }
    }

    public func fetchByPath(_ path: String) throws -> WatchedFolderRecord? {
        try pool.read { db in
            try WatchedFolderRecord.filter(Column("path") == path).fetchOne(db)
        }
    }

    public func fetchAll() throws -> [WatchedFolderRecord] {
        try pool.read { db in
            try WatchedFolderRecord.order(Column("path")).fetchAll(db)
        }
    }

    public func fetchEnabled() throws -> [WatchedFolderRecord] {
        try pool.read { db in
            try WatchedFolderRecord
                .filter(Column("isEnabled") == true)
                .order(Column("path"))
                .fetchAll(db)
        }
    }

    public func updateLastScanned(id: Int64, date: Date = Date()) throws {
        try pool.write { db in
            try db.execute(
                sql: "UPDATE watchedFolder SET lastScanned = ? WHERE id = ?",
                arguments: [date, id]
            )
        }
    }

    public func deleteByPath(_ path: String) throws {
        try pool.write { db in
            _ = try WatchedFolderRecord.filter(Column("path") == path).deleteAll(db)
        }
    }

    public func count() throws -> Int {
        try pool.read { db in
            try WatchedFolderRecord.fetchCount(db)
        }
    }
}
