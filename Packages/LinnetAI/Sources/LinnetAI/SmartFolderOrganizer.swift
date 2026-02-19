import Foundation

public struct FolderSuggestion: Sendable, Identifiable {
    public let id = UUID()
    public let folderName: String
    public let trackFilePaths: [String]
    public let description: String

    public init(folderName: String, trackFilePaths: [String], description: String = "") {
        self.folderName = folderName
        self.trackFilePaths = trackFilePaths
        self.description = description
    }
}

public struct FolderOrganizationPlan: Sendable {
    public let suggestions: [FolderSuggestion]
    public let baseDirectory: String

    public init(suggestions: [FolderSuggestion], baseDirectory: String) {
        self.suggestions = suggestions
        self.baseDirectory = baseDirectory
    }

    public var totalTracks: Int {
        suggestions.reduce(0) { $0 + $1.trackFilePaths.count }
    }
}

public actor SmartFolderOrganizer {
    private let aiService: AIService

    public init(aiService: AIService = .shared) {
        self.aiService = aiService
    }

    /// Analyze library and suggest folder organization
    public func suggestOrganization(
        tracks: [TrackEmbeddingRef],
        targetFolderCount: Int = 8,
        baseDirectory: String
    ) async throws -> FolderOrganizationPlan {
        guard !tracks.isEmpty else {
            return FolderOrganizationPlan(suggestions: [], baseDirectory: baseDirectory)
        }

        // Step 1: Cluster tracks by embedding similarity using k-means
        let clusters = kMeansCluster(tracks: tracks, k: min(targetFolderCount, tracks.count))

        // Step 2: Use LLM to name each cluster based on its tracks
        var suggestions: [FolderSuggestion] = []
        for cluster in clusters {
            let trackTitles = cluster.map { $0.title ?? "Unknown" }.prefix(10).joined(separator: ", ")
            let namingPrompt = """
            Given these songs: \(trackTitles)
            Suggest a short folder name (2-4 words) that describes this group of music.
            Respond with just the folder name, nothing else.
            """

            let folderName: String
            do {
                let response = try await aiService.generateText(prompt: namingPrompt, maxTokens: 20)
                folderName = response.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                folderName = "Group \(suggestions.count + 1)"
            }

            suggestions.append(FolderSuggestion(
                folderName: folderName,
                trackFilePaths: cluster.map(\.filePath),
                description: "\(cluster.count) tracks"
            ))
        }

        return FolderOrganizationPlan(suggestions: suggestions, baseDirectory: baseDirectory)
    }

    /// Apply folder organization (move files)
    /// Returns the number of files moved
    public func applyOrganization(plan: FolderOrganizationPlan) throws -> Int {
        let fm = FileManager.default
        var moveCount = 0

        for suggestion in plan.suggestions {
            let folderURL = URL(filePath: plan.baseDirectory)
                .appendingPathComponent(suggestion.folderName)

            try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

            for filePath in suggestion.trackFilePaths {
                let sourceURL = URL(filePath: filePath)
                let destURL = folderURL.appendingPathComponent(sourceURL.lastPathComponent)

                // Don't overwrite existing files
                if !fm.fileExists(atPath: destURL.path()) {
                    try fm.moveItem(at: sourceURL, to: destURL)
                    moveCount += 1
                }
            }
        }

        return moveCount
    }

    // MARK: - Simple K-Means Clustering

    private func kMeansCluster(tracks: [TrackEmbeddingRef], k: Int, maxIterations: Int = 20) -> [[TrackEmbeddingRef]] {
        guard tracks.count >= k, let dim = tracks.first?.embedding.count else {
            return [tracks]
        }

        // Initialize centroids with random tracks
        var centroids: [[Float]] = Array(tracks.shuffled().prefix(k)).map(\.embedding)
        var assignments = [Int](repeating: 0, count: tracks.count)

        for _ in 0..<maxIterations {
            var changed = false

            // Assign each track to nearest centroid
            for i in 0..<tracks.count {
                var bestCluster = 0
                var bestSim: Float = -2

                for j in 0..<centroids.count {
                    let sim = VectorUtils.cosineSimilarity(tracks[i].embedding, centroids[j])
                    if sim > bestSim {
                        bestSim = sim
                        bestCluster = j
                    }
                }

                if assignments[i] != bestCluster {
                    assignments[i] = bestCluster
                    changed = true
                }
            }

            if !changed { break }

            // Update centroids
            for j in 0..<k {
                let members = tracks.indices.filter { assignments[$0] == j }
                if members.isEmpty { continue }

                var newCentroid = [Float](repeating: 0, count: dim)
                for idx in members {
                    for d in 0..<dim {
                        newCentroid[d] += tracks[idx].embedding[d]
                    }
                }
                let count = Float(members.count)
                newCentroid = newCentroid.map { $0 / count }
                centroids[j] = newCentroid
            }
        }

        // Group tracks by assignment
        var clusters: [[TrackEmbeddingRef]] = Array(repeating: [], count: k)
        for i in 0..<tracks.count {
            clusters[assignments[i]].append(tracks[i])
        }

        return clusters.filter { !$0.isEmpty }
    }
}
