import Foundation
import GRDB

public enum ArtistSortColumn: String, Sendable {
    case name, albumCount
    public var sql: SortSQL {
        switch self {
        case .name: SortSQL("artist.name COLLATE NOCASE")
        case .albumCount: SortSQL("albumCount")
        }
    }
}

public struct ArtistRepository: Sendable {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    // MARK: - CRUD

    @discardableResult
    public func insert(_ artist: inout ArtistRecord) throws -> ArtistRecord {
        artist = try pool.write { db in
            var record = artist
            try record.insert(db)
            return record
        }
        return artist
    }

    public func update(_ artist: ArtistRecord) throws {
        try pool.write { db in
            try artist.update(db)
        }
    }

    public func delete(id: Int64) throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM artwork WHERE ownerType = 'artist' AND ownerId = ?", arguments: [id])
            _ = try ArtistRecord.deleteOne(db, id: id)
        }
    }

    // MARK: - Queries

    public func fetchOne(id: Int64) throws -> ArtistRecord? {
        try pool.read { db in
            try ArtistRecord.fetchOne(db, id: id)
        }
    }

    public func fetchByName(_ name: String) throws -> ArtistRecord? {
        try pool.read { db in
            try ArtistRecord.filter(Column("name") == name).fetchOne(db)
        }
    }

    public func fetchAll(orderedBy column: String = "name") throws -> [ArtistRecord] {
        try pool.read { db in
            try ArtistRecord.order(Column(column)).fetchAll(db)
        }
    }

    /// Find or create an artist by name, returning the record with its id.
    @discardableResult
    public func findOrCreate(name: String) throws -> ArtistRecord {
        try pool.write { [pool] db in
            if let existing = try ArtistRecord.filter(Column("name") == name).fetchOne(db) {
                return existing
            }
            var record = ArtistRecord(name: name)
            try record.insert(db)
            return record
        }
    }

    public func count() throws -> Int {
        try pool.read { db in
            try ArtistRecord.fetchCount(db)
        }
    }

    // MARK: - Joined queries

    public func fetchAllInfo(orderedBy column: ArtistSortColumn = .name, direction: SortDirection = .ascending) throws -> [ArtistInfo] {
        try pool.read { db in
            let sql = """
                SELECT
                    artist.id, artist.name,
                    COUNT(DISTINCT album.id) AS albumCount,
                    COUNT(DISTINCT track.id) AS trackCount
                FROM artist
                LEFT JOIN album ON album.artistId = artist.id
                LEFT JOIN track ON track.artistId = artist.id
                GROUP BY artist.id
                ORDER BY \(column.sql) \(direction.sql)
                """
            return try ArtistInfo.fetchAll(db, sql: sql)
        }
    }

    public func searchInfo(query: String) throws -> [ArtistInfo] {
        try pool.read { db in
            let pattern = "%\(query)%"
            let sql = """
                SELECT
                    artist.id, artist.name,
                    COUNT(DISTINCT album.id) AS albumCount,
                    COUNT(DISTINCT track.id) AS trackCount
                FROM artist
                LEFT JOIN album ON album.artistId = artist.id
                LEFT JOIN track ON track.artistId = artist.id
                WHERE artist.name LIKE ?
                GROUP BY artist.id
                ORDER BY artist.name
                """
            return try ArtistInfo.fetchAll(db, sql: sql, arguments: [pattern])
        }
    }

    // MARK: - Cleanup

    /// Deletes artists that have no tracks. Returns the number deleted.
    @discardableResult
    public func deleteOrphaned() throws -> Int {
        try pool.write { db in
            try db.execute(sql: """
                DELETE FROM artist
                WHERE id NOT IN (SELECT DISTINCT artistId FROM track WHERE artistId IS NOT NULL)
                """)
            let deleted = db.changesCount
            try db.execute(sql: "DELETE FROM artwork WHERE ownerType = 'artist' AND ownerId NOT IN (SELECT id FROM artist)")
            return deleted
        }
    }
}
