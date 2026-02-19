import Foundation
import Hub

public enum AIModelType: String, CaseIterable, Sendable {
    case audioEmbedding = "audio-embedding"
    case musicClassifier = "music-classifier"
    case textLLM = "text-llm"

    public var displayName: String {
        switch self {
        case .audioEmbedding: return "Audio Embedding Model"
        case .musicClassifier: return "Music Classifier"
        case .textLLM: return "Text LLM"
        }
    }

    public var description: String {
        switch self {
        case .audioEmbedding: return "Generates embeddings for audio similarity search"
        case .musicClassifier: return "Classifies genre, mood, BPM, and energy"
        case .textLLM: return "Powers natural language playlist generation"
        }
    }

    public var estimatedSizeMB: Int {
        switch self {
        case .audioEmbedding: return 0   // Uses Accelerate, no model needed
        case .musicClassifier: return 0  // Uses heuristics on AudioFeatures
        case .textLLM: return 2000
        }
    }

    /// HuggingFace model ID for types that require a download.
    /// Empty string means no download needed (uses local computation).
    public var huggingFaceModelID: String {
        switch self {
        case .audioEmbedding: return ""
        case .musicClassifier: return ""
        case .textLLM: return "mlx-community/Qwen3-1.7B-4bit"
        }
    }

    /// Whether this model type requires a HuggingFace download.
    public var requiresDownload: Bool {
        !huggingFaceModelID.isEmpty
    }
}

public enum ModelStatus: Equatable, Sendable {
    case notDownloaded
    case downloading(progress: Double)
    case ready
    case error(String)
}

public actor ModelManager {
    public static let shared = ModelManager()

    private let modelsDirectory: URL
    private var modelStatuses: [AIModelType: ModelStatus] = [:]

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.modelsDirectory = appSupport.appendingPathComponent("Linnet/Models", isDirectory: true)

        // Create models directory if needed
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        // Initialize statuses
        for model in AIModelType.allCases {
            if !model.requiresDownload {
                // Accelerate-based models are always ready
                modelStatuses[model] = .ready
            } else {
                let modelPath = modelsDirectory.appendingPathComponent(model.rawValue)
                if FileManager.default.fileExists(atPath: modelPath.path()) {
                    modelStatuses[model] = .ready
                } else {
                    modelStatuses[model] = .notDownloaded
                }
            }
        }
    }

    public func status(for model: AIModelType) -> ModelStatus {
        modelStatuses[model] ?? .notDownloaded
    }

    public func allStatuses() -> [AIModelType: ModelStatus] {
        modelStatuses
    }

    public func isReady(_ model: AIModelType) -> Bool {
        status(for: model) == .ready
    }

    public func modelPath(for model: AIModelType) -> URL {
        modelsDirectory.appendingPathComponent(model.rawValue)
    }

    public func download(model: AIModelType) async throws {
        guard model.requiresDownload else {
            // No download needed for Accelerate-based features
            modelStatuses[model] = .ready
            return
        }

        modelStatuses[model] = .downloading(progress: 0)

        let hubApi = HubApi()
        let repo = Hub.Repo(id: model.huggingFaceModelID)

        do {
            let localURL = try await hubApi.snapshot(from: repo) { progress in
                Task { @MainActor in
                    // Update progress on next actor hop
                }
                // We capture progress but can't easily call back into the actor from here.
                // The progress is reported through the Hub's own Progress object.
            }

            // Create a symlink or marker in our models directory pointing to the Hub cache
            let destination = modelPath(for: model)
            let fm = FileManager.default
            if fm.fileExists(atPath: destination.path()) {
                try fm.removeItem(at: destination)
            }
            try fm.createSymbolicLink(at: destination, withDestinationURL: localURL)

            modelStatuses[model] = .ready
        } catch {
            modelStatuses[model] = .error(error.localizedDescription)
            throw error
        }
    }

    public func deleteModel(_ model: AIModelType) throws {
        guard model.requiresDownload else { return }

        let path = modelPath(for: model)
        if FileManager.default.fileExists(atPath: path.path()) {
            try FileManager.default.removeItem(at: path)
        }
        modelStatuses[model] = .notDownloaded
    }
}
