import Foundation

public struct Recommendation: Sendable, Identifiable {
    public let id: String  // file path
    public let similarity: Float
    public let title: String?

    public init(id: String, similarity: Float, title: String? = nil) {
        self.id = id
        self.similarity = similarity
        self.title = title
    }
}

public struct TrackEmbeddingRef: Sendable {
    public let filePath: String
    public let embedding: [Float]
    public let title: String?

    public init(filePath: String, embedding: [Float], title: String? = nil) {
        self.filePath = filePath
        self.embedding = embedding
        self.title = title
    }
}

public enum Recommender {
    /// Find tracks similar to the given track
    public static func moreLikeThis(
        track: TrackEmbeddingRef,
        library: [TrackEmbeddingRef],
        count: Int = 10
    ) -> [Recommendation] {
        let candidates = library
            .filter { $0.filePath != track.filePath } // exclude the source track
            .map { (id: $0.filePath, embedding: $0.embedding, title: $0.title) }

        let results = VectorUtils.nearestNeighbors(
            query: track.embedding,
            candidates: candidates.map { (id: $0.id, embedding: $0.embedding) },
            k: count
        )

        return results.map { result in
            let title = candidates.first { $0.id == result.id }?.title
            return Recommendation(id: result.id, similarity: result.similarity, title: title)
        }
    }

    /// Find tracks similar to a group of tracks (e.g. "more like this playlist")
    public static func moreLikeThese(
        tracks: [TrackEmbeddingRef],
        library: [TrackEmbeddingRef],
        count: Int = 20
    ) -> [Recommendation] {
        guard !tracks.isEmpty else { return [] }

        // Average the embeddings of the source tracks
        let dim = tracks[0].embedding.count
        var averaged = [Float](repeating: 0, count: dim)

        for track in tracks {
            for i in 0..<min(dim, track.embedding.count) {
                averaged[i] += track.embedding[i]
            }
        }

        let n = Float(tracks.count)
        averaged = averaged.map { $0 / n }

        let sourceFilePaths = Set(tracks.map(\.filePath))
        let candidates = library
            .filter { !sourceFilePaths.contains($0.filePath) }
            .map { (id: $0.filePath, embedding: $0.embedding) }

        let results = VectorUtils.nearestNeighbors(
            query: averaged,
            candidates: candidates,
            k: count
        )

        return results.map { result in
            let title = library.first { $0.filePath == result.id }?.title
            return Recommendation(id: result.id, similarity: result.similarity, title: title)
        }
    }
}
