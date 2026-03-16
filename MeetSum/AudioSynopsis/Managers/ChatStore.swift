//
//  ChatStore.swift
//  Audio Synopsis
//
//  Manages persistence and collection of chat conversations
//

import Foundation
import Combine

@MainActor
class ChatStore: ObservableObject {

    // MARK: - Published Properties

    @Published var conversations: [ChatConversation] = []
    @Published var selectedConversationId: UUID?
    @Published var lastError: String?

    // MARK: - Private Properties

    private let storageURL: URL

    // MARK: - Computed Properties

    var selectedConversation: ChatConversation? {
        guard let id = selectedConversationId else { return nil }
        return conversations.first { $0.id == id }
    }

    // MARK: - Initialization

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "MeetSum"
        let appDir = appSupport.appendingPathComponent(bundleID)

        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        storageURL = appDir.appendingPathComponent("chats.json")
        load()
    }

    // MARK: - Public Methods

    func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }

        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            conversations = try decoder.decode([ChatConversation].self, from: data)
            conversations.sort { $0.updatedAt > $1.updatedAt }
            Logger.info("Loaded \(conversations.count) chat conversations from store", category: Logger.general)
        } catch {
            Logger.error("Failed to load chat conversations", error: error, category: Logger.general)
            lastError = "Failed to load saved chats: \(error.localizedDescription)"
        }
    }

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(conversations)
            try data.write(to: storageURL, options: .atomic)
            lastError = nil
            Logger.debug("Saved \(conversations.count) chat conversations to store", category: Logger.general)
        } catch {
            Logger.error("Failed to save chat conversations", error: error, category: Logger.general)
            lastError = "Failed to save chat data: \(error.localizedDescription)"
        }
    }

    func addConversation(_ conversation: ChatConversation) {
        conversations.insert(conversation, at: 0)
        save()
    }

    func updateConversation(_ conversation: ChatConversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
            save()
        }
    }

    func deleteConversation(_ conversation: ChatConversation) {
        conversations.removeAll { $0.id == conversation.id }
        if selectedConversationId == conversation.id {
            selectedConversationId = nil
        }
        save()
    }

    func deleteConversation(id: UUID) {
        conversations.removeAll { $0.id == id }
        if selectedConversationId == id {
            selectedConversationId = nil
        }
        save()
    }
}
