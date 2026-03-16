//
//  RecordingStore.swift
//  Audio Synopsis
//
//  Manages persistence and collection of recording sessions
//

import Foundation
import Combine

@MainActor
class RecordingStore: ObservableObject {

    // MARK: - Published Properties

    @Published var recordings: [RecordingSession] = []
    @Published var selectedRecordingId: UUID?
    @Published var lastError: String?

    // MARK: - Private Properties

    private let storageURL: URL

    // MARK: - Computed Properties

    var selectedRecording: RecordingSession? {
        guard let id = selectedRecordingId else { return nil }
        return recordings.first { $0.id == id }
    }

    // MARK: - Initialization

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "MeetSum"
        let appDir = appSupport.appendingPathComponent(bundleID)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        storageURL = appDir.appendingPathComponent("recordings.json")
        load()
    }

    // MARK: - Public Methods

    func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }

        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            recordings = try decoder.decode([RecordingSession].self, from: data)
            recordings.sort { $0.createdAt > $1.createdAt }
            Logger.info("Loaded \(recordings.count) recordings from store", category: Logger.general)
        } catch {
            Logger.error("Failed to load recordings", error: error, category: Logger.general)
            lastError = "Failed to load saved recordings: \(error.localizedDescription)"
        }
    }

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(recordings)
            try data.write(to: storageURL, options: .atomic)
            lastError = nil
            Logger.debug("Saved \(recordings.count) recordings to store", category: Logger.general)
        } catch {
            Logger.error("Failed to save recordings", error: error, category: Logger.general)
            lastError = "Failed to save recording data: \(error.localizedDescription)"
        }
    }

    func addRecording(_ recording: RecordingSession) {
        recordings.insert(recording, at: 0)
        save()
    }

    func updateRecording(_ recording: RecordingSession) {
        if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
            recordings[index] = recording
            save()
        }
    }

    func deleteRecording(_ recording: RecordingSession) {
        // Delete audio files if they exist
        if let url = recording.audioFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        if let playbackFilename = recording.playbackAudioFilename,
           let recordingsDir = try? AudioUtils.getRecordingsDirectory() {
            let playbackURL = recordingsDir.appendingPathComponent(playbackFilename)
            try? FileManager.default.removeItem(at: playbackURL)
        }
        recordings.removeAll { $0.id == recording.id }
        if selectedRecordingId == recording.id {
            selectedRecordingId = nil
        }
        save()
    }

    func renameRecording(id: UUID, newTitle: String) {
        if let index = recordings.firstIndex(where: { $0.id == id }) {
            recordings[index].title = newTitle
            save()
        }
    }
}
