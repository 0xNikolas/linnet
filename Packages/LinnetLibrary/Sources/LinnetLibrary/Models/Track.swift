import Foundation
import SwiftData

@Model
public final class Track {
    #Unique<Track>([\.filePath])

    public var filePath: String
    public var title: String
    public var duration: Double
    public var trackNumber: Int
    public var discNumber: Int
    public var genre: String?
    public var year: Int?
    public var artworkData: Data?

    // Audio properties
    public var bitrate: Int?
    public var sampleRate: Int?
    public var channels: Int?
    public var codec: String?
    public var fileSize: Int64?

    // AI-generated metadata
    public var mood: String?
    public var bpm: Double?
    public var energy: Double?
    public var aiEmbedding: Data?

    // Relationships
    public var album: Album?
    public var artist: Artist?

    public var dateAdded: Date
    public var lastPlayed: Date?
    public var playCount: Int
    public var likedStatus: Int = 0  // -1 = disliked, 0 = neutral, 1 = liked

    public init(
        filePath: String,
        title: String,
        duration: Double,
        trackNumber: Int,
        discNumber: Int = 1,
        genre: String? = nil,
        year: Int? = nil
    ) {
        self.filePath = filePath
        self.title = title
        self.duration = duration
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.genre = genre
        self.year = year
        self.dateAdded = Date()
        self.playCount = 0
    }
}
