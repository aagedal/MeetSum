//
//  MeetSumApp.swift
//  MeetSum
//
//  Created by Truls Aagedal on 24/11/2025.
//

import SwiftUI

@main
struct MeetSumApp: App {
    
    init() {
        Logger.info("MeetSum application starting", category: Logger.general)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    // Settings is now handled in ContentView via sheet
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
