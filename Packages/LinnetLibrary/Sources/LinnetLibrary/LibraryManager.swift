import Foundation
import GRDB

public struct ScanResult: Sendable {
    public let filePath: String
    public let metadata: TrackMetadata

    public init(filePath: String, metadata: TrackMetadata) {
        self.filePath = filePath
        self.metadata = metadata
    }
}

public actor LibraryManager {
    private let scanner: FolderScanner
    private let extractor: MetadataExtractor

    public init() {
        self.scanner = FolderScanner()
        self.extractor = MetadataExtractor()
    }

    /// Scan a folder and extract metadata for all audio files.
    /// Returns results for the caller to persist via SwiftData on @MainActor.
    public func scanFolder(url: URL) async throws -> [ScanResult] {
        let audioFiles = try await scanner.scan(folder: url)
        var results: [ScanResult] = []

        for fileURL in audioFiles {
            let metadata = try await extractor.extract(from: fileURL)
            results.append(ScanResult(filePath: fileURL.path, metadata: metadata))
        }

        return results
    }

    /// Import scan results into GRDB in batched transactions.
    /// Processes in chunks of 500 to avoid locking the database for too long.
    /// Returns the number of newly imported tracks.
    public func importResults(_ results: [ScanResult], into pool: DatabasePool, chunkSize: Int = 500) throws -> Int {
        // Build dedup indexes once: existing file paths, and a content index of
        // (title, artist) -> durations for near-duplicate detection.
        var seenPaths = try pool.read { db in
            try Set(String.fetchAll(db, sql: "SELECT filePath FROM track"))
        }
        var contentIndex: [String: [Double]] = try pool.read { db in
            var index: [String: [Double]] = [:]
            let rows = try Row.fetchAll(db, sql: """
                SELECT track.title AS t, COALESCE(artist.name, '') AS a, track.duration AS d
                FROM track LEFT JOIN artist ON track.artistId = artist.id
                """)
            for row in rows {
                let title: String = row["t"] ?? ""
                let artist: String = row["a"] ?? ""
                let duration: Double = row["d"] ?? 0
                index[Self.contentKey(title: title, artist: artist), default: []].append(duration)
            }
            return index
        }

        // Pre-filter duplicates (by path and by near-identical content), including
        // duplicates within this same import run — in memory, no per-track queries.
        var toImport: [ScanResult] = []
        for result in results {
            let path = result.filePath
            if seenPaths.contains(path) { continue }
            let title = result.metadata.title ?? URL(filePath: path).deletingPathExtension().lastPathComponent
            let dur = result.metadata.duration
            let key = Self.contentKey(title: title, artist: result.metadata.artist ?? "")
            if let durations = contentIndex[key], durations.contains(where: { abs($0 - dur) <= 3.0 }) {
                continue
            }
            toImport.append(result)
            seenPaths.insert(path)
            contentIndex[key, default: []].append(dur)
        }

        var totalImported = 0

        for chunk in toImport.chunked(into: chunkSize) {
            let chunkCount = try pool.write { db in
                var importedCount = 0

                for result in chunk {
                    let path = result.filePath
                    let metadata = result.metadata
                    let title = metadata.title ?? URL(filePath: path).deletingPathExtension().lastPathComponent
                    let dur = metadata.duration

                    // Find or create artist
                    var artistId: Int64?
                    if let artistName = metadata.artist {
                        if let existing = try ArtistRecord.filter(Column("name") == artistName).fetchOne(db) {
                            artistId = existing.id
                        } else {
                            var artist = ArtistRecord(name: artistName)
                            try artist.insert(db)
                            artistId = artist.id
                        }
                    }

                    // Find or create album
                    var albumId: Int64?
                    if let albumName = metadata.album {
                        let existing: AlbumRecord?
                        if let artName = metadata.artist {
                            existing = try AlbumRecord
                                .filter(Column("name") == albumName && Column("artistName") == artName)
                                .fetchOne(db)
                        } else {
                            existing = try AlbumRecord
                                .filter(Column("name") == albumName && Column("artistName") == nil)
                                .fetchOne(db)
                        }

                        if let existing {
                            albumId = existing.id
                        } else {
                            var album = AlbumRecord(
                                name: albumName,
                                artistName: metadata.artist,
                                year: metadata.year,
                                artistId: artistId
                            )
                            try album.insert(db)
                            albumId = album.id

                            // Store album artwork if available
                            if let artData = metadata.artwork {
                                var artwork = ArtworkRecord(
                                    ownerType: "album",
                                    ownerId: albumId!,
                                    imageData: artData
                                )
                                try artwork.insert(db)
                            }
                        }
                    }

                    // Create track
                    var track = TrackRecord(
                        filePath: path,
                        title: title,
                        duration: dur,
                        trackNumber: metadata.trackNumber ?? 0,
                        discNumber: metadata.discNumber ?? 1,
                        genre: metadata.genre,
                        year: metadata.year,
                        bitrate: metadata.bitrate,
                        sampleRate: metadata.sampleRate,
                        channels: metadata.channels,
                        codec: metadata.codec,
                        fileSize: metadata.fileSize,
                        albumId: albumId,
                        artistId: artistId
                    )
                    try track.insert(db)

                    // Store track artwork if present and different from album artwork
                    if let artData = metadata.artwork, albumId == nil {
                        var artwork = ArtworkRecord(
                            ownerType: "track",
                            ownerId: track.id!,
                            imageData: artData
                        )
                        try artwork.insert(db)
                    }

                    importedCount += 1
                }

                return importedCount
            }
            totalImported += chunkCount
        }

        return totalImported
    }

    /// Key for near-duplicate content detection: exact title + artist (empty for none).
    private static func contentKey(title: String, artist: String) -> String {
        "\(title)\u{1}\(artist)"
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
