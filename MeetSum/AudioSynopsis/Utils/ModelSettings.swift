//
//  ModelSettings.swift
//  Audio Synopsis
//
//  UserDefaults wrapper for model preferences
//

import Foundation

/// Which summarization engine to use
enum SummarizationEngine: String, CaseIterable, Identifiable {
    case mlx = "mlx"
    case appleIntelligence = "appleIntelligence"
    case gguf = "gguf"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mlx: return "MLX Model"
        case .appleIntelligence: return "Apple Intelligence"
        case .gguf: return "GGUF (llama.cpp)"
        }
    }

    var description: String {
        switch self {
        case .mlx: return "On-device MLX model (download required)"
        case .appleIntelligence: return "Built-in Apple Intelligence (no download needed)"
        case .gguf: return "GGUF model via bundled llama-server"
        }
    }
}

/// Summarization mode presets
enum SummarizationMode: String, CaseIterable, Identifiable {
    case general
    case meeting
    case lecture

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general: return "General"
        case .meeting: return "Meeting"
        case .lecture: return "Lecture"
        }
    }

    var defaultPrompt: String {
        switch self {
        case .general:
            return "You are a helpful assistant that summarizes audio transcriptions. Format your response in Markdown. Provide clear, concise bullet-point summaries that capture key topics and important details. Use headings, bold text, and lists for readability."
        case .meeting:
            return "You are a helpful assistant that summarizes meeting transcriptions. Format your response in Markdown. Provide clear, concise bullet-point summaries that capture key topics, decisions, and action items. Use headings, bold text, and lists for readability."
        case .lecture:
            return "You are a helpful assistant that summarizes lectures and speeches. Format your response in Markdown. Provide a structured overview with main themes, key arguments, supporting evidence, and notable quotes. Use headings, bold text, and lists for readability."
        }
    }
}

/// Which chat engine to use for the Chat tab
enum ChatEngine: String, CaseIterable, Identifiable {
    case mlx = "mlx"
    case gguf = "gguf"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mlx: return "MLX Model"
        case .gguf: return "GGUF (llama.cpp)"
        }
    }

    var description: String {
        switch self {
        case .mlx: return "On-device MLX model (same models as summarization)"
        case .gguf: return "GGUF model via bundled llama-server"
        }
    }
}

/// A user-added custom model referenced by file path (security-scoped bookmark)
struct CustomModelEntry: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let bookmarkData: Data

    /// Resolve the security-scoped bookmark to a URL
    func resolveURL() -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        return isStale ? nil : url
    }
}

/// UserDefaults storage for model preferences
struct ModelSettings {

