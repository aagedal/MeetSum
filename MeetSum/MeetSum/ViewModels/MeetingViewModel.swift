//
//  MeetingViewModel.swift
//  MeetSum
//
//  Main ViewModel coordinating all operations
//

import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

/// Main ViewModel that coordinates recording, transcription, and summarization
@MainActor
class MeetingViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var recordingSession: RecordingSession?
    @Published var isProcessing = false
    @Published var errorMessage: String?
    @Published var recordingTime: String = "00:00"
    @Published var totalDuration: String = ""
    @Published var liveTranscription: String = ""
    @Published var isNewMeetingMode = true

    // MARK: - Managers

    private let modelManager: ModelManager
    private let recordingManager = AudioRecordingManager()
    private let playbackManager = AudioPlaybackManager()
    let transcriptionManager: TranscriptionManager
    let summarizationManager: SummarizationManager
    private let meetingStore: MeetingStore

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private var segmentQueue: [URL] = []
    private var isProcessingSegment = false

    // MARK: - Computed Properties

    var isRecording: Bool {
        recordingManager.isRecording
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

    var transcription: String {
        recordingSession?.transcription ?? ""
    }

    var summary: String {
        recordingSession?.summary ?? ""
    }

    // MARK: - Initialization

    init(modelManager: ModelManager, meetingStore: MeetingStore) {
        self.modelManager = modelManager
        self.meetingStore = meetingStore
        self.transcriptionManager = TranscriptionManager(modelManager: modelManager)
        self.summarizationManager = SummarizationManager(modelManager: modelManager)

        Logger.info("MeetingViewModel initialized", category: Logger.ui)
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

        // Bind processing state
        Publishers.CombineLatest(transcriptionManager.$isTranscribing, summarizationManager.$isSummarizing)
            .map { $0 || $1 }
            .assign(to: &$isProcessing)

        // Observe new segments for real-time transcription
        recordingManager.$newSegmentURL
            .compactMap { $0 }
            .sink { [weak self] url in
                self?.enqueueSegment(url)
            }
            .store(in: &cancellables)
    }

    // MARK: - Recording Commands

    func startRecording() {
        Logger.info("User started recording", category: Logger.ui)
        liveTranscription = ""
        segmentQueue = []
        isProcessingSegment = false
        recordingManager.startRecording()
    }

    func stopRecording() {
        Logger.info("User stopped recording", category: Logger.ui)

        guard let audioURL = recordingManager.stopRecording() else {
            Logger.error("Failed to get audio file URL after stopping recording", category: Logger.ui)
            errorMessage = "Failed to save recording"
            return
        }

        // Calculate duration
        let duration = recordingManager.recordingTime
        totalDuration = AudioUtils.formatDuration(duration)

        // Create session with filename-based storage
        let audioFilename = audioURL.lastPathComponent
        recordingSession = RecordingSession(
            audioFilename: audioFilename,
            duration: duration
        )

        Logger.info("Recording session created with duration: \(totalDuration)", category: Logger.ui)

        // Load for playback
        playbackManager.loadAudio(url: audioURL)

        // Wait for in-flight segments, then finalize
        Task {
            await waitForPendingSegments()

            // Set transcription from live transcript
            recordingSession?.transcription = liveTranscription

            // Start summarization
            if !liveTranscription.isEmpty {
                guard let summaryText = await summarizationManager.summarize(transcription: liveTranscription) else {
                    Logger.error("Summarization failed", category: Logger.processing)
                    errorMessage = "Summarization failed"
                    // Still save the meeting even without a summary
                    if let session = recordingSession {
                        meetingStore.addMeeting(session)
                        meetingStore.selectedMeetingId = session.id
                        isNewMeetingMode = false
                    }
                    return
                }
                recordingSession?.summary = summaryText
                Logger.info("Processing pipeline completed successfully", category: Logger.processing)
            }

            // Save to store and select
            if let session = recordingSession {
                meetingStore.addMeeting(session)
                meetingStore.selectedMeetingId = session.id
                isNewMeetingMode = false
            }
        }
    }

    // MARK: - Playback Commands

    func playRecording() {
        Logger.info("User started playback", category: Logger.ui)
        if let url = recordingSession?.audioFileURL {
            playbackManager.loadAudio(url: url)
        }
        playbackManager.play()
    }

    func pauseRecording() {
        Logger.info("User paused playback", category: Logger.ui)
        playbackManager.pause()
    }

    // MARK: - Meeting Navigation

    func prepareNewMeeting() {
        Logger.info("Preparing new meeting", category: Logger.ui)
        playbackManager.unload()
        recordingSession = nil
        totalDuration = ""
        errorMessage = nil
        liveTranscription = ""
        isNewMeetingMode = true
        meetingStore.selectedMeetingId = nil
    }

    func loadMeeting(_ meeting: RecordingSession) {
        Logger.info("Loading meeting: \(meeting.title)", category: Logger.ui)
        playbackManager.unload()

        recordingSession = meeting
        totalDuration = meeting.duration > 0 ? AudioUtils.formatDuration(meeting.duration) : ""
        liveTranscription = ""
        errorMessage = nil
        isNewMeetingMode = false

        // Load audio for playback if available
        if let audioURL = meeting.audioFileURL {
            playbackManager.loadAudio(url: audioURL)
        }
    }

    // MARK: - Export Commands

    func exportTranscription() {
        guard !transcription.isEmpty else { return }
        Logger.info("User exporting transcription", category: Logger.ui)
        exportText(transcription, filename: "transcription.txt")
    }

    func exportSummary() {
        guard !summary.isEmpty else { return }
        Logger.info("User exporting summary as text", category: Logger.ui)
        let cleaned = ThinkingTagParser.parse(summary).visibleContent
        exportText(cleaned, filename: "summary.txt")
    }

    func exportSummaryAsMarkdown() {
        guard !summary.isEmpty else { return }
        Logger.info("User exporting summary as markdown", category: Logger.ui)
        let cleaned = ThinkingTagParser.parse(summary).visibleContent
        exportFile(cleaned, filename: "summary.md", contentType: UTType(filenameExtension: "md", conformingTo: .text) ?? .plainText)
    }

    // MARK: - Redo Commands

    func retranscribe() {
        guard let audioURL = recordingSession?.audioFileURL else {
            errorMessage = "No audio file available for re-transcription"
            return
        }
        Logger.info("Re-transcribing audio", category: Logger.ui)

        Task {
            guard let text = await transcriptionManager.transcribe(audioURL: audioURL) else {
                errorMessage = "Re-transcription failed"
                return
            }
            recordingSession?.transcription = text

            // Update in store
            if let session = recordingSession {
                meetingStore.updateMeeting(session)
            }
        }
    }

    func resummarize() {
        guard !transcription.isEmpty else {
            errorMessage = "No transcription available for re-summarization"
            return
        }
        Logger.info("Re-summarizing transcription", category: Logger.ui)

        Task {
            guard let summaryText = await summarizationManager.summarize(transcription: transcription) else {
                errorMessage = "Re-summarization failed"
                return
            }
            recordingSession?.summary = summaryText

            // Update in store
            if let session = recordingSession {
                meetingStore.updateMeeting(session)
            }
        }
    }

    // MARK: - Segment Processing

    private func enqueueSegment(_ url: URL) {
        segmentQueue.append(url)
        processNextSegment()
    }

    private func processNextSegment() {
        guard !isProcessingSegment, !segmentQueue.isEmpty else { return }
        isProcessingSegment = true

        let url = segmentQueue.removeFirst()

        Task {
            if let text = await transcriptionManager.transcribeSegment(audioURL: url) {
                if !liveTranscription.isEmpty {
                    liveTranscription += "\n"
                }
                liveTranscription += text
            }

            // Clean up segment file
            try? FileManager.default.removeItem(at: url)

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

    private func exportText(_ text: String, filename: String) {
        exportFile(text, filename: filename, contentType: .text)
    }

    private func exportFile(_ text: String, filename: String, contentType: UTType) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [contentType]
        savePanel.nameFieldStringValue = filename
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try text.write(to: url, atomically: true, encoding: .utf8)
                    Logger.info("Exported file to: \(url.path)", category: Logger.ui)
                } catch {
                    Logger.error("Failed to export file", error: error, category: Logger.ui)
                    self.errorMessage = "Failed to export file: \(error.localizedDescription)"
                }
            }
        }
    }
}
