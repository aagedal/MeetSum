//
//  MeetingStore.swift
//  MeetSum
//
//  Manages persistence and collection of meeting sessions
//

import Foundation
import Combine

@MainActor
class MeetingStore: ObservableObject {

    // MARK: - Published Properties

    @Published var meetings: [RecordingSession] = []
    @Published var selectedMeetingId: UUID?

    // MARK: - Private Properties

    private let storageURL: URL

    // MARK: - Computed Properties

    var selectedMeeting: RecordingSession? {
        guard let id = selectedMeetingId else { return nil }
        return meetings.first { $0.id == id }
    }

    // MARK: - Initialization

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "MeetSum"
        let appDir = appSupport.appendingPathComponent(bundleID)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        storageURL = appDir.appendingPathComponent("meetings.json")
        load()
    }

    // MARK: - Public Methods

    func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }

        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            meetings = try decoder.decode([RecordingSession].self, from: data)
            meetings.sort { $0.createdAt > $1.createdAt }
            Logger.info("Loaded \(meetings.count) meetings from store", category: Logger.general)
        } catch {
            Logger.error("Failed to load meetings", error: error, category: Logger.general)
        }
    }

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(meetings)
            try data.write(to: storageURL, options: .atomic)
            Logger.debug("Saved \(meetings.count) meetings to store", category: Logger.general)
        } catch {
            Logger.error("Failed to save meetings", error: error, category: Logger.general)
        }
    }

    func addMeeting(_ meeting: RecordingSession) {
        meetings.insert(meeting, at: 0)
        save()
    }

    func updateMeeting(_ meeting: RecordingSession) {
        if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
            meetings[index] = meeting
            save()
        }
    }

    func deleteMeeting(_ meeting: RecordingSession) {
        // Delete audio files if they exist
        if let url = meeting.audioFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        if let playbackFilename = meeting.playbackAudioFilename,
           let recordingsDir = try? AudioUtils.getRecordingsDirectory() {
            let playbackURL = recordingsDir.appendingPathComponent(playbackFilename)
            try? FileManager.default.removeItem(at: playbackURL)
        }
        meetings.removeAll { $0.id == meeting.id }
        if selectedMeetingId == meeting.id {
            selectedMeetingId = nil
        }
        save()
    }

    func renameMeeting(id: UUID, newTitle: String) {
        if let index = meetings.firstIndex(where: { $0.id == id }) {
            meetings[index].title = newTitle
            save()
        }
    }
}
