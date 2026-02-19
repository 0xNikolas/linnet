import SwiftUI
import Observation
import LinnetAI

public enum ChatMessageRole: Sendable {
    case user
    case assistant
}

public struct ChatMessage: Identifiable, Sendable {
    public let id = UUID()
    public let role: ChatMessageRole
    public let content: String
    public let timestamp: Date
    public var actions: [ChatAction]

    public init(role: ChatMessageRole, content: String, actions: [ChatAction] = []) {
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.actions = actions
    }
}

public struct ChatAction: Identifiable, Sendable {
    public let id = UUID()
    public let label: String
    public let icon: String
    public let type: ActionType

    public enum ActionType: Sendable {
        case playPlaylist([String])  // file paths
        case applyTags(String)       // file path
        case previewFolders
        case showRecommendations([String]) // file paths
    }
}

@MainActor
@Observable
public final class AIViewModel {
    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isProcessing: Bool = false
    var isAIAvailable: Bool = false

    private let aiService = AIService.shared
    private let playlistGenerator = PlaylistGenerator()
    private let recommender = Recommender.self

    init() {
        messages.append(ChatMessage(
            role: .assistant,
            content: "Hi! I'm your music AI assistant. I can help you create playlists, find similar tracks, organize your library, and more. What would you like to do?"
        ))

        Task {
            isAIAvailable = await aiService.isAvailable
        }
    }

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Add user message
        messages.append(ChatMessage(role: .user, content: text))
        inputText = ""
        isProcessing = true

        Task { @MainActor in
            let response = await processUserMessage(text)
            messages.append(response)
            isProcessing = false
        }
    }

    private func processUserMessage(_ text: String) async -> ChatMessage {
        let lowered = text.lowercased()

        // Simple intent detection
        if lowered.contains("playlist") || lowered.contains("mix") || lowered.contains("make me") {
            return await handlePlaylistRequest(text)
        } else if lowered.contains("similar") || lowered.contains("like this") || lowered.contains("recommend") {
            return ChatMessage(
                role: .assistant,
                content: "To find similar tracks, right-click on any song and select 'More Like This'. I'll use AI to find tracks with similar characteristics in your library."
            )
        } else if lowered.contains("organize") || lowered.contains("folder") || lowered.contains("sort") {
            return ChatMessage(
                role: .assistant,
                content: "I can suggest how to organize your music into folders based on genre, mood, and similarity. Would you like me to analyze your library and suggest a folder structure?",
                actions: [
                    ChatAction(label: "Analyze Library", icon: "folder.badge.gearshape", type: .previewFolders)
                ]
            )
        } else if lowered.contains("tag") || lowered.contains("genre") || lowered.contains("mood") {
            return ChatMessage(
                role: .assistant,
                content: "I can automatically tag your tracks with genre, mood, BPM, and energy level. This helps with smart playlists and recommendations. Go to Settings > AI to set up the models first."
            )
        } else {
            // General conversation
            if await !aiService.isAvailable {
                return ChatMessage(
                    role: .assistant,
                    content: "AI models aren't set up yet. Go to Settings > AI to download the required models. Once set up, I can create playlists, recommend tracks, organize folders, and auto-tag your music."
                )
            }

            do {
                let response = try await aiService.generateText(prompt: "The user said: \"\(text)\". Respond helpfully as a music assistant.", maxTokens: 200)
                return ChatMessage(role: .assistant, content: response)
            } catch {
                return ChatMessage(role: .assistant, content: "Sorry, I had trouble processing that. Could you try again?")
            }
        }
    }

    private func handlePlaylistRequest(_ text: String) async -> ChatMessage {
        if await !aiService.isAvailable {
            return ChatMessage(
                role: .assistant,
                content: "I'd love to create a playlist for you, but AI models aren't set up yet. Go to Settings > AI to download them."
            )
        }

        return ChatMessage(
            role: .assistant,
            content: "I'll create a playlist based on: \"\(text)\". Once your library is indexed with AI embeddings, I'll be able to pick the perfect tracks. For now, you can create manual playlists in the Playlists tab."
        )
    }
}
