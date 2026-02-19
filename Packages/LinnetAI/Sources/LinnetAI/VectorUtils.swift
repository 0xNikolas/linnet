import Foundation

public enum VectorUtils {
    /// Cosine similarity between two vectors
    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }
        return dotProduct / denominator
    }

    /// Find k nearest neighbors by cosine similarity
    public static func nearestNeighbors(
        query: [Float],
        candidates: [(id: String, embedding: [Float])],
        k: Int = 10
    ) -> [(id: String, similarity: Float)] {
        let scored = candidates.map { candidate in
            (id: candidate.id, similarity: cosineSimilarity(query, candidate.embedding))
        }
        return Array(scored.sorted { $0.similarity > $1.similarity }.prefix(k))
    }

    /// Serialize embedding to Data
    public static func serialize(_ embedding: [Float]) -> Data {
        embedding.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    /// Deserialize Data to embedding
    public static func deserialize(_ data: Data) -> [Float] {
        data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }
}
