import Foundation
import GRDB

// MARK: - Sort Enums

public enum SortDirection: String, Sendable, CaseIterable {
    case ascending, descending
    public var sql: String { self == .ascending ? "ASC" : "DESC" }
}

public enum TrackSortColumn: String, Sendable {
    case title, artist, album, dateAdded, duration
    public var sql: String {
        switch self {
        case .title: "track.title COLLATE NOCASE"
        case .artist: "COALESCE(artist.name, 'zzz') COLLATE NOCASE"
        case .album: "COALESCE(album.name, 'zzz') COLLATE NOCASE"
        case .dateAdded: "track.dateAdded"
        case .duration: "track.duration"
        }
    }
}

public struct TrackRepository: Sendable {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    // MARK: - CRUD

    @discardableResult
    public func insert(_ track: inout TrackRecord) throws -> TrackRecord {
        track = try pool.write { db in
            var record = track
            try record.insert(db)
            return record
        }
        return track
    }

    public func update(_ track: TrackRecord) throws {
        try pool.write { db in
            try track.update(db)
        }
    }

    public func delete(id: Int64) throws {
        try pool.write { db in
            _ = try TrackRecord.deleteOne(db, id: id)
        }
    }

    /// Bulk insert tracks in a single transaction.
    public func insertAll(_ tracks: inout [TrackRecord]) throws {
        tracks = try pool.write { db in
            var records = tracks
            for i in records.indices {
                try records[i].insert(db)
            }
            return records
        }
    }

    // MARK: - Queries

    public func fetchOne(id: Int64) throws -> TrackRecord? {
        try pool.read { db in
            try TrackRecord.fetchOne(db, id: id)
        }
    }

    public func fetchByFilePath(_ filePath: String) throws -> TrackRecord? {
        try pool.read { db in
            try TrackRecord.filter(Column("filePath") == filePath).fetchOne(db)
        }
    }

    public func fetchAll(orderedBy column: String = "title") throws -> [TrackRecord] {
        try pool.read { db in
            // Treat `column` as a quoted column identifier, not raw SQL, so it
            // can't be used as an injection vector.
            try TrackRecord.order(Column(column)).fetchAll(db)
        }
    }

    public func fetchByAlbum(id albumId: Int64) throws -> [TrackRecord] {
        try pool.read { db in
            try TrackRecord
                .filter(Column("albumId") == albumId)
                .order(Column("discNumber"), Column("trackNumber"))
                .fetchAll(db)
        }
    }

    public func fetchByArtist(id artistId: Int64) throws -> [TrackRecord] {
        try pool.read { db in
            try TrackRecord
                .filter(Column("artistId") == artistId)
                .order(Column("title"))
                .fetchAll(db)
        }
    }

    public func fetchLiked() throws -> [TrackRecord] {
        try pool.read { db in
            try TrackRecord
                .filter(Column("likedStatus") == 1)
                .order(Column("title"))
                .fetchAll(db)
        }
    }

