//
//  SidebarView.swift
//  MeetSum
//
//  Sidebar with meeting list and new meeting button
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var meetingStore: MeetingStore
    var processingMeetingIds: Set<UUID>
    var onNewMeeting: () -> Void
    var onImportAudio: () -> Void

    @State private var editingMeetingId: UUID?
    @State private var editingTitle: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // New Meeting / Import buttons
            HStack(spacing: 8) {
                Button(action: onNewMeeting) {
                    Label("New Meeting", systemImage: "plus.circle.fill")
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

            // Meeting list
            if meetingStore.meetings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.title)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No meetings yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $meetingStore.selectedMeetingId) {
                    ForEach(meetingStore.meetings, id: \.id) { meeting in
                        meetingRow(meeting)
                            .tag(meeting.id)
                            .contextMenu {
                                Button("Rename") {
                                    editingMeetingId = meeting.id
                                    editingTitle = meeting.title
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    meetingStore.deleteMeeting(meeting)
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .sheet(item: $editingMeetingId) { meetingId in
            renameSheet(meetingId: meetingId)
        }
    }

    @ViewBuilder
    private func meetingRow(_ meeting: RecordingSession) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(formattedDate(meeting.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if meeting.duration > 0 {
                        Text(AudioUtils.formatDuration(meeting.duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if !meeting.transcription.isEmpty {
                    Text(meeting.transcription.prefix(60) + (meeting.transcription.count > 60 ? "..." : ""))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if processingMeetingIds.contains(meeting.id) {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func renameSheet(meetingId: UUID) -> some View {
        VStack(spacing: 16) {
            Text("Rename Meeting")
                .font(.headline)

            TextField("Title", text: $editingTitle)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    editingMeetingId = nil
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    meetingStore.renameMeeting(id: meetingId, newTitle: editingTitle)
                    editingMeetingId = nil
                }
                .keyboardShortcut(.defaultAction)
                .disabled(editingTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// Make UUID conform to Identifiable for sheet(item:)
extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
