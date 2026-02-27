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

    /// Import scan results into GRDB in a single transaction.
    /// Returns the number of newly imported tracks.
    public func importResults(_ results: [ScanResult], into pool: DatabasePool) throws -> Int {
        try pool.write { db in
            // Pre-fetch existing file paths for fast duplicate check
            let existingPaths = try Set(String.fetchAll(db, sql: "SELECT filePath FROM track"))

            var importedCount = 0

            for result in results {
                let path = result.filePath
                if existingPaths.contains(path) { continue }

                let metadata = result.metadata
                let title = metadata.title ?? URL(filePath: path).deletingPathExtension().lastPathComponent
                let dur = metadata.duration

                // Check for duplicate content (same title + artist + similar duration)
                if let artistName = metadata.artist {
                    let dupCount = try Int.fetchOne(db, sql: """
                        SELECT COUNT(*) FROM track
                        JOIN artist ON track.artistId = artist.id
                        WHERE track.title = ? AND artist.name = ?
                        AND track.duration BETWEEN ? AND ?
                        """, arguments: [title, artistName, dur - 3.0, dur + 3.0]) ?? 0
                    if dupCount > 0 { continue }
                } else {
                    let dupCount = try Int.fetchOne(db, sql: """
                        SELECT COUNT(*) FROM track
                        WHERE title = ? AND artistId IS NULL
                        AND duration BETWEEN ? AND ?
                        """, arguments: [title, dur - 3.0, dur + 3.0]) ?? 0
                    if dupCount > 0 { continue }
                }

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
    }
}
