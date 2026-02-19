import Foundation

public struct TaggingResult: Sendable {
    public let filePath: String
    public let genre: String
    public let mood: String
    public let bpm: Double
    public let energy: Double

    public init(filePath: String, genre: String, mood: String, bpm: Double, energy: Double) {
        self.filePath = filePath
        self.genre = genre
        self.mood = mood
        self.bpm = bpm
        self.energy = energy
    }
}

public actor AutoTagger {
    private let aiService: AIService
    private var isProcessing = false

    public static let supportedGenres = [
        "Rock", "Pop", "Electronic", "Hip Hop", "Jazz", "Classical",
        "R&B", "Country", "Metal", "Folk", "Blues", "Reggae",
        "Latin", "Ambient", "Punk", "Soul", "Funk", "Indie"
    ]

    public static let supportedMoods = [
        "Energetic", "Calm", "Happy", "Melancholic", "Aggressive",
        "Dreamy", "Romantic", "Dark", "Uplifting", "Chill",
        "Intense", "Peaceful", "Nostalgic", "Playful"
    ]

    public init(aiService: AIService = .shared) {
        self.aiService = aiService
    }

    public var processing: Bool { isProcessing }

    /// Tag a batch of audio files.
    public func tagBatch(filePaths: [String], progress: (@Sendable (Int, Int) -> Void)? = nil) async -> [TaggingResult] {
        guard !isProcessing else { return [] }
        isProcessing = true
        defer { isProcessing = false }

        var results: [TaggingResult] = []
        let total = filePaths.count

        for (index, path) in filePaths.enumerated() {
            do {
                let result = try await tag(filePath: path)
                results.append(result)
            } catch {
                continue
            }
            progress?(index + 1, total)
        }

        return results
    }

    /// Tag a single audio file using AudioFeatureExtractor + heuristic classification.
    public func tag(filePath: String) async throws -> TaggingResult {
        let url = URL(filePath: filePath)
        let classification = try await aiService.classifyAudio(from: url)

        return TaggingResult(
            filePath: filePath,
            genre: classification.genre,
            mood: classification.mood,
            bpm: classification.bpm,
            energy: classification.energy
        )
    }
}
