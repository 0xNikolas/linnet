import Foundation
import GRDB

public struct ArtworkRepository: Sendable {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    // MARK: - CRUD

    public func upsert(ownerType: String, ownerId: Int64, imageData: Data?, thumbnailData: Data?) throws {
        try pool.write { db in
            if var existing = try ArtworkRecord
                .filter(Column("ownerType") == ownerType && Column("ownerId") == ownerId)
                .fetchOne(db) {
                existing.imageData = imageData
                existing.thumbnailData = thumbnailData
                try existing.update(db)
            } else {
                var record = ArtworkRecord(
                    ownerType: ownerType,
                    ownerId: ownerId,
                    imageData: imageData,
                    thumbnailData: thumbnailData
                )
                try record.insert(db)
            }
        }
    }

    public func delete(ownerType: String, ownerId: Int64) throws {
        try pool.write { db in
            _ = try ArtworkRecord
                .filter(Column("ownerType") == ownerType && Column("ownerId") == ownerId)
                .deleteAll(db)
        }
    }

    // MARK: - Queries

    public func fetchThumbnail(ownerType: String, ownerId: Int64) throws -> Data? {
        try pool.read { db in
            try Data.fetchOne(
                db,
                sql: "SELECT thumbnailData FROM artwork WHERE ownerType = ? AND ownerId = ?",
                arguments: [ownerType, ownerId]
            )
        }
    }

    public func fetchImageData(ownerType: String, ownerId: Int64) throws -> Data? {
        try pool.read { db in
            try Data.fetchOne(
                db,
                sql: "SELECT imageData FROM artwork WHERE ownerType = ? AND ownerId = ?",
                arguments: [ownerType, ownerId]
            )
        }
    }

    public func fetch(ownerType: String, ownerId: Int64) throws -> ArtworkRecord? {
        try pool.read { db in
            try ArtworkRecord
                .filter(Column("ownerType") == ownerType && Column("ownerId") == ownerId)
                .fetchOne(db)
        }
    }

    public func hasArtwork(ownerType: String, ownerId: Int64) throws -> Bool {
        try pool.read { db in
            try ArtworkRecord
                .filter(Column("ownerType") == ownerType && Column("ownerId") == ownerId)
                .fetchCount(db) > 0
        }
    }
}
