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

    init() {
        let modelMgr = ModelManager()
        let store = MeetingStore()
        _modelManager = StateObject(wrappedValue: modelMgr)
        _meetingStore = StateObject(wrappedValue: store)
        _viewModel = StateObject(wrappedValue: MeetingViewModel(modelManager: modelMgr, meetingStore: store))
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(meetingStore: meetingStore) {
                viewModel.prepareNewMeeting()
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            MeetingDetailView(
                viewModel: viewModel,
                modelManager: modelManager,
                showingSettings: $showingSettings
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
