import Foundation
import GRDB

/// Owns the DatabasePool, runs migrations, and configures SQLite pragmas.
public final class DatabaseManager: Sendable {
    public let pool: DatabasePool

    /// Creates a DatabaseManager with a persistent database file.
    public init(location: DatabaseLocation = .appSupport) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            // WAL mode for concurrent reads
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        pool = try DatabasePool(path: location.url.path, configuration: config)
        try migrate()
    }

    /// Creates a DatabaseManager with a temporary database (for testing).
    /// Uses a temp file so DatabasePool (WAL mode) works correctly.
    public init(inMemory: Bool) throws {
        precondition(inMemory)
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        let tempPath = NSTemporaryDirectory() + "linnet-test-\(UUID().uuidString).db"
        pool = try DatabasePool(path: tempPath, configuration: config)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1-create-tables") { db in
            // artist
            try db.create(table: "artist") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
            }

            // album
            try db.create(table: "album") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("artistName", .text)
                t.column("year", .integer)
                t.belongsTo("artist", onDelete: .setNull)
                t.uniqueKey(["name", "artistName"])
            }
            try db.create(indexOn: "album", columns: ["artistId"])

            // track
            try db.create(table: "track") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("filePath", .text).notNull().unique()
                t.column("title", .text).notNull()
                t.column("duration", .double).notNull()
                t.column("trackNumber", .integer).notNull()
                t.column("discNumber", .integer).notNull().defaults(to: 1)
                t.column("genre", .text)
                t.column("year", .integer)
                t.column("bitrate", .integer)
                t.column("sampleRate", .integer)
                t.column("channels", .integer)
                t.column("codec", .text)
                t.column("fileSize", .integer)
                t.column("mood", .text)
                t.column("bpm", .double)
                t.column("energy", .double)
                t.column("aiEmbedding", .blob)
                t.belongsTo("album", onDelete: .setNull)
                t.belongsTo("artist", onDelete: .setNull)
                t.column("dateAdded", .datetime).notNull()
                t.column("lastPlayed", .datetime)
                t.column("playCount", .integer).notNull().defaults(to: 0)
                t.column("likedStatus", .integer).notNull().defaults(to: 0)
            }
            try db.create(indexOn: "track", columns: ["title"])
            try db.create(indexOn: "track", columns: ["artistId"])
            try db.create(indexOn: "track", columns: ["albumId"])
            try db.create(indexOn: "track", columns: ["dateAdded"])
            try db.create(indexOn: "track", columns: ["likedStatus"])

            // artwork (separate from main records for lazy loading)
            try db.create(table: "artwork") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("ownerType", .text).notNull()
                t.column("ownerId", .integer).notNull()
                t.column("imageData", .blob)
                t.column("thumbnailData", .blob)
                t.uniqueKey(["ownerType", "ownerId"])
            }

            // playlist
            try db.create(table: "playlist") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("isAIGenerated", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
            }

            // playlistEntry
            try db.create(table: "playlistEntry") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("order", .integer).notNull()
                t.belongsTo("track", onDelete: .cascade).notNull()
                t.belongsTo("playlist", onDelete: .cascade).notNull()
            }
            try db.create(indexOn: "playlistEntry", columns: ["playlistId"])

            // watchedFolder
            try db.create(table: "watchedFolder") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("path", .text).notNull().unique()
                t.column("lastScanned", .datetime)
                t.column("isEnabled", .boolean).notNull().defaults(to: true)
                t.column("bookmarkData", .blob)
            }

            // FTS5 for fast text search
            try db.create(virtualTable: "trackFts", using: FTS5()) { t in
                t.synchronize(withTable: "track")
                t.tokenizer = .unicode61()
                t.column("title")
                t.column("genre")
            }
        }

        try migrator.migrate(pool)
    }
}
