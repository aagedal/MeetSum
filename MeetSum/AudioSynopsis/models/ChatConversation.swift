//
//  ChatConversation.swift
//  Audio Synopsis
//
//  Data models for chat conversations with local LLMs
//

import Foundation

/// Role of a chat message participant
enum ChatRole: String, Codable {
    case system
    case user
    case assistant
}

/// What recording context is attached to a chat conversation
enum ChatContextType: String, Codable, CaseIterable, Identifiable {
    case none
    case transcription
    case summary
    case transcriptionAndNotes
    case all

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .transcription: return "Transcript"
        case .summary: return "Summary"
        case .transcriptionAndNotes: return "Transcript + Notes"
        case .all: return "All"
        }
    }
}

/// A single message in a chat conversation
struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date

    init(id: UUID = UUID(), role: ChatRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

/// A multi-turn chat conversation, optionally linked to a recording
struct ChatConversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date
    var recordingId: UUID?
    var contextType: ChatContextType

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        recordingId: UUID? = nil,
        contextType: ChatContextType = .none
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.recordingId = recordingId
        self.contextType = contextType
    }
}
