import Foundation

public struct PlaylistRequest: Sendable {
    public let prompt: String
    public let maxTracks: Int
    public let library: [TrackEmbeddingRef]

    public init(prompt: String, maxTracks: Int = 25, library: [TrackEmbeddingRef]) {
        self.prompt = prompt
        self.maxTracks = maxTracks
        self.library = library
    }
}

public struct GeneratedPlaylist: Sendable {
    public let name: String
    public let description: String
    public let trackFilePaths: [String]

    public init(name: String, description: String, trackFilePaths: [String]) {
        self.name = name
        self.description = description
        self.trackFilePaths = trackFilePaths
    }
}

public actor PlaylistGenerator {
    private let aiService: AIService

    public init(aiService: AIService = .shared) {
        self.aiService = aiService
    }

    /// Generate a playlist from a natural language prompt
    public func generate(request: PlaylistRequest) async throws -> GeneratedPlaylist {
        // Step 1: Use LLM to interpret the prompt and extract intent
        let intentPrompt = """
        The user wants a playlist: "\(request.prompt)"

        Based on this request, provide:
        1. A short playlist name (3-5 words)
        2. A brief description (1 sentence)
        3. Target mood keywords (comma-separated)
        4. Target genre keywords (comma-separated)
        5. Energy level (low/medium/high)

        Format your response exactly as:
        NAME: [name]
        DESCRIPTION: [description]
        MOODS: [moods]
        GENRES: [genres]
        ENERGY: [level]
        """

        let llmResponse = try await aiService.generateText(prompt: intentPrompt, maxTokens: 200)
        let intent = parseIntent(llmResponse)

        // Step 2: Score library tracks against the intent
        // For now, use a simple keyword matching + embedding similarity approach
        let scoredTracks = scoreTracksForIntent(
            library: request.library,
            intent: intent
        )

        // Step 3: Select top tracks
        let selectedPaths = Array(
            scoredTracks
                .sorted { $0.score > $1.score }
                .prefix(request.maxTracks)
                .map(\.filePath)
        )

        return GeneratedPlaylist(
            name: intent.name ?? "AI Playlist",
            description: intent.description ?? "Generated from: \(request.prompt)",
            trackFilePaths: selectedPaths
        )
    }

    // MARK: - Private

    private struct PlaylistIntent {
        var name: String?
        var description: String?
        var moods: [String]
        var genres: [String]
        var energyLevel: String?
    }

    private func parseIntent(_ response: String) -> PlaylistIntent {
        var intent = PlaylistIntent(moods: [], genres: [])

        for line in response.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("NAME:") {
                intent.name = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("DESCRIPTION:") {
                intent.description = String(trimmed.dropFirst(12)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("MOODS:") {
                intent.moods = String(trimmed.dropFirst(6))
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            } else if trimmed.hasPrefix("GENRES:") {
                intent.genres = String(trimmed.dropFirst(7))
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            } else if trimmed.hasPrefix("ENERGY:") {
                intent.energyLevel = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces).lowercased()
            }
        }

        return intent
    }

    private struct ScoredTrack {
        let filePath: String
        let score: Float
    }

    private func scoreTracksForIntent(library: [TrackEmbeddingRef], intent: PlaylistIntent) -> [ScoredTrack] {
        // Simple scoring: check title keywords against intent moods/genres
        // Real implementation would use embeddings more heavily
        return library.map { track in
            var score: Float = 0.5 // base score

            let titleLower = (track.title ?? "").lowercased()

            // Boost if title matches mood or genre keywords
            for mood in intent.moods {
                if titleLower.contains(mood) { score += 0.3 }
            }
            for genre in intent.genres {
                if titleLower.contains(genre) { score += 0.3 }
            }

            // Add some randomness for variety
            score += Float.random(in: 0...0.2)

            return ScoredTrack(filePath: track.filePath, score: min(score, 1.0))
        }
    }
}
