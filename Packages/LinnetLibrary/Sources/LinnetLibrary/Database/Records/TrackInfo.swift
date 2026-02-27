import Foundation
import GRDB

/// Pre-joined DTO that includes artist and album names alongside track data.
/// Avoids N+1 queries when displaying track lists.
public struct TrackInfo: Codable, Sendable, Hashable, Identifiable, FetchableRecord {
    public var id: Int64
    public var filePath: String
    public var title: String
    public var duration: Double
    public var trackNumber: Int
    public var discNumber: Int
    public var genre: String?
    public var year: Int?
    public var bitrate: Int?
    public var sampleRate: Int?
    public var channels: Int?
    public var codec: String?
    public var fileSize: Int64?
    public var mood: String?
    public var bpm: Double?
    public var energy: Double?
    public var albumId: Int64?
    public var artistId: Int64?
    public var dateAdded: Date
    public var lastPlayed: Date?
    public var playCount: Int
    public var likedStatus: Int

    // Joined fields
    public var artistName: String?
    public var albumName: String?

    /// SQL request that joins track with artist and album names.
    public static func request() -> SQLRequest<TrackInfo> {
        let sql = """
            SELECT
                track.*,
                artist.name AS artistName,
                album.name AS albumName
            FROM track
            LEFT JOIN artist ON track.artistId = artist.id
            LEFT JOIN album ON track.albumId = album.id
            """
        return SQLRequest(sql: sql)
    }
}
