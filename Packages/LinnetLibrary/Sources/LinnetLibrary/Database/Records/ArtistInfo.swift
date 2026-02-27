import Foundation
import GRDB

/// Pre-joined DTO that includes album and track counts alongside artist data.
/// Avoids N+1 queries when displaying artist lists.
public struct ArtistInfo: Codable, Sendable, Hashable, Identifiable, FetchableRecord {
    public var id: Int64
    public var name: String
    public var albumCount: Int
    public var trackCount: Int
}
