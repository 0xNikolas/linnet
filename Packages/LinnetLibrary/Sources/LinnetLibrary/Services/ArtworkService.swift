import Foundation
import GRDB

@MainActor
@Observable
public final class ArtworkService {
    public var fanartTVAPIKey: String = ""
    public var acoustIDAPIKey: String = ""

    private let musicBrainz = MusicBrainzClient()
    private let imageFetcher = ImageFetcher()

    /// Prevents duplicate concurrent fetches for the same item.
    private var inFlightRequests: Set<String> = []

    /// Tracks items that were already attempted (success or failure) to avoid
    /// retrying on every view appear. Manual "Find Artwork" bypasses this.
    private var attemptedLookups: Set<String> = []

    /// Limits concurrent auto-fetch operations.
    private var autoFetchCount = 0
    private static let maxAutoFetches = 3

    public init() {}

    // MARK: - Album Artwork (GRDB)

    public func fetchAlbumArtwork(
        albumId: Int64,
        albumName: String,
        artistName: String?,
        db: AppDatabase,
        force: Bool = false
    ) async -> Bool {
        let key = "album:\(albumName):\(artistName ?? "")"
        guard !inFlightRequests.contains(key) else { return false }
        if !force && attemptedLookups.contains(key) { return false }
        if !force && autoFetchCount >= Self.maxAutoFetches { return false }

        guard let artistName else { return false }

        inFlightRequests.insert(key)
        if !force { autoFetchCount += 1 }
        defer {
            inFlightRequests.remove(key)
            attemptedLookups.insert(key)
            if !force { autoFetchCount -= 1 }
        }

        let imageData = await Self.lookupAlbumArtwork(
            albumName: albumName,
            artistName: artistName,
            musicBrainz: musicBrainz,
            imageFetcher: imageFetcher
        )

        guard let imageData else { return false }
        guard !Task.isCancelled else { return false }

        try? db.artwork.upsert(
            ownerType: "album",
            ownerId: albumId,
            imageData: imageData,
            thumbnailData: nil
        )
        return true
    }

    // MARK: - Artist Artwork (GRDB)

    public func fetchArtistArtwork(
        artistId: Int64,
        artistName: String,
        db: AppDatabase,
        force: Bool = false
    ) async -> Bool {
        let key = "artist:\(artistName)"
        guard !inFlightRequests.contains(key) else { return false }
        if !force && attemptedLookups.contains(key) { return false }
        if !force && autoFetchCount >= Self.maxAutoFetches { return false }

        inFlightRequests.insert(key)
        if !force { autoFetchCount += 1 }
        defer {
            inFlightRequests.remove(key)
            attemptedLookups.insert(key)
            if !force { autoFetchCount -= 1 }
        }

        let apiKey = fanartTVAPIKey

        let imageData = await Self.lookupArtistArtwork(
            artistName: artistName,
            fanartAPIKey: apiKey,
            musicBrainz: musicBrainz,
            imageFetcher: imageFetcher
        )

        guard let imageData else { return false }
        guard !Task.isCancelled else { return false }

        try? db.artwork.upsert(
            ownerType: "artist",
            ownerId: artistId,
            imageData: imageData,
            thumbnailData: nil
        )
        return true
    }

    // MARK: - Network helpers (off main actor)

    private nonisolated static func lookupAlbumArtwork(
        albumName: String,
        artistName: String,
        musicBrainz: MusicBrainzClient,
        imageFetcher: ImageFetcher
    ) async -> Data? {
        do {
            try Task.checkCancellation()
            guard let releaseGroup = try await musicBrainz.searchReleaseGroup(
                album: albumName, artist: artistName
            ) else { return nil }

            try Task.checkCancellation()
            return await imageFetcher.fetchAlbumCover(releaseGroupMBID: releaseGroup.id)
        } catch {
            return nil
        }
    }

    private nonisolated static func lookupArtistArtwork(
        artistName: String,
        fanartAPIKey: String,
        musicBrainz: MusicBrainzClient,
        imageFetcher: ImageFetcher
    ) async -> Data? {
        do {
            // Try Fanart.tv first if API key is available
            if !fanartAPIKey.isEmpty {
                if let data = try await fetchFanartTVImage(
                    artistName: artistName,
                    apiKey: fanartAPIKey,
                    musicBrainz: musicBrainz
                ) {
                    return data
                }
            }

            try Task.checkCancellation()

            // Fall back to MusicBrainz → Wikipedia
            guard let artistResult = try await musicBrainz.searchArtist(name: artistName) else {
                return nil
            }

            try Task.checkCancellation()

            guard let wikiURL = try await musicBrainz.fetchArtistWikipediaURL(
                mbid: artistResult.id
            ) else {
                return nil
            }

            try Task.checkCancellation()

            return await imageFetcher.fetchWikipediaImage(from: wikiURL)
        } catch {
            return nil
        }
    }

    // MARK: - Fanart.tv (nonisolated)

    private nonisolated static func fetchFanartTVImage(
        artistName: String,
        apiKey: String,
        musicBrainz: MusicBrainzClient
    ) async throws -> Data? {
        guard let artistResult = try await musicBrainz.searchArtist(name: artistName) else {
            return nil
        }

        let urlString = "https://webservice.fanart.tv/v3/music/\(artistResult.id)?api_key=\(apiKey)"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Linnet/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        let fanartResponse = try JSONDecoder().decode(FanartResponse.self, from: data)
        guard let firstThumb = fanartResponse.artistthumb?.first,
              let imageURL = URL(string: firstThumb.url) else {
            return nil
        }

        var imageRequest = URLRequest(url: imageURL)
        imageRequest.setValue("Linnet/1.0", forHTTPHeaderField: "User-Agent")
        imageRequest.timeoutInterval = 20

        let (imageData, imageResponse) = try await URLSession.shared.data(for: imageRequest)
        guard let imgHTTPResponse = imageResponse as? HTTPURLResponse,
              imgHTTPResponse.statusCode == 200 else {
            return nil
        }

        return imageData
    }

    // MARK: - Fanart.tv Response Types

    private struct FanartResponse: Decodable, Sendable {
        let artistthumb: [FanartImage]?
    }

    private struct FanartImage: Decodable, Sendable {
        let url: String
    }
}
