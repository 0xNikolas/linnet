import Foundation

public struct ImageFetcher: Sendable {
    private static let userAgent = "Linnet/1.0 (https://github.com/nicklama/linnet)"
    private static let requestTimeout: TimeInterval = 20

    public init() {}

    // MARK: - Album Cover

    public func fetchAlbumCover(releaseGroupMBID: String) async -> Data? {
        let urlString = "https://coverartarchive.org/release-group/\(releaseGroupMBID)/front-500"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = Self.requestTimeout

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            return data
        } catch {
            print("[ImageFetcher] Cover Art Archive error for \(releaseGroupMBID): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Wikipedia Image

    public func fetchWikipediaImage(from wikiURL: URL) async -> Data? {
        let title: String?

        if wikiURL.host?.contains("wikidata.org") == true {
            title = await resolveWikidataToWikipediaTitle(url: wikiURL)
        } else if wikiURL.host?.contains("wikipedia.org") == true {
            title = wikiURL.pathComponents.last
        } else {
            return nil
        }

        guard let title else { return nil }

        return await fetchWikipediaPageImage(title: title)
    }

    // MARK: - Private Helpers

    private func resolveWikidataToWikipediaTitle(url: URL) async -> String? {
        guard let entityID = url.pathComponents.last, entityID.hasPrefix("Q") else {
            return nil
        }

        let apiURL = "https://www.wikidata.org/w/api.php?action=wbgetentities&ids=\(entityID)&sitefilter=enwiki&props=sitelinks&format=json"
        guard let url = URL(string: apiURL) else { return nil }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = Self.requestTimeout

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(WikidataResponse.self, from: data)
            return response.entities[entityID]?.sitelinks?["enwiki"]?.title
        } catch {
            print("[ImageFetcher] Wikidata resolve error for \(entityID): \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchWikipediaPageImage(title: String) async -> Data? {
        guard let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }

        let summaryURL = "https://en.wikipedia.org/api/rest_v1/page/summary/\(encodedTitle)"
        guard let url = URL(string: summaryURL) else { return nil }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = Self.requestTimeout

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let summary = try JSONDecoder().decode(WikipediaSummary.self, from: data)

            let imageURLString = summary.originalimage?.source ?? summary.thumbnail?.source
            guard let imageURLString, let imageURL = URL(string: imageURLString) else {
                return nil
            }

            var imageRequest = URLRequest(url: imageURL)
            imageRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            imageRequest.timeoutInterval = Self.requestTimeout

            let (imageData, imageResponse) = try await URLSession.shared.data(for: imageRequest)
            guard let httpResponse = imageResponse as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            return imageData
        } catch {
            print("[ImageFetcher] Wikipedia image error for \(title): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Response Types

    private struct WikidataResponse: Decodable, Sendable {
        let entities: [String: WikidataEntity]
    }

    private struct WikidataEntity: Decodable, Sendable {
        let sitelinks: [String: WikidataSitelink]?
    }

    private struct WikidataSitelink: Decodable, Sendable {
        let title: String
    }

    private struct WikipediaSummary: Decodable, Sendable {
        let originalimage: WikipediaImage?
        let thumbnail: WikipediaImage?
    }

    private struct WikipediaImage: Decodable, Sendable {
        let source: String
    }
}
