//
//  RecordingViewModel.swift
//  Audio Synopsis
//
//  Main ViewModel coordinating all operations
//

import Foundation
import Combine
import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// Main ViewModel that coordinates recording, transcription, and summarization
@MainActor
class RecordingViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var recordingSession: RecordingSession?
    @Published var isProcessing = false
    @Published var errorMessage: String?
    @Published var recordingTime: String = "00:00"
    @Published var totalDuration: String = ""
    @Published var liveTranscription: String = ""
    @Published var isNewRecordingMode = true
    @Published var liveSegments: [TranscriptSegment] = []
    @Published var notes: String = ""
    @Published var isSummarizing = false
    @Published var summarizationProgress: String = ""
    @Published var modelLoadFraction: Double = 0
    @Published var processingRecordingIds: Set<UUID> = []
    @Published var pendingTitle: String?
    @Published var frequencyBands: [Float] = [Float](repeating: 0, count: AudioAnalyzer.bandCount)

    // MARK: - Managers

    private let modelManager: ModelManager
    private let recordingManager = AudioRecordingManager()
    private let playbackManager = AudioPlaybackManager()
    let transcriptionManager: TranscriptionManager
    let summarizationManager: SummarizationManager
    private let recordingStore: RecordingStore

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private var segmentQueue: [(url: URL, startTime: TimeInterval)] = []
    private var isProcessingSegment = false
    private var summarizationTask: Task<Void, Never>?

    // MARK: - Computed Properties

    var isRecording: Bool {
        recordingManager.isRecording
    }

    var isPaused: Bool {
        recordingManager.isPaused
    }

    var isStartingRecording: Bool {
        recordingManager.recordingState == .starting
    }

    var recordingState: RecordingState {
        recordingManager.recordingState
    }

    var isPlaying: Bool {
        playbackManager.isPlaying
    }

    var playbackCurrentTime: TimeInterval {
        playbackManager.currentTime
    }

    var playbackDuration: TimeInterval {
        playbackManager.duration
    }

    var playbackRate: Float {
        playbackManager.playbackRate
    }

    func cyclePlaybackRate() {
        playbackManager.cycleRate()
        objectWillChange.send()
    }

    var currentRecordingTimeInterval: TimeInterval {
        recordingManager.recordingTime
    }

    var systemAudioFailed: Bool {
        recordingManager.systemAudioFailed
    }

    var transcription: String {
        recordingSession?.transcription ?? ""
    }

    var summary: String {
        recordingSession?.summary ?? ""
    }

    /// Sanitized recording title for use in export filenames
    private var exportPrefix: String {
        let title = recordingSession?.title ?? "recording"
        // Replace characters unsafe for filenames
        let sanitized = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return sanitized
    }

    // MARK: - Initialization

    init(modelManager: ModelManager, recordingStore: RecordingStore, llamaServerManager: LlamaServerManager) {
        self.modelManager = modelManager
        self.recordingStore = recordingStore
        self.transcriptionManager = TranscriptionManager(modelManager: modelManager)
        self.summarizationManager = SummarizationManager(modelManager: modelManager, llamaServerManager: llamaServerManager)

        Logger.info("RecordingViewModel initialized", category: Logger.ui)
        setupBindings()
    }

    // MARK: - Setup

    private func setupBindings() {
        // Forward recording state changes to trigger UI updates
        recordingManager.$recordingState
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Forward playback state changes to trigger UI updates
        playbackManager.$isPlaying
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        playbackManager.$currentTime
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        playbackManager.$duration
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Forward system audio failure state to trigger UI updates
        recordingManager.$systemAudioFailed
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Bind recording time
        recordingManager.$recordingTime
            .map { AudioUtils.formatDuration($0) }
            .assign(to: &$recordingTime)

        // Bind errors
        recordingManager.$error
            .compactMap { $0?.localizedDescription }
            .assign(to: &$errorMessage)

        playbackManager.$error
            .compactMap { $0?.localizedDescription }
            .assign(to: &$errorMessage)

        transcriptionManager.$error
            .compactMap { $0?.localizedDescription }
            .assign(to: &$errorMessage)

        summarizationManager.$error
            .compactMap { $0?.localizedDescription }
            .assign(to: &$errorMessage)

        recordingStore.$lastError
            .compactMap { $0 }
            .assign(to: &$errorMessage)

        // Bind processing state
        Publishers.CombineLatest(transcriptionManager.$isTranscribing, summarizationManager.$isSummarizing)
            .map { $0 || $1 }
            .assign(to: &$isProcessing)

        // Forward summarization state
        summarizationManager.$isSummarizing
            .assign(to: &$isSummarizing)

        summarizationManager.$progress
            .assign(to: &$summarizationProgress)

        summarizationManager.$modelLoadFraction
            .assign(to: &$modelLoadFraction)

        // Forward frequency bands for audio visualizer
        recordingManager.$frequencyBands
            .assign(to: &$frequencyBands)

        // Observe new segments for real-time transcription
        recordingManager.$newSegment
            .compactMap { $0 }
            .sink { [weak self] segment in
                self?.enqueueSegment(segment.url, startTime: segment.startTime)
            }
            .store(in: &cancellables)
    }

    // MARK: - Recording Commands

    func startRecording() {
        Logger.info("User started recording", category: Logger.ui)
        liveTranscription = ""
        liveSegments = []
        segmentQueue = []
        isProcessingSegment = false
        recordingManager.startRecording()
    }

    func stopRecording() {
        Logger.info("User stopped recording", category: Logger.ui)

        // Capture duration before stopping (stopRecording resets accumulatedTime)
        let duration = recordingManager.recordingTime

        guard let audioURL = recordingManager.stopRecording() else {
            Logger.error("Failed to get audio file URL after stopping recording", category: Logger.ui)
            errorMessage = "Failed to save recording"
            return
        }
        totalDuration = AudioUtils.formatDuration(duration)

        // Create session with filename-based storage
        let audioFilename = audioURL.lastPathComponent
        let playbackFilename = recordingManager.currentPlaybackFileURL?.lastPathComponent
        recordingSession = RecordingSession(
            title: pendingTitle,
            audioFilename: audioFilename,
            playbackAudioFilename: playbackFilename,
            duration: duration,
            notes: notes
        )
        pendingTitle = nil

        // Set transcription immediately so the view has content before the async task runs
        recordingSession?.transcription = liveTranscription
        recordingSession?.segments = liveSegments

        Logger.info("Recording session created with duration: \(totalDuration)", category: Logger.ui)

        // Load HQ file for playback (falls back to whisper file for old recordings)
        if let playbackURL = recordingManager.currentPlaybackFileURL {
            playbackManager.loadAudio(url: playbackURL)
        } else {
            playbackManager.loadAudio(url: audioURL)
        }

        // Wait for in-flight segments, then finalize
        summarizationTask = Task {
            await waitForPendingSegments()

            // Set transcription and segments from live data
            recordingSession?.transcription = liveTranscription
            recordingSession?.segments = liveSegments

            // Save recording immediately so it appears in sidebar
            guard let session = recordingSession else { return }
            let recordingId = session.id
            recordingStore.addRecording(session)
            recordingStore.selectedRecordingId = recordingId
            isNewRecordingMode = false

            // Start summarization and update recording when done
            guard !liveTranscription.isEmpty else { return }
            guard ModelSettings.autoSummarize else { return }
            processingRecordingIds.insert(recordingId)
            defer { processingRecordingIds.remove(recordingId) }

            if let summaryText = await summarizationManager.summarize(transcription: liveTranscription, notes: notes) {
                updateRecordingInStore(id: recordingId) { $0.summary = summaryText }
                Logger.info("Processing pipeline completed successfully", category: Logger.processing)
            } else if !summarizationManager.wasCancelled {
                Logger.error("Summarization failed", category: Logger.processing)
                errorMessage = "Summarization failed"
            }
        }
    }

    // MARK: - Playback Commands

    func playRecording() {
        Logger.info("User started playback", category: Logger.ui)
        // Only load if not already loaded
        if playbackManager.duration == 0, let url = recordingSession?.playbackAudioFileURL {
            playbackManager.loadAudio(url: url)
        }
        playbackManager.play()
    }

    func pausePlayback() {
        Logger.info("User paused playback", category: Logger.ui)
        playbackManager.pause()
    }

    func stopPlayback() {
        Logger.info("User stopped playback", category: Logger.ui)
        playbackManager.stop()
    }

    func seekPlayback(to time: TimeInterval) {
        playbackManager.seek(to: time)
    }

    func pauseRecording() {
        Logger.info("User paused recording", category: Logger.ui)
        recordingManager.pauseRecording()
    }

    func continueRecording() {
        Logger.info("User continuing recording", category: Logger.ui)
        recordingManager.resumeRecording()
    }

    // MARK: - Recording Navigation

    func prepareNewRecording() {
        guard !isRecording && !isPaused else { return }
        Logger.info("Preparing new recording", category: Logger.ui)
        playbackManager.unload()
        recordingSession = nil
        totalDuration = ""
        errorMessage = nil
        liveTranscription = ""
        liveSegments = []
        notes = ""
        pendingTitle = nil
        isNewRecordingMode = true
        recordingStore.selectedRecordingId = nil
    }

    func loadRecording(_ recording: RecordingSession) {
        guard !isRecording && !isPaused else { return }
        guard recordingSession?.id != recording.id else { return }

        // Flush any pending notes before switching away
        if recordingSession != nil && !isNewRecordingMode {
            saveNotes()
        }

        Logger.info("Loading recording: \(recording.title)", category: Logger.ui)
        playbackManager.unload()

        recordingSession = recording
        totalDuration = recording.duration > 0 ? AudioUtils.formatDuration(recording.duration) : ""
        liveTranscription = ""
        liveSegments = []
        notes = recording.notes
        errorMessage = nil
        isNewRecordingMode = false

        // Load audio for playback if available (prefer HQ file)
        if let audioURL = recording.playbackAudioFileURL {
            playbackManager.loadAudio(url: audioURL)
        }
    }

    // MARK: - Notes & Title

    func saveNotes() {
        guard let id = recordingSession?.id else { return }
        updateRecordingInStore(id: id) { $0.notes = self.notes }
    }

    func renameRecording(_ newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let id = recordingSession?.id, !isNewRecordingMode {
            // Saved recording — update via store
            recordingStore.renameRecording(id: id, newTitle: trimmed)
            recordingSession?.title = trimmed
        } else if recordingSession != nil {
            // Recording in progress — update session directly
            recordingSession?.title = trimmed
        } else {
            // New recording mode, no session yet — stash for later
            pendingTitle = trimmed
        }
    }

    // MARK: - Import Audio

    func importAudioFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select an audio file to import"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self?.processImportedAudio(url)
            }
        }
    }

    private func processImportedAudio(_ sourceURL: URL) async {
        Logger.info("Importing audio file: \(sourceURL.lastPathComponent)", category: Logger.ui)

        do {
            let recordingsDir = try AudioUtils.getRecordingsDirectory()
            let stem = sourceURL.deletingPathExtension().lastPathComponent
            let ext = sourceURL.pathExtension

            var destFilename = sourceURL.lastPathComponent
            var destURL = recordingsDir.appendingPathComponent(destFilename)

            // Avoid overwriting existing files
            if FileManager.default.fileExists(atPath: destURL.path) {
                destFilename = "\(stem)_\(UUID().uuidString.prefix(8)).\(ext)"
                destURL = recordingsDir.appendingPathComponent(destFilename)
            }

            try FileManager.default.copyItem(at: sourceURL, to: destURL)

            // Get audio duration
            var duration: TimeInterval = 0
            if let player = try? AVAudioPlayer(contentsOf: destURL) {
                duration = player.duration
            }

            let session = RecordingSession(
                title: stem,
                audioFilename: destFilename,
                duration: duration
            )
            let recordingId = session.id

            recordingSession = session
            totalDuration = duration > 0 ? AudioUtils.formatDuration(duration) : ""
            liveTranscription = ""
            liveSegments = []
            isNewRecordingMode = false

            // Load for playback
            playbackManager.loadAudio(url: destURL)

            // Save to store immediately
            recordingStore.addRecording(session)
            recordingStore.selectedRecordingId = recordingId

            // Transcribe and summarize in background
            processingRecordingIds.insert(recordingId)
            defer { processingRecordingIds.remove(recordingId) }

            if let text = await transcriptionManager.transcribe(audioURL: destURL) {
                updateRecordingInStore(id: recordingId) { $0.transcription = text }

                if ModelSettings.autoSummarize {
                    if let summaryText = await summarizationManager.summarize(transcription: text, notes: "") {
                        updateRecordingInStore(id: recordingId) { $0.summary = summaryText }
                    }
                }
            }
        } catch {
            Logger.error("Failed to import audio", error: error, category: Logger.ui)
            errorMessage = "Failed to import audio: \(error.localizedDescription)"
        }
    }

    // MARK: - Export Commands

    func exportTranscription() {
        guard !transcription.isEmpty else { return }
        Logger.info("User exporting transcription", category: Logger.ui)
        exportText(transcription, filename: "\(exportPrefix)_transcription.txt")
    }

    func exportTranscriptionAsSRT() {
        guard let segments = recordingSession?.segments, !segments.isEmpty else { return }
        Logger.info("User exporting transcription as SRT", category: Logger.ui)

        var srt = ""
        for (index, segment) in segments.enumerated() {
            let start = Self.srtTimestamp(segment.startTime)
            let nextStart = index + 1 < segments.count ? segments[index + 1].startTime : segment.startTime + 5
            let end = Self.srtTimestamp(nextStart)
            srt += "\(index + 1)\n\(start) --> \(end)\n\(segment.text)\n\n"
        }

        let srtType = UTType(filenameExtension: "srt", conformingTo: .text) ?? .plainText
        exportFile(srt, filename: "\(exportPrefix)_transcription.srt", contentType: srtType)
    }

    private static func srtTimestamp(_ time: TimeInterval) -> String {
        let totalMs = Int(time * 1000)
        let hours = totalMs / 3_600_000
        let minutes = (totalMs % 3_600_000) / 60_000
        let seconds = (totalMs % 60_000) / 1000
        let ms = totalMs % 1000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, ms)
    }

    func exportSummary() {
        guard !summary.isEmpty else { return }
        Logger.info("User exporting summary as text", category: Logger.ui)
        let cleaned = ThinkingTagParser.parse(summary).visibleContent
        exportText(cleaned, filename: "\(exportPrefix)_summary.txt")
    }

    func exportSummaryAsMarkdown() {
        guard !summary.isEmpty else { return }
        Logger.info("User exporting summary as markdown", category: Logger.ui)
        let cleaned = ThinkingTagParser.parse(summary).visibleContent
        exportFile(cleaned, filename: "\(exportPrefix)_summary.md", contentType: UTType(filenameExtension: "md", conformingTo: .text) ?? .plainText)
    }

    func exportCombinedMarkdown() {
        guard let session = recordingSession else { return }
        Logger.info("User exporting combined markdown", category: Logger.ui)

        var md = "# \(session.title)\n\n"

        // Date + duration header
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        md += "**Date:** \(formatter.string(from: session.createdAt))"
        if session.duration > 0 {
            md += "  |  **Duration:** \(AudioUtils.formatDuration(session.duration))"
        }
        md += "\n\n"

        // Summary section
        let cleanedSummary = ThinkingTagParser.parse(session.summary).visibleContent
        if !cleanedSummary.isEmpty {
            md += "## Summary\n\n\(cleanedSummary)\n\n"
        }

        // Notes section
        let trimmedNotes = session.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            md += "## Notes\n\n\(trimmedNotes)\n\n"
        }

        // Transcript section
        if !session.transcription.isEmpty {
            md += "## Transcript\n\n"
            if !session.segments.isEmpty {
                for segment in session.segments {
                    md += "**[\(segment.timecode)]** \(segment.text)\n\n"
                }
            } else {
                md += session.transcription + "\n"
            }
        }

        let mdType = UTType(filenameExtension: "md", conformingTo: .text) ?? .plainText
        exportFile(md, filename: "\(exportPrefix)_recording.md", contentType: mdType)
    }

    // MARK: - Redo Commands

    func retranscribe() {
        guard let session = recordingSession, let audioURL = session.audioFileURL else {
            errorMessage = "No audio file available for re-transcription"
            return
        }
        let recordingId = session.id
        Logger.info("Re-transcribing audio", category: Logger.ui)

        processingRecordingIds.insert(recordingId)

        Task {
            defer { processingRecordingIds.remove(recordingId) }

            guard let result = await transcriptionManager.transcribeWithSegments(audioURL: audioURL) else {
                errorMessage = "Re-transcription failed"
                return
            }

            updateRecordingInStore(id: recordingId) {
                $0.transcription = result.text
                $0.segments = result.segments
            }
        }
    }

    func resummarize() {
        guard let session = recordingSession, !session.transcription.isEmpty else {
            errorMessage = "No transcription available for re-summarization"
            return
        }
        let recordingId = session.id
        let transcriptionText = session.transcription
        let notesText = session.notes
        Logger.info("Re-summarizing transcription", category: Logger.ui)

        processingRecordingIds.insert(recordingId)

        summarizationTask = Task {
            defer { processingRecordingIds.remove(recordingId) }

            guard let summaryText = await summarizationManager.summarize(transcription: transcriptionText, notes: notesText) else {
                if !summarizationManager.wasCancelled {
                    errorMessage = "Re-summarization failed"
                }
                return
            }

            updateRecordingInStore(id: recordingId) { $0.summary = summaryText }
        }
    }

    func cancelSummarization() {
        summarizationTask?.cancel()
        summarizationManager.cancelSummarization()
        if let id = recordingSession?.id {
            processingRecordingIds.remove(id)
        }
    }

    // MARK: - Segment Processing

    private func enqueueSegment(_ url: URL, startTime: TimeInterval) {
        segmentQueue.append((url: url, startTime: startTime))
        processNextSegment()
    }

    private func processNextSegment() {
        guard !isProcessingSegment, !segmentQueue.isEmpty else { return }
        isProcessingSegment = true

        let segment = segmentQueue.removeFirst()

        Task {
            let lastPrompt = liveTranscription.isEmpty ? nil : String(liveTranscription.suffix(200))
            if let text = await transcriptionManager.transcribeSegment(audioURL: segment.url, prompt: lastPrompt) {
                let transcriptSegment = TranscriptSegment(startTime: segment.startTime, text: text)
                liveSegments.append(transcriptSegment)

                if !liveTranscription.isEmpty {
                    liveTranscription += "\n"
                }
                liveTranscription += text
            }

            // Clean up segment file
            try? FileManager.default.removeItem(at: segment.url)

            isProcessingSegment = false
            processNextSegment()
        }
    }

    private func waitForPendingSegments() async {
        // Wait until all queued segments are processed
        while isProcessingSegment || !segmentQueue.isEmpty {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
    }

    // MARK: - Private Methods

    /// Update a recording in the store by ID, and sync to recordingSession if still viewing it
    private func updateRecordingInStore(id: UUID, mutate: (inout RecordingSession) -> Void) {
        if var recording = recordingStore.recordings.first(where: { $0.id == id }) {
            mutate(&recording)
            recordingStore.updateRecording(recording)

            // Sync to local session if still viewing this recording
            if recordingSession?.id == id {
                recordingSession = recording
            }
        }
    }

    private func exportText(_ text: String, filename: String) {
        exportFile(text, filename: filename, contentType: .text)
    }

    private func exportFile(_ text: String, filename: String, contentType: UTType) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [contentType]
        savePanel.nameFieldStringValue = filename
        savePanel.begin { [weak self] response in
            if response == .OK, let url = savePanel.url {
                do {
                    try text.write(to: url, atomically: true, encoding: .utf8)
                    Logger.info("Exported file to: \(url.path)", category: Logger.ui)
                } catch {
                    Logger.error("Failed to export file", error: error, category: Logger.ui)
                    self?.errorMessage = "Failed to export file: \(error.localizedDescription)"
                }
            }
        }
    }
}
