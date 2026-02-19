import Foundation

public struct EmbeddingResult: Sendable {
    public let filePath: String
    public let embedding: [Float]
    public let embeddingData: Data

    public init(filePath: String, embedding: [Float]) {
        self.filePath = filePath
        self.embedding = embedding
        self.embeddingData = VectorUtils.serialize(embedding)
    }
}

public actor EmbeddingGenerator {
    private let aiService: AIService
    private var isProcessing = false

    public init(aiService: AIService = .shared) {
        self.aiService = aiService
    }

    public var processing: Bool { isProcessing }

    /// Generate embeddings for a batch of audio file paths.
    /// Returns results for files that were successfully processed.
    public func generateBatch(filePaths: [String], progress: (@Sendable (Int, Int) -> Void)? = nil) async -> [EmbeddingResult] {
        guard !isProcessing else { return [] }
        isProcessing = true
        defer { isProcessing = false }

        var results: [EmbeddingResult] = []
        let total = filePaths.count

        for (index, path) in filePaths.enumerated() {
            do {
                let result = try await generate(filePath: path)
                results.append(result)
            } catch {
                // Skip files that fail — don't halt the batch
                continue
            }

            progress?(index + 1, total)
        }

        return results
    }

    /// Generate embedding for a single file using AudioFeatureExtractor.
    public func generate(filePath: String) async throws -> EmbeddingResult {
        let url = URL(filePath: filePath)
        let embedding = try await aiService.generateEmbedding(from: url)
        return EmbeddingResult(filePath: filePath, embedding: embedding)
    }
}