    private static let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        static let modelDirectoryBookmark = "modelDirectoryBookmark"
        static let mlxModelDirectoryBookmark = "mlxModelDirectoryBookmark"
        static let selectedWhisperModel = "selectedWhisperModel"
        static let selectedMLXModel = "selectedMLXModel"
        static let summarizationEngine = "summarizationEngine"
        static let hasCompletedInitialSetup = "hasCompletedInitialSetup"
        static let summarizationSystemPrompt = "summarizationSystemPrompt"
        static let disableModelThinking = "disableModelThinking"
        static let captureSystemAudio = "captureSystemAudio"
        static let captureMicrophone = "captureMicrophone"
        static let transcriptionLanguage = "transcriptionLanguage"
        static let insertTimecodeInNotes = "insertTimecodeInNotes"
        static let maxOutputTokens = "maxOutputTokens"
        static let summarizationLanguage = "summarizationLanguage"
        static let summarizationMode = "summarizationMode"
        static let customWhisperModels = "customWhisperModels"
        static let customMLXModels = "customMLXModels"
        static let chatEngine = "chatEngine"
        static let selectedGGUFModel = "selectedGGUFModel"
        static let ggufContextSize = "ggufContextSize"
        static let customGGUFModels = "customGGUFModels"
        static let chatSystemPrompt = "chatSystemPrompt"
    }

    // MARK: - Defaults

    /// Returns the default prompt for the current summarization mode
    static var defaultSummarizationPrompt: String {
        summarizationMode.defaultPrompt
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

    static var mlxModelDirectoryBookmark: Data? {
        get {
            defaults.data(forKey: Keys.mlxModelDirectoryBookmark)
        }
        set {
            defaults.set(newValue, forKey: Keys.mlxModelDirectoryBookmark)
            Logger.info("MLX model directory bookmark saved", category: Logger.general)
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
            defaults.string(forKey: Keys.selectedMLXModel) ?? "mlx-community/Qwen3.5-4B-OptiQ-4bit"
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

    // MARK: - Summarization Mode

    static var summarizationMode: SummarizationMode {
        get {
            if let raw = defaults.string(forKey: Keys.summarizationMode),
               let mode = SummarizationMode(rawValue: raw) {
                return mode
            }
            return .general
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.summarizationMode)
        }
    }

    // MARK: - Summarization Prompt

    static var summarizationSystemPrompt: String {
        get {
            defaults.string(forKey: Keys.summarizationSystemPrompt) ?? defaultSummarizationPrompt
        }
        set {
            defaults.set(newValue, forKey: Keys.summarizationSystemPrompt)
        }
    }

    // MARK: - Model Thinking

    /// When enabled, appends /no_think to the system prompt to suppress thinking tokens (Qwen3)
    static var disableModelThinking: Bool {
        get {
            if defaults.object(forKey: Keys.disableModelThinking) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.disableModelThinking)
        }
        set {
            defaults.set(newValue, forKey: Keys.disableModelThinking)
            Logger.info("Disable model thinking: \(newValue)", category: Logger.general)
        }
    }

    // MARK: - Audio Capture

    /// Whether to capture microphone audio
    static var captureMicrophone: Bool {
        get {
            if defaults.object(forKey: Keys.captureMicrophone) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.captureMicrophone)
        }
        set {
            defaults.set(newValue, forKey: Keys.captureMicrophone)
            Logger.info("Capture microphone: \(newValue)", category: Logger.general)
        }
    }

    /// Whether to capture system audio (Teams, FaceTime, etc.)
    static var captureSystemAudio: Bool {
        get {
            if defaults.object(forKey: Keys.captureSystemAudio) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.captureSystemAudio)
        }
        set {
            defaults.set(newValue, forKey: Keys.captureSystemAudio)
            Logger.info("Capture system audio: \(newValue)", category: Logger.general)
        }
    }

    // MARK: - Notes

    /// Whether to auto-insert timecodes when pressing Enter in notes during recording
    static var insertTimecodeInNotes: Bool {
        get {
            if defaults.object(forKey: Keys.insertTimecodeInNotes) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.insertTimecodeInNotes)
        }
        set {
            defaults.set(newValue, forKey: Keys.insertTimecodeInNotes)
        }
    }

    // MARK: - Summarization Language

    /// Language preference for summary output ("auto", or a language name)
    static var summarizationLanguage: String {
        get {
            defaults.string(forKey: Keys.summarizationLanguage) ?? "auto"
        }
        set {
            defaults.set(newValue, forKey: Keys.summarizationLanguage)
            Logger.info("Summarization language: \(newValue)", category: Logger.general)
        }
    }

    /// Language options for summarization output
    static let summarizationLanguages: [(code: String, name: String)] = [
        ("auto", "Match transcript/notes language"),
        ("English", "English"),
        ("Chinese", "Chinese"),
        ("German", "German"),
        ("Spanish", "Spanish"),
        ("Russian", "Russian"),
        ("Korean", "Korean"),
        ("French", "French"),
        ("Japanese", "Japanese"),
        ("Portuguese", "Portuguese"),
        ("Dutch", "Dutch"),
        ("Italian", "Italian"),
        ("Swedish", "Swedish"),
        ("Danish", "Danish"),
        ("Norwegian", "Norwegian"),
        ("Finnish", "Finnish"),
        ("Polish", "Polish"),
    ]

    // MARK: - Output Token Limit

    /// Maximum number of tokens for summary output (default: 2000, range: 500-8000)
    static var maxOutputTokens: Int {
        get {
            let value = defaults.integer(forKey: Keys.maxOutputTokens)
            return value > 0 ? value : 2000
        }
        set {
            defaults.set(newValue, forKey: Keys.maxOutputTokens)
            Logger.info("Max output tokens: \(newValue)", category: Logger.general)
        }
    }

    // MARK: - Transcription Language

    /// Language code for Whisper transcription (e.g. "auto", "en", "no")
    static var transcriptionLanguage: String {
        get {
            defaults.string(forKey: Keys.transcriptionLanguage) ?? "auto"
        }
        set {
            defaults.set(newValue, forKey: Keys.transcriptionLanguage)
            Logger.info("Transcription language: \(newValue)", category: Logger.general)
        }
    }

    /// Supported Whisper languages with display names
    static let whisperLanguages: [(code: String, name: String)] = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("zh", "Chinese"),
        ("de", "German"),
        ("es", "Spanish"),
        ("ru", "Russian"),
        ("ko", "Korean"),
        ("fr", "French"),
        ("ja", "Japanese"),
        ("pt", "Portuguese"),
        ("tr", "Turkish"),
        ("pl", "Polish"),
        ("ca", "Catalan"),
        ("nl", "Dutch"),
        ("ar", "Arabic"),
        ("sv", "Swedish"),
        ("it", "Italian"),
        ("id", "Indonesian"),
        ("hi", "Hindi"),
        ("fi", "Finnish"),
        ("vi", "Vietnamese"),
        ("he", "Hebrew"),
        ("uk", "Ukrainian"),
        ("el", "Greek"),
        ("ms", "Malay"),
        ("cs", "Czech"),
        ("ro", "Romanian"),
        ("da", "Danish"),
        ("hu", "Hungarian"),
        ("ta", "Tamil"),
        ("no", "Norwegian"),
        ("th", "Thai"),
        ("ur", "Urdu"),
        ("hr", "Croatian"),
        ("bg", "Bulgarian"),
        ("lt", "Lithuanian"),
        ("la", "Latin"),
        ("mi", "Maori"),
        ("ml", "Malayalam"),
        ("cy", "Welsh"),
        ("sk", "Slovak"),
        ("te", "Telugu"),
        ("fa", "Persian"),
        ("lv", "Latvian"),
        ("bn", "Bengali"),
        ("sr", "Serbian"),
        ("az", "Azerbaijani"),
        ("sl", "Slovenian"),
        ("kn", "Kannada"),
        ("et", "Estonian"),
        ("mk", "Macedonian"),
        ("br", "Breton"),
        ("eu", "Basque"),
        ("is", "Icelandic"),
        ("hy", "Armenian"),
        ("ne", "Nepali"),
        ("mn", "Mongolian"),
        ("bs", "Bosnian"),
        ("kk", "Kazakh"),
        ("sq", "Albanian"),
        ("sw", "Swahili"),
        ("gl", "Galician"),
        ("mr", "Marathi"),
        ("pa", "Punjabi"),
        ("si", "Sinhala"),
        ("km", "Khmer"),
        ("sn", "Shona"),
        ("yo", "Yoruba"),
        ("so", "Somali"),
        ("af", "Afrikaans"),
        ("oc", "Occitan"),
        ("ka", "Georgian"),
        ("be", "Belarusian"),
        ("tg", "Tajik"),
        ("sd", "Sindhi"),
        ("gu", "Gujarati"),
        ("am", "Amharic"),
        ("yi", "Yiddish"),
        ("lo", "Lao"),
        ("uz", "Uzbek"),
        ("fo", "Faroese"),
        ("ht", "Haitian Creole"),
        ("ps", "Pashto"),
        ("tk", "Turkmen"),
        ("nn", "Nynorsk"),
        ("mt", "Maltese"),
        ("sa", "Sanskrit"),
        ("lb", "Luxembourgish"),
        ("my", "Myanmar"),
        ("bo", "Tibetan"),
        ("tl", "Tagalog"),
        ("mg", "Malagasy"),
        ("as", "Assamese"),
        ("tt", "Tatar"),
        ("haw", "Hawaiian"),
        ("ln", "Lingala"),
        ("ha", "Hausa"),
        ("ba", "Bashkir"),
        ("jw", "Javanese"),
        ("su", "Sundanese"),
    ]

    // MARK: - Custom Model Paths

    static var customWhisperModels: [CustomModelEntry] {
        get {
            guard let data = defaults.data(forKey: Keys.customWhisperModels) else { return [] }
            return (try? JSONDecoder().decode([CustomModelEntry].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            defaults.set(data, forKey: Keys.customWhisperModels)
        }
    }

    static var customMLXModels: [CustomModelEntry] {
        get {
            guard let data = defaults.data(forKey: Keys.customMLXModels) else { return [] }
            return (try? JSONDecoder().decode([CustomModelEntry].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            defaults.set(data, forKey: Keys.customMLXModels)
        }
    }

    // MARK: - Chat Engine

    static var chatEngine: ChatEngine {
        get {
            if let raw = defaults.string(forKey: Keys.chatEngine),
               let engine = ChatEngine(rawValue: raw) {
                return engine
            }
            return .mlx
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.chatEngine)
            Logger.info("Selected chat engine: \(newValue.displayName)", category: Logger.general)
        }
    }

    // MARK: - Selected GGUF Model

    static var selectedGGUFModel: String {
        get {
            defaults.string(forKey: Keys.selectedGGUFModel) ?? "qwen3.5-0.8b-q4_k_m"
        }
        set {
            defaults.set(newValue, forKey: Keys.selectedGGUFModel)
            Logger.info("Selected GGUF model: \(newValue)", category: Logger.general)
        }
    }

    // MARK: - GGUF Context Size

    /// Context window size for GGUF models (default: 4096, range: 512-131072)
    static var ggufContextSize: Int {
        get {
            let value = defaults.integer(forKey: Keys.ggufContextSize)
            return value > 0 ? value : 4096
        }
        set {
            defaults.set(newValue, forKey: Keys.ggufContextSize)
            Logger.info("GGUF context size: \(newValue)", category: Logger.general)
        }
    }

    // MARK: - Chat System Prompt

    static let defaultChatSystemPrompt = "You are a helpful AI assistant. Be concise, accurate, and helpful. When given context from a recording (transcript, notes, or summary), use it to inform your answers."

    static var chatSystemPrompt: String {
        get {
            defaults.string(forKey: Keys.chatSystemPrompt) ?? defaultChatSystemPrompt
        }
        set {
            defaults.set(newValue, forKey: Keys.chatSystemPrompt)
        }
    }

    // MARK: - Custom GGUF Models

    static var customGGUFModels: [CustomModelEntry] {
        get {
            guard let data = defaults.data(forKey: Keys.customGGUFModels) else { return [] }
            return (try? JSONDecoder().decode([CustomModelEntry].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            defaults.set(data, forKey: Keys.customGGUFModels)
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
        defaults.removeObject(forKey: Keys.mlxModelDirectoryBookmark)
        defaults.removeObject(forKey: Keys.selectedWhisperModel)
        defaults.removeObject(forKey: Keys.selectedMLXModel)
        defaults.removeObject(forKey: Keys.summarizationEngine)
        defaults.removeObject(forKey: Keys.hasCompletedInitialSetup)
        defaults.removeObject(forKey: Keys.summarizationSystemPrompt)
        defaults.removeObject(forKey: Keys.disableModelThinking)
        defaults.removeObject(forKey: Keys.captureSystemAudio)
        defaults.removeObject(forKey: Keys.captureMicrophone)
        defaults.removeObject(forKey: Keys.transcriptionLanguage)
        defaults.removeObject(forKey: Keys.insertTimecodeInNotes)
        defaults.removeObject(forKey: Keys.maxOutputTokens)
        defaults.removeObject(forKey: Keys.summarizationLanguage)
        defaults.removeObject(forKey: Keys.summarizationMode)
        defaults.removeObject(forKey: Keys.customWhisperModels)
        defaults.removeObject(forKey: Keys.customMLXModels)
        defaults.removeObject(forKey: Keys.chatEngine)
        defaults.removeObject(forKey: Keys.selectedGGUFModel)
        defaults.removeObject(forKey: Keys.ggufContextSize)
        defaults.removeObject(forKey: Keys.customGGUFModels)
        defaults.removeObject(forKey: Keys.chatSystemPrompt)
        Logger.info("Model settings reset", category: Logger.general)
    }
}
