//
//  MeetSumApp.swift
//  MeetSum
//
//  Created by Truls Aagedal on 24/11/2025.
//

import SwiftUI

@main
struct MeetSumApp: App {
    @StateObject private var modelManager = ModelManager()
    @StateObject private var meetingStore = MeetingStore()

    init() {
        Logger.info("MeetSum application starting", category: Logger.general)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(modelManager: modelManager, meetingStore: meetingStore)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsCommand()
            }
        }

        Window("Settings", id: "settings") {
            SettingsView()
                .environmentObject(modelManager)
        }
        .defaultSize(width: 650, height: 550)
        .windowResizability(.contentSize)
    }
}

/// Helper view to open the settings window from the menu bar (Cmd+,)
private struct SettingsCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Settings...") {
            openWindow(id: "settings")
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}