    public func fetchRecentlyAdded(limit: Int = 50) throws -> [TrackRecord] {
        try pool.read { db in
            try TrackRecord
                .order(Column("dateAdded").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - TrackInfo (joined)

    public func fetchAllInfo(orderedBy column: TrackSortColumn = .title, direction: SortDirection = .ascending) throws -> [TrackInfo] {
        try pool.read { db in
            try TrackInfo.fetchAll(db, sql: "\(TrackInfo.baseSQL) ORDER BY \(column.sql) \(direction.sql)")
        }
    }

    public func fetchInfoByAlbum(id albumId: Int64) throws -> [TrackInfo] {
        try pool.read { db in
            try TrackInfo.fetchAll(db, sql: "\(TrackInfo.baseSQL) WHERE track.albumId = ? ORDER BY track.discNumber, track.trackNumber", arguments: [albumId])
        }
    }

    public func fetchInfoByArtist(id artistId: Int64) throws -> [TrackInfo] {
        try pool.read { db in
            try TrackInfo.fetchAll(db, sql: "\(TrackInfo.baseSQL) WHERE track.artistId = ? ORDER BY track.title", arguments: [artistId])
        }
    }

    public func fetchLikedInfo(orderedBy column: TrackSortColumn = .title, direction: SortDirection = .ascending) throws -> [TrackInfo] {
        try pool.read { db in
            try TrackInfo.fetchAll(db, sql: "\(TrackInfo.baseSQL) WHERE track.likedStatus = 1 ORDER BY \(column.sql) \(direction.sql)")
        }
    }

    public func fetchRecentlyAddedInfo(limit: Int = 50) throws -> [TrackInfo] {
        try pool.read { db in
            try TrackInfo.fetchAll(db, sql: "\(TrackInfo.baseSQL) ORDER BY track.dateAdded DESC LIMIT ?", arguments: [limit])
        }
    }

    // MARK: - FTS5 helpers

    /// Sanitize a user query for FTS5 MATCH. Returns nil if the query can't be safely used.
    private func sanitizedFTSQuery(_ query: String) -> String? {
        let tokens = query
            .components(separatedBy: .whitespaces)
            .map { $0.filter { $0.isLetter || $0.isNumber } }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    // MARK: - Full-text + LIKE search

    public func search(query: String, limit: Int = 50) throws -> [TrackInfo] {
        try searchAllInfo(query: query, limit: limit)
    }

    public func searchAllInfo(query: String, limit: Int = 200) throws -> [TrackInfo] {
        try pool.read { db in
            let likePattern = "%\(query)%"

            if let ftsQuery = sanitizedFTSQuery(query) {
                let sql = """
                    \(TrackInfo.baseFTSSQL)
                    WHERE trackFts MATCH ?
                       OR track.title LIKE ?
                       OR artist.name LIKE ?
                       OR album.name LIKE ?
                    ORDER BY track.title COLLATE NOCASE
                    LIMIT ?
                    """
                return try TrackInfo.fetchAll(db, sql: sql, arguments: [ftsQuery, likePattern, likePattern, likePattern, limit])
            } else {
                let sql = """
                    \(TrackInfo.baseSQL)
                    WHERE track.title LIKE ?
                       OR artist.name LIKE ?
                       OR album.name LIKE ?
                    ORDER BY track.title COLLATE NOCASE
                    LIMIT ?
                    """
                return try TrackInfo.fetchAll(db, sql: sql, arguments: [likePattern, likePattern, likePattern, limit])
            }
        }
    }

    // MARK: - Grouped queries with optional search

    private func searchSQL(searchQuery: String?) -> (sql: String, arguments: [any DatabaseValueConvertible]) {
        guard let query = searchQuery, !query.isEmpty else {
            return (sql: TrackInfo.baseSQL, arguments: [])
        }
        let likePattern = "%\(query)%"
        if let ftsQuery = sanitizedFTSQuery(query) {
            let sql = """
                \(TrackInfo.baseFTSSQL)
                WHERE trackFts MATCH ? OR track.title LIKE ? OR artist.name LIKE ? OR album.name LIKE ?
                """
            return (sql: sql, arguments: [ftsQuery, likePattern, likePattern, likePattern])
        } else {
            let sql = """
                \(TrackInfo.baseSQL)
                WHERE track.title LIKE ? OR artist.name LIKE ? OR album.name LIKE ?
                """
            return (sql: sql, arguments: [likePattern, likePattern, likePattern])
        }
    }

    public func fetchInfoGroupedByArtist(searchQuery: String? = nil) throws -> [(sectionName: String, tracks: [TrackInfo])] {
        try pool.read { [self] db in
            let (sql, arguments) = searchSQL(searchQuery: searchQuery)
            let fullSQL = sql + " ORDER BY COALESCE(artist.name, 'Unknown Artist') COLLATE NOCASE, track.title COLLATE NOCASE"

            let tracks = try TrackInfo.fetchAll(db, sql: fullSQL, arguments: StatementArguments(arguments))

            var sections: [(sectionName: String, tracks: [TrackInfo])] = []
            var currentKey = ""
            var currentTracks: [TrackInfo] = []

            for track in tracks {
                let key = track.artistName ?? "Unknown Artist"
                if key != currentKey {
                    if !currentTracks.isEmpty {
                        sections.append((sectionName: currentKey, tracks: currentTracks))
                    }
                    currentKey = key
                    currentTracks = [track]
                } else {
                    currentTracks.append(track)
                }
            }
            if !currentTracks.isEmpty {
                sections.append((sectionName: currentKey, tracks: currentTracks))
            }

            return sections
        }
    }

    public func fetchInfoGroupedByAlbum(searchQuery: String? = nil) throws -> [(sectionName: String, tracks: [TrackInfo])] {
        try pool.read { [self] db in
            let (sql, arguments) = searchSQL(searchQuery: searchQuery)
            let fullSQL = sql + " ORDER BY COALESCE(album.name, 'Unknown Album') COLLATE NOCASE, track.title COLLATE NOCASE"

            let tracks = try TrackInfo.fetchAll(db, sql: fullSQL, arguments: StatementArguments(arguments))

            var sections: [(sectionName: String, tracks: [TrackInfo])] = []
            var currentKey = ""
            var currentTracks: [TrackInfo] = []

            for track in tracks {
                let key = track.albumName ?? "Unknown Album"
                if key != currentKey {
                    if !currentTracks.isEmpty {
                        sections.append((sectionName: currentKey, tracks: currentTracks))
                    }
                    currentKey = key
                    currentTracks = [track]
                } else {
                    currentTracks.append(track)
                }
            }
            if !currentTracks.isEmpty {
                sections.append((sectionName: currentKey, tracks: currentTracks))
            }

            return sections
        }
    }

    public func fetchInfoGroupedByFolder(searchQuery: String? = nil) throws -> [(sectionName: String, tracks: [TrackInfo])] {
        try pool.read { [self] db in
            let (sql, arguments) = searchSQL(searchQuery: searchQuery)
            let fullSQL = sql + " ORDER BY track.filePath COLLATE NOCASE"

            let tracks = try TrackInfo.fetchAll(db, sql: fullSQL, arguments: StatementArguments(arguments))

            var sections: [(sectionName: String, tracks: [TrackInfo])] = []
            var currentKey = ""
            var currentTracks: [TrackInfo] = []

            for track in tracks {
                let url = URL(fileURLWithPath: track.filePath)
                let key = url.deletingLastPathComponent().path
                if key != currentKey {
                    if !currentTracks.isEmpty {
                        sections.append((sectionName: currentKey, tracks: currentTracks))
                    }
                    currentKey = key
                    currentTracks = [track]
                } else {
                    currentTracks.append(track)
                }
            }
            if !currentTracks.isEmpty {
                sections.append((sectionName: currentKey, tracks: currentTracks))
            }

            return sections
        }
    }

    // MARK: - Metadata updates

    public func updatePlayCount(id: Int64) throws {
        try pool.write { db in
            try db.execute(
                sql: """
                    UPDATE track
                    SET playCount = playCount + 1, lastPlayed = ?
                    WHERE id = ?
                    """,
                arguments: [Date(), id]
            )
        }
    }

    public func updateLikedStatus(id: Int64, status: Int) throws {
        try pool.write { db in
            try db.execute(
                sql: "UPDATE track SET likedStatus = ? WHERE id = ?",
                arguments: [status, id]
            )
        }
    }

    public func updatePlayCount(filePath: String) throws {
        try pool.write { db in
            try db.execute(
                sql: """
                    UPDATE track
                    SET playCount = playCount + 1, lastPlayed = ?
                    WHERE filePath = ?
                    """,
                arguments: [Date(), filePath]
            )
        }
    }

    public func updateLikedStatus(filePath: String, status: Int) throws {
        try pool.write { db in
            try db.execute(
                sql: "UPDATE track SET likedStatus = ? WHERE filePath = ?",
                arguments: [status, filePath]
            )
        }
    }

    public func fetchLikedStatus(filePath: String) throws -> Int? {
        try pool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT likedStatus FROM track WHERE filePath = ?",
                arguments: [filePath]
            )
        }
    }

    public func count() throws -> Int {
        try pool.read { db in
            try TrackRecord.fetchCount(db)
        }
    }

    /// Deletes all tracks whose filePath starts with the given prefix.
    @discardableResult
    public func deleteByFolder(pathPrefix: String) throws -> Int {
        // Escape LIKE wildcards so `%`/`_` in a real path don't match unrelated rows.
        let escaped = pathPrefix
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return try pool.write { db in
            try TrackRecord
                .filter(sql: "filePath LIKE ? ESCAPE '\\'", arguments: ["\(escaped)%"])
                .deleteAll(db)
        }
    }

    /// Deletes a track by its file path.
    @discardableResult
    public func deleteByFilePath(_ filePath: String) throws -> Bool {
        try pool.write { db in
            try TrackRecord.filter(Column("filePath") == filePath).deleteAll(db) > 0
        }
    }

    /// Returns all file paths currently in the database.
    public func allFilePaths() throws -> Set<String> {
        try pool.read { db in
            let paths = try String.fetchAll(db, sql: "SELECT filePath FROM track")
            return Set(paths)
        }
    }
}
