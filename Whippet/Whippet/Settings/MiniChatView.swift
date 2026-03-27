import SwiftUI

/// A compact inline chat control that talks to the configured AI provider.
/// Designed to fit in a settings pane; a full-size variant can be built later
/// using the same MiniChatViewModel.
struct MiniChatView: View {
    @ObservedObject var viewModel: MiniChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Message area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                        }

                        if viewModel.isLoading {
                            TypingIndicator()
                                .id("typing")
                        }
                    }
                    .padding(8)
                }
                .frame(height: 200)
                .onChange(of: viewModel.messages.count) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        if viewModel.isLoading {
                            proxy.scrollTo("typing", anchor: .bottom)
                        } else if let last = viewModel.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.isLoading) {
                    if viewModel.isLoading {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("typing", anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input row
            HStack(spacing: 6) {
                TextField("Message...", text: $viewModel.inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        viewModel.sendMessage()
                    }

                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(action: { viewModel.sendMessage() }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(.background.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            Text(message.content)
                .font(.system(size: 12))
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .textSelection(.enabled)

            if message.role != .user { Spacer(minLength: 40) }
        }
        .id(message.id)
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user: return .accentColor.opacity(0.15)
        case .assistant: return .secondary.opacity(0.1)
        case .error: return .red.opacity(0.1)
        }
    }

    private var foregroundColor: Color {
        switch message.role {
        case .user: return .primary
        case .assistant: return .primary
        case .error: return .red
        }
    }
}

// MARK: - Typing Indicator

private struct TypingIndicator: View {
    @State private var dotCount = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack {
            Text(String(repeating: ".", count: dotCount + 1))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onReceive(timer) { _ in
                    dotCount = (dotCount + 1) % 3
                }

            Spacer()
        }
    }
}
