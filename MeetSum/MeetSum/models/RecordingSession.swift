//
//  RecordingSession.swift
//  Audio Synopsis
//
//  Data model for a recording session
//

import Foundation

/// A single timestamped transcript segment
struct TranscriptSegment: Identifiable, Codable {
    let id: UUID
    let startTime: TimeInterval
    let text: String

    var timecode: String {
        let totalSeconds = Int(startTime)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    init(id: UUID = UUID(), startTime: TimeInterval, text: String) {
        self.id = id
        self.startTime = startTime
        self.text = text
    }
}

/// Represents a single recording session with its associated data
struct RecordingSession: Identifiable, Codable {
    let id: UUID
    var title: String
    var audioFilename: String?
    var playbackAudioFilename: String?
    var duration: TimeInterval
    var transcription: String
    var summary: String
    var createdAt: Date
    var segments: [TranscriptSegment]
    var notes: String

    init(
        id: UUID = UUID(),
        title: String? = nil,
        audioFilename: String? = nil,
        playbackAudioFilename: String? = nil,
        duration: TimeInterval = 0,
        transcription: String = "",
        summary: String = "",
        createdAt: Date = Date(),
        segments: [TranscriptSegment] = [],
        notes: String = ""
    ) {
        self.id = id
        self.title = title ?? Self.defaultTitle(for: createdAt)
        self.audioFilename = audioFilename
        self.playbackAudioFilename = playbackAudioFilename
        self.duration = duration
        self.transcription = transcription
        self.summary = summary
        self.createdAt = createdAt
        self.segments = segments
        self.notes = notes
    }

    // Backward-compatible decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        audioFilename = try container.decodeIfPresent(String.self, forKey: .audioFilename)
        playbackAudioFilename = try container.decodeIfPresent(String.self, forKey: .playbackAudioFilename)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        transcription = try container.decode(String.self, forKey: .transcription)
        summary = try container.decode(String.self, forKey: .summary)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        segments = try container.decodeIfPresent([TranscriptSegment].self, forKey: .segments) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    /// Resolve the 16kHz Whisper audio file URL (for transcription)
    var audioFileURL: URL? {
        guard let filename = audioFilename else { return nil }
        guard let recordingsDir = try? AudioUtils.getRecordingsDirectory() else { return nil }
        let url = recordingsDir.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Resolve the high-quality playback audio file URL, falling back to the Whisper file
    var playbackAudioFileURL: URL? {
        if let filename = playbackAudioFilename,
           let recordingsDir = try? AudioUtils.getRecordingsDirectory() {
            let url = recordingsDir.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return audioFileURL
    }

    private static func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Recording \(formatter.string(from: date))"
    }
}
