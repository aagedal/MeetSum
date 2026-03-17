//
//  ChatManager.swift
//  Audio Synopsis
//
//  Orchestrates chat with local LLMs (MLX or GGUF, one at a time)
//

import Foundation
import Combine
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Manages multi-turn chat with local LLMs
@MainActor
class ChatManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isGenerating = false
    @Published var currentResponse = ""
    @Published var error: Error?
    @Published var isModelLoaded = false
    @Published var modelLoadProgress = ""
    @Published var modelLoadFraction: Double = 0

    // MARK: - Private Properties

    private let modelManager: ModelManager
    private let llamaServerManager: LlamaServerManager
    private var mlxContainer: ModelContainer?
    private var loadedMLXModelId: String?
    private var generationTask: Task<Void, Never>?

    // MARK: - Initialization

    init(modelManager: ModelManager, llamaServerManager: LlamaServerManager) {
        self.modelManager = modelManager
        self.llamaServerManager = llamaServerManager
    }

    // MARK: - Public Methods

    /// Send a user message and get a streamed assistant response
    func sendMessage(
        conversation: ChatConversation,
        userMessage: String,
        recording: RecordingSession? = nil
    ) async -> ChatMessage? {
        guard !isGenerating else { return nil }

        isGenerating = true
        currentResponse = ""
        error = nil

        let engine = ModelSettings.chatEngine

        // Build the messages array for the LLM
        let systemPrompt = buildSystemPrompt(conversation: conversation, recording: recording)
        var llmMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]

        // Add conversation history (skip system messages from stored history)
        for msg in conversation.messages {
            switch msg.role {
            case .user:
                llmMessages.append(["role": "user", "content": msg.content])
            case .assistant:
                llmMessages.append(["role": "assistant", "content": msg.content])
            case .system:
                break
            }
        }

        // Add the new user message
        llmMessages.append(["role": "user", "content": userMessage])

        do {
            let response: String
            switch engine {
            case .mlx:
                response = try await generateWithMLX(messages: llmMessages)
            case .gguf:
                response = try await generateWithGGUF(messages: llmMessages)
            }

            isGenerating = false
            currentResponse = ""

            guard !response.isEmpty else { return nil }

            return ChatMessage(role: .assistant, content: response)
        } catch {
            Logger.error("Chat generation failed", error: error, category: Logger.processing)
            self.error = error
            isGenerating = false
            currentResponse = ""
            return nil
        }
    }

    /// Cancel the current generation
    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        currentResponse = ""
    }

    /// Unload any loaded model (for engine switching)
    func unloadModel() {
        mlxContainer = nil
        loadedMLXModelId = nil
        isModelLoaded = false
        modelLoadProgress = ""
        modelLoadFraction = 0
    }

    // MARK: - System Prompt Building

    private func buildSystemPrompt(conversation: ChatConversation, recording: RecordingSession?) -> String {
        var prompt = ModelSettings.chatSystemPrompt

        if ModelSettings.disableModelThinking {
            prompt += " /no_think"
        }

        // Attach recording context if available
        guard let recording = recording, conversation.contextType != .none else {
            return prompt
        }

        prompt += "\n\nYou have context from a recording titled \"\(recording.title)\":\n"

        let contextWindow = contextWindowForCurrentEngine()
        let maxOutputTokens = ModelSettings.maxOutputTokens
        let charBudget = (Int(Double(contextWindow) * 0.6) - maxOutputTokens) * 4

        switch conversation.contextType {
        case .none:
            break
        case .transcription:
            let transcript = truncateToFit(recording.transcription, budget: charBudget)
            prompt += "\n--- Transcript ---\n\(transcript)\n--- End Transcript ---"
        case .summary:
            let summary = truncateToFit(recording.summary, budget: charBudget)
            prompt += "\n--- Summary ---\n\(summary)\n--- End Summary ---"
        case .transcriptionAndNotes:
            let halfBudget = charBudget / 2
            let transcript = truncateToFit(recording.transcription, budget: halfBudget)
            let notes = truncateToFit(recording.notes, budget: halfBudget)
            prompt += "\n--- Transcript ---\n\(transcript)\n--- End Transcript ---"
            if !notes.isEmpty {
                prompt += "\n\n--- Notes ---\n\(notes)\n--- End Notes ---"
            }
        case .all:
            let thirdBudget = charBudget / 3
            let transcript = truncateToFit(recording.transcription, budget: thirdBudget)
            let summary = truncateToFit(recording.summary, budget: thirdBudget)
            let notes = truncateToFit(recording.notes, budget: thirdBudget)
            prompt += "\n--- Transcript ---\n\(transcript)\n--- End Transcript ---"
            if !summary.isEmpty {
                prompt += "\n\n--- Summary ---\n\(summary)\n--- End Summary ---"
            }
            if !notes.isEmpty {
                prompt += "\n\n--- Notes ---\n\(notes)\n--- End Notes ---"
            }
        }

        return prompt
    }

    private func contextWindowForCurrentEngine() -> Int {
        switch ModelSettings.chatEngine {
        case .mlx:
            return ModelMetadata.contextWindowForCurrentModel()
        case .gguf:
            return ModelSettings.ggufContextSize
        }
    }

    private func truncateToFit(_ text: String, budget: Int) -> String {
        guard budget > 0, !text.isEmpty else { return text }
        if text.count <= budget { return text }
        return String(text.prefix(budget)) + "\n[...truncated]"
    }

    // MARK: - MLX Generation

    private func generateWithMLX(messages: [[String: String]]) async throws -> String {
        // Unload stale model if user switched
        let currentModelId = ModelSettings.selectedMLXModel
        if mlxContainer != nil && loadedMLXModelId != currentModelId {
            Logger.info("MLX model changed, reloading for chat", category: Logger.processing)
            unloadModel()
        }

        // Load model if needed
        if mlxContainer == nil {
            modelLoadProgress = "Loading model..."
            let config: ModelConfiguration
            if currentModelId.hasPrefix("custom-mlx-"),
               let entry = ModelSettings.customMLXModels.first(where: { $0.id == currentModelId }),
               let url = entry.resolveURL() {
                _ = url.startAccessingSecurityScopedResource()
                config = ModelConfiguration(directory: url)
            } else {
                config = ModelConfiguration(id: currentModelId)
            }

            let container = try await LLMModelFactory.shared.loadContainer(configuration: config) { progress in
                Task { @MainActor in
                    self.modelLoadFraction = progress.fractionCompleted
                    self.modelLoadProgress = "Loading model: \(Int(progress.fractionCompleted * 100))%"
                }
            }
            mlxContainer = container
            loadedMLXModelId = currentModelId
            isModelLoaded = true
            modelLoadProgress = "Model loaded"
        }

        guard let container = mlxContainer else {
            throw ChatError.modelNotLoaded
        }

        modelLoadProgress = "Generating..."
        let maxTokens = ModelSettings.maxOutputTokens

        let userInput = UserInput(messages: messages)

        let result = try await container.perform { context in
            let input = try await context.processor.prepare(input: userInput)

            return try MLXLMCommon.generate(
                input: input,
                parameters: GenerateParameters(temperature: 0.7),
                context: context
            ) { tokens in
                if tokens.count >= maxTokens {
                    return .stop
                }

                if tokens.count % 5 == 0 {
                    let partial = context.tokenizer.decode(tokens: tokens)
                    Task { @MainActor in
                        self.currentResponse = partial
                    }
                }

                return .more
            }
        }

        let response = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        Logger.info("MLX chat completed. Response length: \(response.count) chars", category: Logger.processing)
        return response
    }

    // MARK: - GGUF Generation

    private func generateWithGGUF(messages: [[String: String]]) async throws -> String {
        // Ensure llama-server is running with the correct model
        let selectedModel = ModelSettings.selectedGGUFModel
        guard let modelPath = modelManager.getGGUFModelPath(for: selectedModel) else {
            throw ChatError.ggufModelNotFound(selectedModel)
        }

        if !llamaServerManager.isRunning || llamaServerManager.loadedModelPath != modelPath {
            if !llamaServerManager.isBinaryAvailable {
                modelLoadProgress = "Downloading llama-server..."
            } else {
                modelLoadProgress = "Starting llama-server..."
            }
            try await llamaServerManager.startServer(modelPath: modelPath)
        }

        modelLoadProgress = "Generating..."
        let maxTokens = ModelSettings.maxOutputTokens

        var fullResponse = ""
        let stream = llamaServerManager.sendChatCompletion(
            messages: messages,
            temperature: 0.7,
            maxTokens: maxTokens
        )

        for try await token in stream {
            fullResponse += token
            currentResponse = fullResponse
        }

        Logger.info("GGUF chat completed. Response length: \(fullResponse.count) chars", category: Logger.processing)
        return fullResponse.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Chat Errors

enum ChatError: LocalizedError {
    case modelNotLoaded
    case ggufModelNotFound(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Failed to load chat model. Please select and download a model in Settings."
        case .ggufModelNotFound(let modelId):
            return "GGUF model '\(modelId)' is not downloaded. Please download it in Settings."
        }
    }
}
