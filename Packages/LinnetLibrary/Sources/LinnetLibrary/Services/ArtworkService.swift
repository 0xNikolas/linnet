import Foundation
import SwiftData

@MainActor
@Observable
public final class ArtworkService {
    public var fanartTVAPIKey: String = ""
    public var acoustIDAPIKey: String = ""

    private let musicBrainz = MusicBrainzClient()
    private let imageFetcher = ImageFetcher()
    private var inFlightRequests: Set<String> = []

    public init() {}

    // MARK: - Album Artwork

    public func fetchAlbumArtwork(for album: Album, context: ModelContext) async -> Bool {
        let key = "album:\(album.name):\(album.artistName ?? "")"
        guard !inFlightRequests.contains(key) else { return false }
        inFlightRequests.insert(key)
        defer { inFlightRequests.remove(key) }

        do {
            guard let artistName = album.artistName ?? album.artist?.name else {
                return false
            }

            guard let releaseGroup = try await musicBrainz.searchReleaseGroup(
                album: album.name,
                artist: artistName
            ) else {
                return false
            }

            guard let imageData = await imageFetcher.fetchAlbumCover(
                releaseGroupMBID: releaseGroup.id
            ) else {
                return false
            }

            album.artworkData = imageData

            // Update tracks that don't have their own artwork
            for track in album.tracks where track.artworkData == nil {
                track.artworkData = imageData
            }

            try context.save()
            return true
        } catch {
            print("[ArtworkService] Failed to fetch album artwork for '\(album.name)': \(error)")
            return false
        }
    }

    // MARK: - Artist Artwork

    public func fetchArtistArtwork(for artist: Artist, context: ModelContext) async -> Bool {
        let key = "artist:\(artist.name)"
        guard !inFlightRequests.contains(key) else { return false }
        inFlightRequests.insert(key)
        defer { inFlightRequests.remove(key) }

        do {
            // Try Fanart.tv first if API key is available
            if !fanartTVAPIKey.isEmpty {
                if let data = try await fetchFanartTVImage(artistName: artist.name) {
                    artist.artworkData = data
                    try context.save()
                    return true
                }
            }

            // Fall back to MusicBrainz → Wikipedia
            guard let artistResult = try await musicBrainz.searchArtist(name: artist.name) else {
                return false
            }

            guard let wikiURL = try await musicBrainz.fetchArtistWikipediaURL(
                mbid: artistResult.id
            ) else {
                return false
            }

            guard let imageData = await imageFetcher.fetchWikipediaImage(from: wikiURL) else {
                return false
            }

            artist.artworkData = imageData
            try context.save()
            return true
        } catch {
            print("[ArtworkService] Failed to fetch artist artwork for '\(artist.name)': \(error)")
            return false
        }
    }

    // MARK: - Fanart.tv

    private func fetchFanartTVImage(artistName: String) async throws -> Data? {
        guard let artistResult = try await musicBrainz.searchArtist(name: artistName) else {
            return nil
        }

        let urlString = "https://webservice.fanart.tv/v3/music/\(artistResult.id)?api_key=\(fanartTVAPIKey)"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Linnet/1.0", forHTTPHeaderField: "User-Agent")

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
