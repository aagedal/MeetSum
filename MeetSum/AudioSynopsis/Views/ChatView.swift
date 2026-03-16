//
//  ChatView.swift
//  Audio Synopsis
//
//  Main chat interface for multi-turn conversation with local LLMs
//

import SwiftUI

struct ChatView: View {
    @ObservedObject var chatManager: ChatManager
    @ObservedObject var chatStore: ChatStore
    var recording: RecordingSession?

    @State private var inputText = ""
    @State private var contextType: ChatContextType = .none
    @FocusState private var isInputFocused: Bool

    private var currentConversation: ChatConversation? {
        chatStore.selectedConversation
    }

    var body: some View {
        VStack(spacing: 0) {
            // Context bar + conversation header
            chatHeader

            Divider()

            // Messages
            messageList
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Input bar
            inputBar
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 10)
        .onAppear {
            // If no conversation selected, create one
            if chatStore.selectedConversationId == nil {
                createNewConversation()
            }
            // Sync context type from conversation
            if let conv = currentConversation {
                contextType = conv.contextType
            }
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        VStack(spacing: 8) {
            HStack {
                // Conversation picker
                if chatStore.conversations.count > 1 {
                    Menu {
                        ForEach(chatStore.conversations) { conv in
                            Button(conv.title) {
                                chatStore.selectedConversationId = conv.id
                                contextType = conv.contextType
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(currentConversation?.title ?? "Chat")
                                .font(.headline)
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                } else {
                    Text(currentConversation?.title ?? "Chat")
                        .font(.headline)
                }

                Spacer()

                Button(action: createNewConversation) {
                    Label("New Chat", systemImage: "plus.bubble")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if currentConversation != nil && !(currentConversation?.messages.isEmpty ?? true) {
                    Button(action: deleteCurrentConversation) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Delete this conversation")
                }
            }

            // Context bar (only when recording is available)
            if let recording = recording {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundColor(.blue)
                        .font(.caption)

                    Text(recording.title)
                        .font(.caption)
                        .lineLimit(1)

                    Picker("Context", selection: $contextType) {
                        ForEach(ChatContextType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 160)
                    .onChange(of: contextType) { _, newValue in
                        updateConversationContextType(newValue)
                    }

                    Spacer()
                }
                .padding(.horizontal, 4)
            }

            // Error display
            if let error = chatManager.error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button(action: { chatManager.error = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }

            // Model loading progress
            if !chatManager.modelLoadProgress.isEmpty && chatManager.isGenerating {
                HStack(spacing: 8) {
                    if chatManager.modelLoadFraction > 0 && chatManager.modelLoadFraction < 1 {
                        ProgressView(value: chatManager.modelLoadFraction)
                            .progressViewStyle(.linear)
                            .frame(width: 80)
                    }
                    Text(chatManager.modelLoadProgress)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if let conversation = currentConversation {
                        ForEach(conversation.messages) { message in
                            if message.role != .system {
                                ChatBubbleView(message: message)
                                    .id(message.id)
                            }
                        }
                    }

                    // Streaming partial response
                    if chatManager.isGenerating && !chatManager.currentResponse.isEmpty {
                        ChatBubbleView(message: ChatMessage(
                            role: .assistant,
                            content: chatManager.currentResponse
                        ))
                        .id("streaming")
                        .opacity(0.8)
                    }

                    // Generating indicator
                    if chatManager.isGenerating && chatManager.currentResponse.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Thinking...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .id("thinking")
                    }

                    // Invisible anchor for scrolling
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding()
            }
            .onChange(of: currentConversation?.messages.count) {
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: chatManager.currentResponse) {
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextEditor(text: $inputText)
                .font(.body)
                .frame(minHeight: 36, maxHeight: 120)
                .fixedSize(horizontal: false, vertical: true)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .focused($isInputFocused)
                .onSubmit {
                    // Cmd+Enter sends (regular Enter makes newline)
                }

            if chatManager.isGenerating {
                Button(action: { chatManager.cancelGeneration() }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Stop generating")
            } else {
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .blue)
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Send message (Cmd+Enter)")
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        guard var conversation = currentConversation else { return }

        // Add user message
        let userMsg = ChatMessage(role: .user, content: text)
        conversation.messages.append(userMsg)
        conversation.updatedAt = Date()

        // Auto-title on first message
        if conversation.messages.count == 1 {
            conversation.title = String(text.prefix(40)) + (text.count > 40 ? "..." : "")
        }

        chatStore.updateConversation(conversation)
        inputText = ""

        // Generate response
        Task {
            if let assistantMsg = await chatManager.sendMessage(
                conversation: conversation,
                userMessage: text,
                recording: recording
            ) {
                if var updated = chatStore.conversations.first(where: { $0.id == conversation.id }) {
                    updated.messages.append(assistantMsg)
                    updated.updatedAt = Date()
                    chatStore.updateConversation(updated)
                }
            }
        }
    }

    private func createNewConversation() {
        let conv = ChatConversation(
            recordingId: recording?.id,
            contextType: recording != nil ? .transcription : .none
        )
        chatStore.addConversation(conv)
        chatStore.selectedConversationId = conv.id
        contextType = conv.contextType
    }

    private func deleteCurrentConversation() {
        guard let conv = currentConversation else { return }
        chatStore.deleteConversation(conv)
        // Select another conversation or create new
        if let first = chatStore.conversations.first {
            chatStore.selectedConversationId = first.id
            contextType = first.contextType
        } else {
            createNewConversation()
        }
    }

    private func updateConversationContextType(_ type: ChatContextType) {
        guard var conv = currentConversation else { return }
        conv.contextType = type
        chatStore.updateConversation(conv)
    }
}
