import SwiftUI

struct AIChatView: View {
    @State private var viewModel = AIViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.accent)
                Text("AI Assistant")
                    .font(.title2.bold())
                Spacer()

                if !viewModel.isAIAvailable {
                    Label("Models not set up", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding()

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }

                        if viewModel.isProcessing {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) {
                    if let last = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input
            HStack(spacing: 12) {
                TextField("Ask me anything about your music...", text: $viewModel.inputText)
                    .textFieldStyle(.plain)
                    .onSubmit { viewModel.sendMessage() }

                Button(action: { viewModel.sendMessage() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.accent)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isProcessing)
            }
            .padding()
        }
    }
}

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundStyle(.accent)
                    .frame(width: 28, height: 28)
                    .background(.accent.opacity(0.1))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(message.content)
                    .font(.system(size: 13))
                    .textSelection(.enabled)

                if !message.actions.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(message.actions) { action in
                            Button(action: {}) {
                                Label(action.label, systemImage: action.icon)
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
            .padding(12)
            .background(message.role == .assistant ? Color.secondary.opacity(0.08) : Color.accent.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if message.role == .user {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}
