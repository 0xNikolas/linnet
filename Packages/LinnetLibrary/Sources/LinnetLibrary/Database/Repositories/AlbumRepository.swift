import Foundation
import GRDB

public struct AlbumRepository: Sendable {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    // MARK: - CRUD

    @discardableResult
    public func insert(_ album: inout AlbumRecord) throws -> AlbumRecord {
        album = try pool.write { db in
            var record = album
            try record.insert(db)
            return record
        }
        return album
    }

    public func update(_ album: AlbumRecord) throws {
        try pool.write { db in
            try album.update(db)
        }
    }

    public func delete(id: Int64) throws {
        try pool.write { db in
            _ = try AlbumRecord.deleteOne(db, id: id)
        }
    }

    // MARK: - Queries

    public func fetchOne(id: Int64) throws -> AlbumRecord? {
        try pool.read { db in
            try AlbumRecord.fetchOne(db, id: id)
        }
    }

    public func fetchByNameAndArtist(name: String, artistName: String?) throws -> AlbumRecord? {
        try pool.read { db in
            if let artistName {
                return try AlbumRecord
                    .filter(Column("name") == name && Column("artistName") == artistName)
                    .fetchOne(db)
            } else {
                return try AlbumRecord
                    .filter(Column("name") == name && Column("artistName") == nil)
                    .fetchOne(db)
            }
        }
    }

    public func fetchAll(orderedBy column: String = "name") throws -> [AlbumRecord] {
        try pool.read { db in
            try AlbumRecord.order(sql: column).fetchAll(db)
        }
    }

    public func fetchByArtist(id artistId: Int64) throws -> [AlbumRecord] {
        try pool.read { db in
            try AlbumRecord.filter(Column("artistId") == artistId).order(Column("year")).fetchAll(db)
        }
    }

    /// Find or create an album by name + artistName, returning the record with its id.
    @discardableResult
    public func findOrCreate(
        name: String,
        artistName: String?,
        year: Int?,
        artistId: Int64?
    ) throws -> AlbumRecord {
        try pool.write { db in
            let existing: AlbumRecord?
            if let artistName {
                existing = try AlbumRecord
                    .filter(Column("name") == name && Column("artistName") == artistName)
                    .fetchOne(db)
            } else {
                existing = try AlbumRecord
                    .filter(Column("name") == name && Column("artistName") == nil)
                    .fetchOne(db)
            }
            if let existing { return existing }

            var record = AlbumRecord(
                name: name,
                artistName: artistName,
                year: year,
                artistId: artistId
            )
            try record.insert(db)
            return record
        }
    }

    public func count() throws -> Int {
        try pool.read { db in
            try AlbumRecord.fetchCount(db)
        }
    }

    // MARK: - Joined queries

    public func fetchAllInfo(orderedBy ordering: String = "album.name COLLATE NOCASE", direction: String = "ASC") throws -> [AlbumInfo] {
        try pool.read { db in
            let sql = """
                SELECT
                    album.id, album.name, album.artistName, album.year, album.artistId,
                    COUNT(track.id) AS trackCount
                FROM album
                LEFT JOIN track ON track.albumId = album.id
                GROUP BY album.id
                ORDER BY \(ordering) \(direction)
                """
            return try AlbumInfo.fetchAll(db, sql: sql)
        }
    }

    public func fetchInfoByArtist(id artistId: Int64) throws -> [AlbumInfo] {
        try pool.read { db in
            let sql = """
                SELECT
                    album.id, album.name, album.artistName, album.year, album.artistId,
                    COUNT(track.id) AS trackCount
                FROM album
                LEFT JOIN track ON track.albumId = album.id
                WHERE album.artistId = ?
                GROUP BY album.id
                ORDER BY album.year DESC, album.name
                """
            return try AlbumInfo.fetchAll(db, sql: sql, arguments: [artistId])
        }
    }

    public func searchInfo(query: String) throws -> [AlbumInfo] {
        try pool.read { db in
            let pattern = "%\(query)%"
            let sql = """
                SELECT
                    album.id, album.name, album.artistName, album.year, album.artistId,
                    COUNT(track.id) AS trackCount
                FROM album
                LEFT JOIN track ON track.albumId = album.id
                WHERE album.name LIKE ? OR album.artistName LIKE ?
                GROUP BY album.id
                ORDER BY album.name
                """
            return try AlbumInfo.fetchAll(db, sql: sql, arguments: [pattern, pattern])
        }
    }

    // MARK: - Cleanup

    /// Deletes albums that have no tracks. Returns the number deleted.
    @discardableResult
    public func deleteOrphaned() throws -> Int {
        try pool.write { db in
            try db.execute(sql: """
                DELETE FROM album
                WHERE id NOT IN (SELECT DISTINCT albumId FROM track WHERE albumId IS NOT NULL)
                """)
            return db.changesCount
        }
    }
}
