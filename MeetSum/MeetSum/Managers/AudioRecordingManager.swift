//
//  AudioRecordingManager.swift
//  MeetSum
//
//  Manages audio recording using AVAudioEngine with segmented output
//

import Foundation
import AVFoundation
import Combine

/// Recording lifecycle states
enum RecordingState {
    case idle
    case starting
    case recording
}

/// Manages audio recording using AVAudioEngine for real-time segment access
@MainActor
class AudioRecordingManager: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published var recordingState: RecordingState = .idle
    @Published var recordingTime: TimeInterval = 0.0
    @Published var currentFileURL: URL?
    @Published var error: Error?
    /// Published when a new segment file is ready for transcription
    @Published var newSegmentURL: URL?

    // MARK: - Private Properties

    private var audioEngine: AVAudioEngine?
    private var timer: Timer?
    private var startTime: Date?

    /// Serial queue for safe segment rotation from audio tap callback
    private let segmentQueue = DispatchQueue(label: "com.meetsum.segment", qos: .userInitiated)

    // Segment management
    private var segmentIndex: Int = 0
    private var segmentFileHandle: FileHandle?
    private var segmentDataSize: UInt32 = 0
    private var segmentURL: URL?
    private var segmentsDirectory: URL?

    // Full recording
    private var recordingFileHandle: FileHandle?
    private var recordingDataSize: UInt32 = 0

    // Segment rotation
    private let segmentDuration: TimeInterval = 10.0
    private var segmentStartTime: Date?

    // MARK: - Public Methods

    var isRecording: Bool {
        recordingState == .starting || recordingState == .recording
    }

    func startRecording() {
        Logger.info("Starting audio recording", category: Logger.audio)

        error = nil
        guard recordingState == .idle else { return }
        recordingState = .starting

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            let granted = await self.requestMicrophonePermission()
            guard granted else {
                await MainActor.run {
                    self.error = NSError(domain: "AudioRecordingManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied"])
                    self.recordingState = .idle
                    Logger.error("Microphone permission denied", category: Logger.audio)
                }
                return
            }

            do {
                // Setup directories and files
                let recordingsDir = try AudioUtils.getRecordingsDirectory()
                let segDir = try AudioUtils.getSegmentsDirectory()
                AudioUtils.cleanSegmentsDirectory()

                let filename = AudioUtils.generateRecordingFilename()
                let fileURL = recordingsDir.appendingPathComponent(filename)

                await MainActor.run {
                    self.currentFileURL = fileURL
                    self.segmentsDirectory = segDir
                    self.segmentIndex = 0
                }

                // Create full recording WAV file
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
                let recHandle = try FileHandle(forWritingTo: fileURL)
                AudioUtils.writeWAVHeader(to: recHandle, dataSize: 0)

                // Create first segment
                let firstSegURL = segDir.appendingPathComponent("segment_000.wav")
                FileManager.default.createFile(atPath: firstSegURL.path, contents: nil)
                let segHandle = try FileHandle(forWritingTo: firstSegURL)
                AudioUtils.writeWAVHeader(to: segHandle, dataSize: 0)

                await MainActor.run {
                    self.recordingFileHandle = recHandle
                    self.recordingDataSize = 0
                    self.segmentFileHandle = segHandle
                    self.segmentDataSize = 0
                    self.segmentURL = firstSegURL
                    self.segmentStartTime = Date()
                }

                // Setup AVAudioEngine
                let engine = AVAudioEngine()
                let inputNode = engine.inputNode
                let inputFormat = inputNode.outputFormat(forBus: 0)
                let targetFormat = AudioUtils.whisperRecordingFormat

                // Install tap on input node
                inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                    guard let self = self else { return }
                    self.segmentQueue.async {
                        self.processAudioBuffer(buffer, from: inputFormat, to: targetFormat)
                    }
                }

                try engine.start()

                await MainActor.run {
                    self.audioEngine = engine
                    self.recordingState = .recording
                    self.startTime = Date()
                    self.startTimer()
                    Logger.info("Audio recording started with AVAudioEngine to: \(fileURL.path)", category: Logger.audio)
                }

            } catch {
                await MainActor.run {
                    Logger.error("Failed to setup audio engine", error: error, category: Logger.audio)
                    self.error = error
                    self.recordingState = .idle
                }
            }
        }
    }

    /// Stop recording audio
    /// - Returns: URL of the recorded file, or nil if recording failed
    func stopRecording() -> URL? {
        Logger.info("Stopping audio recording", category: Logger.audio)

        stopTimer()

        // Stop engine
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        recordingState = .idle

        // Finalize current segment
        segmentQueue.sync {
            self.finalizeCurrentSegment(publish: true)
            self.finalizeRecordingFile()
        }

        let fileURL = currentFileURL

        if let url = fileURL, FileManager.default.fileExists(atPath: url.path) {
            Logger.info("Audio recording stopped. File saved at: \(url.path)", category: Logger.audio)
        } else {
            Logger.warning("Audio recording stopped but file may not exist", category: Logger.audio)
        }

        return fileURL
    }

    // MARK: - Private Methods

    /// Process an audio buffer: convert to 16kHz PCM and write to segment + full recording
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, from sourceFormat: AVAudioFormat, to targetFormat: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else { return }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else { return }

        var error: NSError?
        var inputConsumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard error == nil, outputBuffer.frameLength > 0 else { return }

        // Extract raw PCM data (Int16)
        let pcmData: Data
        if let int16Data = outputBuffer.int16ChannelData {
            pcmData = Data(bytes: int16Data[0], count: Int(outputBuffer.frameLength) * 2)
        } else {
            return
        }

        // Write to full recording
        recordingFileHandle?.write(pcmData)
        recordingDataSize += UInt32(pcmData.count)

        // Write to current segment
        segmentFileHandle?.write(pcmData)
        segmentDataSize += UInt32(pcmData.count)

        // Check if we need to rotate segment
        if let start = segmentStartTime, Date().timeIntervalSince(start) >= segmentDuration {
            finalizeCurrentSegment(publish: true)
            openNewSegment()
        }
    }

    /// Finalize the current segment WAV file and optionally publish it
    private func finalizeCurrentSegment(publish: Bool) {
        guard let url = segmentURL else { return }

        // Close file handle
        try? segmentFileHandle?.close()
        segmentFileHandle = nil

        // Update WAV header with actual data size
        if segmentDataSize > 0 {
            AudioUtils.updateWAVHeader(at: url, dataSize: segmentDataSize)

            if publish {
                let publishURL = url
                Task { @MainActor in
                    self.newSegmentURL = publishURL
                }
            }
        } else {
            // Empty segment, remove file
            try? FileManager.default.removeItem(at: url)
        }

        segmentDataSize = 0
        segmentURL = nil
    }

    /// Open a new segment file
    private func openNewSegment() {
        segmentIndex += 1
        guard let segDir = segmentsDirectory else { return }

        let segFilename = String(format: "segment_%03d.wav", segmentIndex)
        let newURL = segDir.appendingPathComponent(segFilename)
        FileManager.default.createFile(atPath: newURL.path, contents: nil)

        do {
            let handle = try FileHandle(forWritingTo: newURL)
            AudioUtils.writeWAVHeader(to: handle, dataSize: 0)
            segmentFileHandle = handle
            segmentDataSize = 0
            segmentURL = newURL
            segmentStartTime = Date()
        } catch {
            Logger.error("Failed to open new segment file", error: error, category: Logger.audio)
        }
    }

    /// Finalize the full recording WAV file
    private func finalizeRecordingFile() {
        guard let url = currentFileURL else { return }
        try? recordingFileHandle?.close()
        recordingFileHandle = nil

        if recordingDataSize > 0 {
            AudioUtils.updateWAVHeader(at: url, dataSize: recordingDataSize)
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Logger.info("Microphone permission: \(granted ? "granted" : "denied")", category: Logger.audio)
                continuation.resume(returning: granted)
            }
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.startTime else { return }
            Task { @MainActor in
                self.recordingTime = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
