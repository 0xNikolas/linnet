import Foundation

public actor MusicBrainzClient {
    private static let baseURL = "https://musicbrainz.org/ws/2"
    private static let userAgent = "Linnet/1.0 (https://github.com/nicklama/linnet)"
    private static let scoreThreshold = 80
    private static let rateLimitInterval: TimeInterval = 1.0

    private var lastRequestTime: Date?

    public init() {}

    // MARK: - Public Types

    public struct ReleaseGroupResult: Sendable {
        public let id: String
        public let title: String
        public let score: Int
    }

    public struct ArtistResult: Sendable {
        public let id: String
        public let name: String
        public let score: Int
    }

    // MARK: - Public API

    public func searchReleaseGroup(album: String, artist: String) async throws -> ReleaseGroupResult? {
        let query = "releasegroup:\(album) AND artist:\(artist)"
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        let urlString = "\(Self.baseURL)/release-group/?query=\(encodedQuery)&fmt=json&limit=5"
        guard let url = URL(string: urlString) else { return nil }

        let data = try await performRequest(url: url)
        let response = try JSONDecoder().decode(ReleaseGroupSearchResponse.self, from: data)

        return response.releaseGroups
            .first { $0.score >= Self.scoreThreshold }
            .map { ReleaseGroupResult(id: $0.id, title: $0.title, score: $0.score) }
    }

    public func searchArtist(name: String) async throws -> ArtistResult? {
        let query = "artist:\(name)"
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        let urlString = "\(Self.baseURL)/artist/?query=\(encodedQuery)&fmt=json&limit=5"
        guard let url = URL(string: urlString) else { return nil }

        let data = try await performRequest(url: url)
        let response = try JSONDecoder().decode(ArtistSearchResponse.self, from: data)

        return response.artists
            .first { $0.score >= Self.scoreThreshold }
            .map { ArtistResult(id: $0.id, name: $0.name, score: $0.score) }
    }

    public func fetchArtistWikipediaURL(mbid: String) async throws -> URL? {
        let urlString = "\(Self.baseURL)/artist/\(mbid)?inc=url-rels&fmt=json"
        guard let url = URL(string: urlString) else { return nil }

        let data = try await performRequest(url: url)
        let response = try JSONDecoder().decode(ArtistRelationsResponse.self, from: data)

        guard let relations = response.relations else { return nil }

        // Prefer Wikipedia over Wikidata
        if let wikipedia = relations.first(where: { $0.type == "wikipedia" }),
           let urlStr = wikipedia.url?.resource,
           let result = URL(string: urlStr) {
            return result
        }

        if let wikidata = relations.first(where: { $0.type == "wikidata" }),
           let urlStr = wikidata.url?.resource,
           let result = URL(string: urlStr) {
            return result
        }

        return nil
    }

    // MARK: - Rate Limiting

    private func performRequest(url: URL) async throws -> Data {
        await enforceRateLimit()

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        lastRequestTime = Date()
        return data
    }

    private func enforceRateLimit() async {
        if let last = lastRequestTime {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < Self.rateLimitInterval {
                let delay = Self.rateLimitInterval - elapsed
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    // MARK: - Response Types

    private struct ReleaseGroupSearchResponse: Decodable, Sendable {
        let releaseGroups: [ReleaseGroupEntry]

        enum CodingKeys: String, CodingKey {
            case releaseGroups = "release-groups"
        }
    }

    private struct ReleaseGroupEntry: Decodable, Sendable {
        let id: String
        let title: String
        let score: Int
    }

    private struct ArtistSearchResponse: Decodable, Sendable {
        let artists: [ArtistEntry]
    }

    private struct ArtistEntry: Decodable, Sendable {
        let id: String
        let name: String
        let score: Int
    }

    private struct ArtistRelationsResponse: Decodable, Sendable {
        let relations: [Relation]?
    }

    private struct Relation: Decodable, Sendable {
        let type: String
        let url: RelationURL?
    }

    private struct RelationURL: Decodable, Sendable {
        let resource: String
    }
}
