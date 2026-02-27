import Foundation
import GRDB

/// Pre-joined DTO that includes track count alongside album data.
/// Avoids N+1 queries when displaying album lists.
public struct AlbumInfo: Codable, Sendable, Hashable, Identifiable, FetchableRecord {
    public var id: Int64
    public var name: String
    public var artistName: String?
    public var year: Int?
    public var artistId: Int64?
    public var trackCount: Int
}
