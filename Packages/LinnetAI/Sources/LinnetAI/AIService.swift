import Foundation
import MLX
import MLXLLM
import MLXLMCommon

public enum AIError: Error, LocalizedError {
    case modelNotReady(AIModelType)
    case inferenceError(String)
    case invalidInput(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotReady(let model): return "\(model.displayName) is not downloaded"
        case .inferenceError(let msg): return "Inference failed: \(msg)"
        case .invalidInput(let msg): return "Invalid input: \(msg)"
        }
    }
}

public actor AIService {
    public static let shared = AIService()

    private let modelManager = ModelManager.shared
    private var loadedModels: Set<AIModelType> = []
    private var modelContainer: ModelContainer?

    private init() {}

    public var isAvailable: Bool {
        get async {
            let statuses = await modelManager.allStatuses()
            return statuses.values.contains(.ready)
        }
    }

    public func ensureModelLoaded(_ model: AIModelType) async throws {
        guard await modelManager.isReady(model) else {
            throw AIError.modelNotReady(model)
        }

        if !loadedModels.contains(model) {
            if model == .textLLM {
                try await loadLLM()
            }
            loadedModels.insert(model)
        }
    }

    private func loadLLM() async throws {
        guard modelContainer == nil else { return }
        let modelPath = await modelManager.modelPath(for: .textLLM)
        do {
            modelContainer = try await loadModelContainer(id: modelPath.path())
        } catch {
            throw AIError.inferenceError("Failed to load LLM: \(error.localizedDescription)")
        }
    }

    public func unloadModel(_ model: AIModelType) {
        loadedModels.remove(model)
        if model == .textLLM {
            modelContainer = nil
        }
    }

    public func unloadAll() {
        loadedModels.removeAll()
        modelContainer = nil
    }

    // MARK: - Embedding (Accelerate-based, no ML model)

    /// Generate an embedding vector from an audio file URL.
    public func generateEmbedding(from url: URL) async throws -> [Float] {
        try await ensureModelLoaded(.audioEmbedding)
        let features = try AudioFeatureExtractor.extract(from: url)
        return features.embedding
    }

    /// Generate an embedding vector for audio data (legacy, kept for compatibility).
    public func generateEmbedding(audioData: Data) async throws -> [Float] {
        try await ensureModelLoaded(.audioEmbedding)
        // Write data to temp file, extract features
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".wav")
        try audioData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let features = try AudioFeatureExtractor.extract(from: tempURL)
        return features.embedding
    }

    // MARK: - Classification (heuristic on AudioFeatures)

    /// Classify audio from a file URL into genre, mood, BPM, energy.
    public func classifyAudio(from url: URL) async throws -> AudioClassification {
        try await ensureModelLoaded(.musicClassifier)
        let features = try AudioFeatureExtractor.extract(from: url)
        return classifyFromFeatures(features)
    }

    /// Classify audio from raw data (legacy, kept for compatibility).
    public func classifyAudio(audioData: Data) async throws -> AudioClassification {
        try await ensureModelLoaded(.musicClassifier)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".wav")
        try audioData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let features = try AudioFeatureExtractor.extract(from: tempURL)
        return classifyFromFeatures(features)
    }

    private func classifyFromFeatures(_ features: AudioFeatures) -> AudioClassification {
        // Genre heuristic based on spectral centroid and energy
        let genre: String
        let centroid = features.spectralCentroid
        let energy = features.energy
        let zcr = features.zeroCrossingRate

        if energy > 0.7 && zcr > 0.15 {
            genre = "Metal"
        } else if energy > 0.6 && centroid > 3000 {
            genre = "Electronic"
        } else if energy > 0.5 && centroid > 2000 {
            genre = "Rock"
        } else if energy > 0.4 && zcr < 0.08 {
            genre = "Hip Hop"
        } else if centroid < 1500 && energy < 0.3 {
            genre = "Classical"
        } else if centroid < 2000 && energy < 0.4 {
            genre = "Jazz"
        } else if energy < 0.25 {
            genre = "Ambient"
        } else if centroid > 2500 {
            genre = "Pop"
        } else {
            genre = "Indie"
        }

        // Mood heuristic based on energy + centroid
        let mood: String
        if energy > 0.7 {
            mood = centroid > 2500 ? "Energetic" : "Aggressive"
        } else if energy > 0.5 {
            mood = centroid > 2000 ? "Happy" : "Intense"
        } else if energy > 0.3 {
            mood = centroid > 1500 ? "Playful" : "Nostalgic"
        } else if energy > 0.15 {
            mood = centroid > 1500 ? "Chill" : "Melancholic"
        } else {
            mood = centroid > 1000 ? "Dreamy" : "Peaceful"
        }

        return AudioClassification(
            genre: genre,
            mood: mood,
            bpm: features.estimatedBPM,
            energy: Double(energy)
        )
    }

    // MARK: - Text Generation (MLX LLM)

    /// Generate text completion from a prompt using the loaded LLM.
    public func generateText(prompt: String, maxTokens: Int = 256) async throws -> String {
        try await ensureModelLoaded(.textLLM)

        guard let container = modelContainer else {
            throw AIError.inferenceError("LLM model not loaded")
        }

        let input = try await container.prepare(input: .init(prompt: prompt))
        let params = GenerateParameters(maxTokens: maxTokens, temperature: 0.7)

        var result = ""
        let stream = try await container.generate(input: input, parameters: params)
        for await generation in stream {
            switch generation {
            case .chunk(let text):
                result += text
            default:
                break
            }
        }
        return result
    }
}

public struct AudioClassification: Sendable {
    public let genre: String
    public let mood: String
    public let bpm: Double
    public let energy: Double

    public init(genre: String, mood: String, bpm: Double, energy: Double) {
        self.genre = genre
        self.mood = mood
        self.bpm = bpm
        self.energy = energy
    }
}
