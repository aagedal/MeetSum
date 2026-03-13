//
//  ContentView.swift
//  MeetSum
//
//  Created by Truls Aagedal on 24/11/2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var modelManager = ModelManager()
    @StateObject private var meetingStore = MeetingStore()
    @StateObject private var viewModel: MeetingViewModel

    @State private var showingSettings = false
    @State private var showingModelSetup = false
    @State private var selectedTab: Int = 0
    @State private var captureMicrophone: Bool = ModelSettings.captureMicrophone
    @State private var captureSystemAudio: Bool = ModelSettings.captureSystemAudio

    init() {
        let modelMgr = ModelManager()
        let store = MeetingStore()
        _modelManager = StateObject(wrappedValue: modelMgr)
        _meetingStore = StateObject(wrappedValue: store)
        _viewModel = StateObject(wrappedValue: MeetingViewModel(modelManager: modelMgr, meetingStore: store))
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(meetingStore: meetingStore, processingMeetingIds: viewModel.processingMeetingIds, onNewMeeting: {
                viewModel.prepareNewMeeting()
            }, onImportAudio: {
                viewModel.importAudioFile()
            })
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            MeetingDetailView(
                viewModel: viewModel,
                modelManager: modelManager,
                showingSettings: $showingSettings,
                selectedTab: $selectedTab
            )
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $showingSettings) {
            SettingsView(modelManager: modelManager)
        }
        .sheet(isPresented: $showingModelSetup) {
            ModelSetupView(modelManager: modelManager, isPresented: $showingModelSetup)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 16) {
                    // Record/Play/Stop button
                    Group {
                        if viewModel.isRecording || viewModel.isStartingRecording {
                            Button(action: {
                                if viewModel.recordingState == .recording {
                                    viewModel.stopRecording()
                                }
                            }) {
                                HStack(spacing: 6) {
                                    if viewModel.isStartingRecording {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "stop.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                    Text(viewModel.isRecording ? viewModel.recordingTime : "Starting...")
                                        .monospacedDigit()
                                }
                            }
                            .disabled(viewModel.isStartingRecording)
                        } else if viewModel.isNewMeetingMode && viewModel.recordingSession?.playbackAudioFileURL == nil {
                            HStack(spacing: 8) {
                                Button(action: { viewModel.startRecording() }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "record.circle")
                                        Text("Record")
                                    }
                                }
                                .disabled(!captureMicrophone && !captureSystemAudio)

                                Button(action: {
                                    captureMicrophone.toggle()
                                    ModelSettings.captureMicrophone = captureMicrophone
                                }) {
                                    Image(systemName: captureMicrophone ? "mic.fill" : "mic.slash")
                                        .foregroundColor(captureMicrophone ? .blue : .secondary)
                                }
                                .buttonStyle(.plain)
                                .help(captureMicrophone ? "Microphone on" : "Microphone off")

                                Button(action: {
                                    captureSystemAudio.toggle()
                                    ModelSettings.captureSystemAudio = captureSystemAudio
                                }) {
                                    Image(systemName: captureSystemAudio ? "macbook" : "macbook")
                                        .foregroundColor(captureSystemAudio ? .blue : .secondary)
                                        .opacity(captureSystemAudio ? 1.0 : 0.4)
                                }
                                .buttonStyle(.plain)
                                .help(captureSystemAudio ? "System audio on (Teams, FaceTime)" : "System audio off")
                            }
                        } else if viewModel.recordingSession?.playbackAudioFileURL != nil {
                            Button(action: {
                                if viewModel.isPlaying {
                                    viewModel.pauseRecording()
                                } else {
                                    viewModel.playRecording()
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    Text(viewModel.isPlaying ? "Pause" : "Play")
                                }
                            }
                        }
                    }

                    // Tab picker
                    Picker("View", selection: $selectedTab) {
                        Text("Transcript").tag(0)
                        Text("Summary").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }

            ToolbarItem(placement: .automatic) {
                Button(action: {
                    showingSettings = true
                }) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .onChange(of: meetingStore.selectedMeetingId) { oldId, newId in
            if let id = newId, let meeting = meetingStore.meetings.first(where: { $0.id == id }) {
                viewModel.loadMeeting(meeting)
            } else if newId == nil {
                viewModel.prepareNewMeeting()
            }
        }
    }
}

#Preview {
    ContentView()
}
