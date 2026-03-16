//
//  SidebarView.swift
//  Audio Synopsis
//
//  Sidebar with recording list and new recording button
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var recordingStore: RecordingStore
    var processingRecordingIds: Set<UUID>
    var onNewRecording: () -> Void
    var onImportAudio: () -> Void

    @State private var editingRecordingId: UUID?
    @State private var editingTitle: String = ""
    @State private var recordingToDelete: RecordingSession?
    @State private var searchText: String = ""

    private var filteredRecordings: [RecordingSession] {
        guard !searchText.isEmpty else { return recordingStore.recordings }
        let query = searchText.lowercased()
        return recordingStore.recordings.filter { recording in
            recording.title.lowercased().contains(query) ||
            recording.transcription.lowercased().contains(query) ||
            recording.notes.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // New Recording / Import buttons
            HStack(spacing: 8) {
                Button(action: onNewRecording) {
                    Label("New Recording", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(action: onImportAudio) {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help("Import audio file")
            }
            .padding()

            Divider()

            // Recording list
            if recordingStore.recordings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.title)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No recordings yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search recordings", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.vertical, 8)

                if filteredRecordings.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No matching recordings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $recordingStore.selectedRecordingId) {
                        ForEach(filteredRecordings, id: \.id) { recording in
                            recordingRow(recording)
                                .tag(recording.id)
                                .contextMenu {
                                    Button("Rename") {
                                        editingRecordingId = recording.id
                                        editingTitle = recording.title
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        recordingToDelete = recording
                                    }
                                }
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
        }
        .sheet(item: $editingRecordingId) { recordingId in
            renameSheet(recordingId: recordingId)
        }
        .alert("Delete Recording?", isPresented: Binding(
            get: { recordingToDelete != nil },
            set: { if !$0 { recordingToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { recordingToDelete = nil }
            Button("Delete", role: .destructive) {
                if let recording = recordingToDelete {
                    recordingStore.deleteRecording(recording)
                    recordingToDelete = nil
                }
            }
        } message: {
            Text("This will permanently delete the recording and its audio files.")
        }
    }

    @ViewBuilder
    private func recordingRow(_ recording: RecordingSession) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(formattedDate(recording.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if recording.duration > 0 {
                        Text(AudioUtils.formatDuration(recording.duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if !recording.transcription.isEmpty {
                    Text(recording.transcription.prefix(60) + (recording.transcription.count > 60 ? "..." : ""))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if processingRecordingIds.contains(recording.id) {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func renameSheet(recordingId: UUID) -> some View {
        VStack(spacing: 16) {
            Text("Rename Recording")
                .font(.headline)

            TextField("Title", text: $editingTitle)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    editingRecordingId = nil
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    recordingStore.renameRecording(id: recordingId, newTitle: editingTitle)
                    editingRecordingId = nil
                }
                .keyboardShortcut(.defaultAction)
                .disabled(editingTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private func formattedDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }
}

// Make UUID conform to Identifiable for sheet(item:)
extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
