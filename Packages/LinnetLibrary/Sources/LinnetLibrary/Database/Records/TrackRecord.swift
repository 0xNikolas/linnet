import Foundation
import GRDB

public struct TrackRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: Int64?
    public var filePath: String
    public var title: String
    public var duration: Double
    public var trackNumber: Int
    public var discNumber: Int
    public var genre: String?
    public var year: Int?

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
    public var albumId: Int64?
    public var artistId: Int64?

    // Timestamps & playback
    public var dateAdded: Date
    public var lastPlayed: Date?
    public var playCount: Int
    public var likedStatus: Int

    public init(
        id: Int64? = nil,
        filePath: String,
        title: String,
        duration: Double,
        trackNumber: Int,
        discNumber: Int = 1,
        genre: String? = nil,
        year: Int? = nil,
        bitrate: Int? = nil,
        sampleRate: Int? = nil,
        channels: Int? = nil,
        codec: String? = nil,
        fileSize: Int64? = nil,
        mood: String? = nil,
        bpm: Double? = nil,
        energy: Double? = nil,
        aiEmbedding: Data? = nil,
        albumId: Int64? = nil,
        artistId: Int64? = nil,
        dateAdded: Date = Date(),
        lastPlayed: Date? = nil,
        playCount: Int = 0,
        likedStatus: Int = 0
    ) {
        self.id = id
        self.filePath = filePath
        self.title = title
        self.duration = duration
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.genre = genre
        self.year = year
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.channels = channels
        self.codec = codec
        self.fileSize = fileSize
        self.mood = mood
        self.bpm = bpm
        self.energy = energy
        self.aiEmbedding = aiEmbedding
        self.albumId = albumId
        self.artistId = artistId
        self.dateAdded = dateAdded
        self.lastPlayed = lastPlayed
        self.playCount = playCount
        self.likedStatus = likedStatus
    }
}

extension TrackRecord: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "track"

    public static let album = belongsTo(AlbumRecord.self)
    public static let artist = belongsTo(ArtistRecord.self)

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
