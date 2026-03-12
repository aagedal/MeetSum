//
//  MeetingDetailView.swift
//  MeetSum
//
//  Detail view for a meeting session (recording, transcript, summary)
//

import SwiftUI

struct MeetingDetailView: View {
    @ObservedObject var viewModel: MeetingViewModel
    @ObservedObject var modelManager: ModelManager
    @Binding var showingSettings: Bool

    @State private var selectedTab: Int = 0

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.blue.opacity(0.05), Color.purple.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                // Header
                header

                // Recording card (only in new-meeting mode)
                if viewModel.isNewMeetingMode {
                    recordingCard
                        .padding(.horizontal)
                }

                // Playback controls (for saved meetings with audio)
                if !viewModel.isNewMeetingMode && viewModel.recordingSession?.audioFileURL != nil {
                    playbackCard
                        .padding(.horizontal)
                }

                // Error card
                if let error = viewModel.errorMessage {
                    errorCard(error)
                        .padding(.horizontal)
                }

                // Tab view
                TabView(selection: $selectedTab) {
                    transcriptTab
                        .tabItem {
                            Label("Transcript", systemImage: "text.quote")
                        }
                        .tag(0)

                    summaryTab
                        .tabItem {
                            Label("Summary", systemImage: "sparkles")
                        }
                        .tag(1)
                }
                .padding(.horizontal)
            }
            .padding()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if let session = viewModel.recordingSession {
                    Text(session.title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                } else {
                    Text("New Meeting")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                }
            }

            Spacer()

            if !viewModel.totalDuration.isEmpty {
                Label(viewModel.totalDuration, systemImage: "clock")
                    .font(.headline)
                    .foregroundColor(.green)
            }
        }
        .padding()
    }

    // MARK: - Recording Card

    private var recordingCard: some View {
        VStack(spacing: 16) {
            // Recording button
            Button(action: {
                if viewModel.recordingState == .recording {
                    viewModel.stopRecording()
                } else if viewModel.recordingState == .idle {
                    viewModel.startRecording()
                }
            }) {
                HStack(spacing: 12) {
                    if viewModel.isStartingRecording {
                        ProgressView()
                            .controlSize(.regular)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: viewModel.recordingState == .recording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 32))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.isStartingRecording ? "Starting..." : viewModel.recordingState == .recording ? "Stop Recording" : "Start Recording")
                            .font(.headline)
                        if viewModel.recordingState == .recording {
                            Text("Recording: \(viewModel.recordingTime)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.isStartingRecording ? Color.orange : viewModel.recordingState == .recording ? Color.red : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isStartingRecording)

            // Playback controls (during new meeting mode, after recording)
            if !viewModel.isRecording && !viewModel.totalDuration.isEmpty {
                HStack(spacing: 16) {
                    Button(action: {
                        if viewModel.isPlaying {
                            viewModel.pauseRecording()
                        } else {
                            viewModel.playRecording()
                        }
                    }) {
                        Label(viewModel.isPlaying ? "Pause" : "Play", systemImage: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.headline)
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 10)
    }

    // MARK: - Playback Card (for saved meetings)

    private var playbackCard: some View {
        HStack(spacing: 16) {
            Button(action: {
                if viewModel.isPlaying {
                    viewModel.pauseRecording()
                } else {
                    viewModel.playRecording()
                }
            }) {
                Label(viewModel.isPlaying ? "Pause" : "Play", systemImage: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.bordered)

            if !viewModel.totalDuration.isEmpty {
                Label(viewModel.totalDuration, systemImage: "clock")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 10)
    }

    // MARK: - Transcript Tab

    private var transcriptTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.isRecording {
                // Live transcription during recording
                HStack {
                    Label("Live Transcript", systemImage: "text.quote")
                        .font(.headline)

                    Spacer()

                    if !viewModel.liveTranscription.isEmpty {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("Transcribing...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        Text(viewModel.liveTranscription.isEmpty ? "Listening..." : viewModel.liveTranscription)
                            .font(.body)
                            .foregroundColor(viewModel.liveTranscription.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .id("transcriptBottom")
                    }
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .onChange(of: viewModel.liveTranscription) {
                        withAnimation {
                            proxy.scrollTo("transcriptBottom", anchor: .bottom)
                        }
                    }
                }

            } else if !viewModel.transcription.isEmpty {
                // Final transcript after recording
                HStack {
                    Label("Transcription", systemImage: "text.quote")
                        .font(.headline)

                    Spacer()

                    Button(action: {
                        viewModel.retranscribe()
                    }) {
                        Label("Redo", systemImage: "arrow.counterclockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isRecording || viewModel.isProcessing || viewModel.recordingSession?.audioFileURL == nil)
                    .help("Re-transcribe audio")

                    Button(action: {
                        viewModel.exportTranscription()
                    }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                ScrollView {
                    Text(viewModel.transcription)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)

            } else {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "mic.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Start recording to see live transcription")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 10)
    }

    // MARK: - Summary Tab

    private var summaryTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.isRecording {
                // During recording
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Summary will be generated after recording stops")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if viewModel.summarizationManager.isSummarizing {
                // Summarizing
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Generating summary...")
                        .font(.headline)
                    Text(viewModel.summarizationManager.progress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if !viewModel.summary.isEmpty {
                // Summary available
                HStack {
                    Label("Summary", systemImage: "sparkles")
                        .font(.headline)

                    Spacer()

                    Button(action: {
                        viewModel.resummarize()
                    }) {
                        Label("Redo", systemImage: "arrow.counterclockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isRecording || viewModel.isProcessing)
                    .help("Re-summarize transcription")

                    Menu {
                        Button("Export as Text") {
                            viewModel.exportSummary()
                        }
                        Button("Export as Markdown") {
                            viewModel.exportSummaryAsMarkdown()
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                MarkdownSummaryView(rawSummary: viewModel.summary)

            } else {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Record a meeting to generate a summary")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 10)
    }

    // MARK: - Error Card

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Error")
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if message.contains("not found") {
                Button("Open Settings") {
                    showingSettings = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
}
