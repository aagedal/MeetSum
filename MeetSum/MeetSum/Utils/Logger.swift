//
//  Logger.swift
//  MeetSum
//
//  Centralized logging utility
//

import Foundation
import os.log

/// Centralized logging utility for MeetSum
/// Provides structured logging with different levels and categories
struct Logger {
    
    // MARK: - Log Categories
    
    /// Audio recording and playback operations
    static let audio = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "MeetSum", category: "Audio")
    
    /// Transcription operations
    static let transcription = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "MeetSum", category: "Transcription")
    
    /// User interface operations
    static let ui = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "MeetSum", category: "UI")
    
    /// Processing operations (summarization, etc.)
    static let processing = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "MeetSum", category: "Processing")
    
    /// General application operations
    static let general = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "MeetSum", category: "General")
    
    // MARK: - Logging Methods
    
    /// Log debug information (DEBUG builds only)
    /// - Parameters:
    ///   - message: The message to log
    ///   - category: The log category (defaults to general)
    ///   - file: The file name (automatically filled)
    ///   - function: The function name (automatically filled)
    ///   - line: The line number (automatically filled)
    static func debug(
        _ message: String,
        category: OSLog = Logger.general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        os_log(.debug, log: category, "%{public}@:%{public}@:%d - %{public}@",
               fileName, function, line, message)
        #endif
    }
    
    /// Log general information
    /// - Parameters:
    ///   - message: The message to log
    ///   - category: The log category (defaults to general)
    ///   - file: The file name (automatically filled)
    ///   - function: The function name (automatically filled)
    ///   - line: The line number (automatically filled)
    static func info(
        _ message: String,
        category: OSLog = Logger.general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        os_log(.info, log: category, "%{public}@:%{public}@:%d - %{public}@",
               fileName, function, line, message)
    }
    
    /// Log warnings
    /// - Parameters:
    ///   - message: The message to log
    ///   - category: The log category (defaults to general)
    ///   - file: The file name (automatically filled)
    ///   - function: The function name (automatically filled)
    ///   - line: The line number (automatically filled)
    static func warning(
        _ message: String,
        category: OSLog = Logger.general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        os_log(.default, log: category, "⚠️ %{public}@:%{public}@:%d - %{public}@",
               fileName, function, line, message)
    }
    
    /// Log errors
    /// - Parameters:
    ///   - message: The message to log
    ///   - error: Optional error object for additional context
    ///   - category: The log category (defaults to general)
    ///   - file: The file name (automatically filled)
    ///   - function: The function name (automatically filled)
    ///   - line: The line number (automatically filled)
    static func error(
        _ message: String,
        error: Error? = nil,
        category: OSLog = Logger.general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let errorDescription = error?.localizedDescription ?? ""
        let fullMessage = errorDescription.isEmpty ? message : "\(message) - \(errorDescription)"
        os_log(.error, log: category, "❌ %{public}@:%{public}@:%d - %{public}@",
               fileName, function, line, fullMessage)
    }
}
