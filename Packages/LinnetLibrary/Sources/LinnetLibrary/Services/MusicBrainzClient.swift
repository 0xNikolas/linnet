import Foundation

public actor MusicBrainzClient {
    private static let baseURL = "https://musicbrainz.org/ws/2"
    private static let userAgent = "Linnet/1.0 (https://github.com/nicklama/linnet)"
    private static let scoreThreshold = 60
    private static let rateLimitInterval: TimeInterval = 1.0
    private static let requestTimeout: TimeInterval = 15
    private static let maxRetries = 2

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
        // Try structured query first
        let query = "releasegroup:\(album) AND artist:\(artist)"
        if let result = try await executeReleaseGroupSearch(query: query) {
            return result
        }

        // Fallback: normalize album name (strip suffixes like "Deluxe Edition", "Remastered", etc.)
        let normalized = Self.normalizeAlbumName(album)
        if normalized != album {
            let fallback = "releasegroup:\(normalized) AND artist:\(artist)"
            if let result = try await executeReleaseGroupSearch(query: fallback) {
                return result
            }
        }

        // Last resort: simple unstructured search
        let simple = "\(normalized) \(artist)"
        return try await executeReleaseGroupSearch(query: simple)
    }

    private func executeReleaseGroupSearch(query: String) async throws -> ReleaseGroupResult? {
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

    private static func normalizeAlbumName(_ name: String) -> String {
        var result = name
        // Remove common suffixes in parentheses/brackets
        let patterns = [
            "\\s*[\\(\\[].*(?i:deluxe|remaster|expanded|anniversary|bonus|special|edition|version|disc|explicit).*[\\)\\]]",
            "\\s*-\\s*(?i:deluxe|remaster|expanded|special).*$"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    public func searchArtist(name: String) async throws -> ArtistResult? {
        // Try structured query first
        let query = "artist:\(name)"
        if let result = try await executeArtistSearch(query: query) {
            return result
        }

        // Fallback: simple unstructured search
        return try await executeArtistSearch(query: name)
    }

    private func executeArtistSearch(query: String) async throws -> ArtistResult? {
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

    // MARK: - Rate-Limited Request with Retry

    private func performRequest(url: URL) async throws -> Data {
        var lastError: Error?

        for attempt in 0...Self.maxRetries {
            if attempt > 0 {
                // Exponential backoff: 2s, 4s
                let delay = TimeInterval(1 << attempt)
                try await Task.sleep(for: .seconds(delay))
            }

            await enforceRateLimit()

            var request = URLRequest(url: url)
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = Self.requestTimeout

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                lastRequestTime = Date()

                if let http = response as? HTTPURLResponse {
                    if (200...299).contains(http.statusCode) {
                        return data
                    }
                    // Retry on 503 (rate limited) or 5xx server errors
                    if http.statusCode == 503 || http.statusCode >= 500 {
                        lastError = URLError(.badServerResponse)
                        continue
                    }
                    // 404 or other client errors — don't retry
                    throw URLError(.badServerResponse)
                }

                return data
            } catch let error as URLError where error.code == .timedOut || error.code == .networkConnectionLost || error.code == .notConnectedToInternet {
                lastError = error
                continue
            } catch {
                throw error
            }
        }

        throw lastError ?? URLError(.badServerResponse)
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
