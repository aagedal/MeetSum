//
//  ModelSettings.swift
//  MeetSum
//
//  UserDefaults wrapper for model preferences
//

import Foundation

/// Which summarization engine to use
enum SummarizationEngine: String, CaseIterable, Identifiable {
    case mlx = "mlx"
    case appleIntelligence = "appleIntelligence"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mlx: return "MLX Model"
        case .appleIntelligence: return "Apple Intelligence"
        }
    }

    var description: String {
        switch self {
        case .mlx: return "On-device MLX model (download required)"
        case .appleIntelligence: return "Built-in Apple Intelligence (no download needed)"
        }
    }
}

/// UserDefaults storage for model preferences
struct ModelSettings {

    private static let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        static let modelDirectoryBookmark = "modelDirectoryBookmark"
        static let selectedWhisperModel = "selectedWhisperModel"
        static let selectedMLXModel = "selectedMLXModel"
        static let summarizationEngine = "summarizationEngine"
        static let hasCompletedInitialSetup = "hasCompletedInitialSetup"
    }

    // MARK: - Model Directory Bookmark

    static var modelDirectoryBookmark: Data? {
        get {
            defaults.data(forKey: Keys.modelDirectoryBookmark)
        }
        set {
            defaults.set(newValue, forKey: Keys.modelDirectoryBookmark)
            Logger.info("Model directory bookmark saved", category: Logger.general)
        }
    }

    // MARK: - Selected Models

    static var selectedWhisperModel: String {
        get {
            defaults.string(forKey: Keys.selectedWhisperModel) ?? "whisper-base"
        }
        set {
            defaults.set(newValue, forKey: Keys.selectedWhisperModel)
            Logger.info("Selected Whisper model: \(newValue)", category: Logger.general)
        }
    }

    static var selectedMLXModel: String {
        get {
            defaults.string(forKey: Keys.selectedMLXModel) ?? "mlx-community/Qwen3-4B-4bit"
        }
        set {
            defaults.set(newValue, forKey: Keys.selectedMLXModel)
            Logger.info("Selected MLX model: \(newValue)", category: Logger.general)
        }
    }

    // MARK: - Summarization Engine

    static var summarizationEngine: SummarizationEngine {
        get {
            if let raw = defaults.string(forKey: Keys.summarizationEngine),
               let engine = SummarizationEngine(rawValue: raw) {
                return engine
            }
            return .appleIntelligence
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.summarizationEngine)
            Logger.info("Selected summarization engine: \(newValue.displayName)", category: Logger.general)
        }
    }

    // MARK: - Setup Status

    static var hasCompletedInitialSetup: Bool {
        get {
            defaults.bool(forKey: Keys.hasCompletedInitialSetup)
        }
        set {
            defaults.set(newValue, forKey: Keys.hasCompletedInitialSetup)
            Logger.info("Initial setup completed: \(newValue)", category: Logger.general)
        }
    }

    // MARK: - Reset

    static func reset() {
        defaults.removeObject(forKey: Keys.modelDirectoryBookmark)
        defaults.removeObject(forKey: Keys.selectedWhisperModel)
        defaults.removeObject(forKey: Keys.selectedMLXModel)
        defaults.removeObject(forKey: Keys.summarizationEngine)
        defaults.removeObject(forKey: Keys.hasCompletedInitialSetup)
        Logger.info("Model settings reset", category: Logger.general)
    }
}
