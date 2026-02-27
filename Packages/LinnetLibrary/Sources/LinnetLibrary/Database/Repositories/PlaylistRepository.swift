import Foundation
import GRDB

public struct PlaylistRepository: Sendable {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    // MARK: - Playlist CRUD

    @discardableResult
    public func insert(_ playlist: inout PlaylistRecord) throws -> PlaylistRecord {
        playlist = try pool.write { db in
            var record = playlist
            try record.insert(db)
            return record
        }
        return playlist
    }

    public func update(_ playlist: PlaylistRecord) throws {
        try pool.write { db in
            try playlist.update(db)
        }
    }

    public func delete(id: Int64) throws {
        try pool.write { db in
            _ = try PlaylistRecord.deleteOne(db, id: id)
        }
    }

    public func fetchOne(id: Int64) throws -> PlaylistRecord? {
        try pool.read { db in
            try PlaylistRecord.fetchOne(db, id: id)
        }
    }

    public func fetchAll() throws -> [PlaylistRecord] {
        try pool.read { db in
            try PlaylistRecord.order(Column("name")).fetchAll(db)
        }
    }

    public func fetchAllByCreatedAt() throws -> [PlaylistRecord] {
        try pool.read { db in
            try PlaylistRecord.order(Column("createdAt")).fetchAll(db)
        }
    }

    public func fetchAllSorted(orderedBy ordering: String = "name COLLATE NOCASE", direction: String = "ASC") throws -> [(playlist: PlaylistRecord, songCount: Int)] {
        try pool.read { db in
            let sql = """
                SELECT
                    playlist.*,
                    COUNT(playlistEntry.id) AS songCount
                FROM playlist
                LEFT JOIN playlistEntry ON playlistEntry.playlistId = playlist.id
                GROUP BY playlist.id
                ORDER BY \(ordering) \(direction)
                """
            let rows = try Row.fetchAll(db, sql: sql)
            return rows.map { row in
                let record = PlaylistRecord(
                    id: row["id"],
                    name: row["name"],
                    isAIGenerated: row["isAIGenerated"],
                    createdAt: row["createdAt"]
                )
                let count: Int = row["songCount"]
                return (playlist: record, songCount: count)
            }
        }
    }

    public func entryCount(playlistId: Int64) throws -> Int {
        try pool.read { db in
            try PlaylistEntryRecord.filter(Column("playlistId") == playlistId).fetchCount(db)
        }
    }

    // MARK: - Entries

    @discardableResult
    public func addTrack(trackId: Int64, toPlaylist playlistId: Int64) throws -> PlaylistEntryRecord {
        try pool.write { db in
            let maxOrder = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(\"order\"), -1) FROM playlistEntry WHERE playlistId = ?",
                arguments: [playlistId]
            ) ?? -1
            var entry = PlaylistEntryRecord(
                order: maxOrder + 1,
                trackId: trackId,
                playlistId: playlistId
            )
            try entry.insert(db)
            return entry
        }
    }

    public func removeEntry(id: Int64) throws {
        try pool.write { db in
            _ = try PlaylistEntryRecord.deleteOne(db, id: id)
        }
    }

    public func fetchEntries(playlistId: Int64) throws -> [PlaylistEntryRecord] {
        try pool.read { db in
            try PlaylistEntryRecord
                .filter(Column("playlistId") == playlistId)
                .order(Column("order"))
                .fetchAll(db)
        }
    }

    public func fetchTrackInfos(playlistId: Int64) throws -> [TrackInfo] {
        try pool.read { db in
            let sql = """
                SELECT
                    track.*,
                    artist.name AS artistName,
                    album.name AS albumName
                FROM playlistEntry
                JOIN track ON playlistEntry.trackId = track.id
                LEFT JOIN artist ON track.artistId = artist.id
                LEFT JOIN album ON track.albumId = album.id
                WHERE playlistEntry.playlistId = ?
                ORDER BY playlistEntry."order"
                """
            return try TrackInfo.fetchAll(db, sql: sql, arguments: [playlistId])
        }
    }

    /// Add multiple tracks to a playlist.
    public func addTracks(trackIds: [Int64], toPlaylist playlistId: Int64) throws {
        try pool.write { db in
            let maxOrder = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(\"order\"), -1) FROM playlistEntry WHERE playlistId = ?",
                arguments: [playlistId]
            ) ?? -1
            for (i, trackId) in trackIds.enumerated() {
                var entry = PlaylistEntryRecord(
                    order: maxOrder + 1 + i,
                    trackId: trackId,
                    playlistId: playlistId
                )
                try entry.insert(db)
            }
        }
    }

    /// Remove entries by track IDs from a playlist and reorder remaining.
    public func removeEntries(trackIds: Set<Int64>, fromPlaylist playlistId: Int64) throws {
        try pool.write { db in
            try db.execute(
                sql: "DELETE FROM playlistEntry WHERE playlistId = ? AND trackId IN (\(trackIds.map { "\($0)" }.joined(separator: ",")))",
                arguments: [playlistId]
            )
            // Reorder remaining
            let remaining = try PlaylistEntryRecord
                .filter(Column("playlistId") == playlistId)
                .order(Column("order"))
                .fetchAll(db)
            for (i, var entry) in remaining.enumerated() {
                if entry.order != i {
                    entry.order = i
                    try entry.update(db)
                }
            }
        }
    }

    /// Duplicate a playlist with all its entries.
    @discardableResult
    public func duplicate(playlistId: Int64, newName: String) throws -> PlaylistRecord {
        try pool.write { db in
            guard let original = try PlaylistRecord.fetchOne(db, id: playlistId) else {
                throw DatabaseError(message: "Playlist not found")
            }
            var copy = PlaylistRecord(name: newName, isAIGenerated: original.isAIGenerated)
            try copy.insert(db)
            let entries = try PlaylistEntryRecord
                .filter(Column("playlistId") == playlistId)
                .order(Column("order"))
                .fetchAll(db)
            for entry in entries {
                var newEntry = PlaylistEntryRecord(
                    order: entry.order,
                    trackId: entry.trackId,
                    playlistId: copy.id!
                )
                try newEntry.insert(db)
            }
            return copy
        }
    }

    public func search(query: String) throws -> [PlaylistRecord] {
        try pool.read { db in
            let pattern = "%\(query)%"
            return try PlaylistRecord
                .filter(Column("name").like(pattern))
                .order(Column("createdAt"))
                .fetchAll(db)
        }
    }

    public func count() throws -> Int {
        try pool.read { db in
            try PlaylistRecord.fetchCount(db)
        }
    }
}
