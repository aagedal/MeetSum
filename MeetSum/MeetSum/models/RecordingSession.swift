//
//  RecordingSession.swift
//  MeetSum
//
//  Data model for a recording session
//

import Foundation

/// Represents a single recording session with its associated data
struct RecordingSession: Identifiable, Codable {
    let id: UUID
    var title: String
    var audioFilename: String?
    var duration: TimeInterval
    var transcription: String
    var summary: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String? = nil,
        audioFilename: String? = nil,
        duration: TimeInterval = 0,
        transcription: String = "",
        summary: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title ?? Self.defaultTitle(for: createdAt)
        self.audioFilename = audioFilename
        self.duration = duration
        self.transcription = transcription
        self.summary = summary
        self.createdAt = createdAt
    }

    /// Resolve the full audio file URL from the filename
    var audioFileURL: URL? {
        guard let filename = audioFilename else { return nil }
        guard let recordingsDir = try? AudioUtils.getRecordingsDirectory() else { return nil }
        let url = recordingsDir.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Meeting \(formatter.string(from: date))"
    }
}
