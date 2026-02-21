@preconcurrency import AVFoundation

public struct TrackMetadata: Sendable {
    public let title: String?
    public let artist: String?
    public let album: String?
    public let trackNumber: Int?
    public let discNumber: Int?
    public let year: Int?
    public let genre: String?
    public let duration: Double
    public let artwork: Data?

    public init(title: String?, artist: String?, album: String?, trackNumber: Int?, discNumber: Int?, year: Int?, genre: String?, duration: Double, artwork: Data?) {
        self.title = title
        self.artist = artist
        self.album = album
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.year = year
        self.genre = genre
        self.duration = duration
        self.artwork = artwork
    }
}

public actor MetadataExtractor {
    public init() {}

    public func extract(from url: URL) async throws -> TrackMetadata {
        let asset = AVURLAsset(url: url)
        let metadata = try await asset.load(.commonMetadata)
        let duration = try await asset.load(.duration).seconds

        var title: String?
        var artist: String?
        var album: String?
        let trackNumber: Int? = nil
        let discNumber: Int? = nil
        let year: Int? = nil
        let genre: String? = nil
        var artwork: Data?

        for item in metadata {
            guard let key = item.commonKey else { continue }
            switch key {
            case .commonKeyTitle: title = try await item.load(.stringValue)
            case .commonKeyArtist: artist = try await item.load(.stringValue)
            case .commonKeyAlbumName: album = try await item.load(.stringValue)
            case .commonKeyArtwork: artwork = try await item.load(.dataValue)
            default: break
            }
        }

        // Fallback title to filename
        if title == nil {
            title = url.deletingPathExtension().lastPathComponent
        }

        return TrackMetadata(
            title: title, artist: artist, album: album,
            trackNumber: trackNumber, discNumber: discNumber,
            year: year, genre: genre, duration: duration, artwork: artwork
        )
    }
}
