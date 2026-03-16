//
//  ModelMetadata.swift
//  Audio Synopsis
//
//  Model definitions for downloadable models
//

import Foundation

/// Type of AI model
enum ModelType: String, Codable {
    case whisper
    case mlx
    case gguf

    var displayName: String {
        switch self {
        case .whisper: return "Whisper (Speech-to-Text)"
        case .mlx: return "MLX (Summarization/Chat)"
        case .gguf: return "GGUF (Chat via llama.cpp)"
        }
    }
}

/// Category for whisper models (used for filtering in the UI)
enum WhisperModelCategory: String, CaseIterable, Identifiable, Codable {
    case general = "General"
    case norwegian = "Norwegian"
    case swedish = "Swedish"

    var id: String { rawValue }
}

/// Metadata for a downloadable AI model
struct ModelMetadata: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let type: ModelType
    let filename: String
    let downloadURL: URL
    let sizeBytes: Int64
    let description: String

    /// HuggingFace model ID for MLX models (used by MLXLLM)
    let huggingFaceId: String?

    /// Context window size in tokens (nil for Whisper models)
    let contextWindowTokens: Int?

    /// Category for whisper models (nil for MLX models)
    let whisperCategory: WhisperModelCategory?

    var sizeMB: Double {
        Double(sizeBytes) / 1_048_576.0
    }

    var sizeFormatted: String {
        if sizeMB < 1024 {
            return String(format: "%.1f MB", sizeMB)
        } else {
            return String(format: "%.2f GB", sizeMB / 1024.0)
        }
    }

    init(id: String, name: String, type: ModelType, filename: String, downloadURL: URL, sizeBytes: Int64, description: String, huggingFaceId: String? = nil, contextWindowTokens: Int? = nil, whisperCategory: WhisperModelCategory? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.filename = filename
        self.downloadURL = downloadURL
        self.sizeBytes = sizeBytes
        self.description = description
        self.huggingFaceId = huggingFaceId
        self.contextWindowTokens = contextWindowTokens
        self.whisperCategory = whisperCategory
    }

    // MARK: - Whisper Models (General)

    static let whisperTiny = ModelMetadata(
        id: "whisper-tiny",
        name: "Whisper Tiny",
        type: .whisper,
        filename: "ggml-tiny.bin",
        downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin")!,
        sizeBytes: 77_691_713,
        description: "Fast, lightweight model. Good for quick transcriptions.",
        whisperCategory: .general
    )

    static let whisperBase = ModelMetadata(
        id: "whisper-base",
        name: "Whisper Base",
        type: .whisper,
        filename: "ggml-base.bin",
        downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!,
        sizeBytes: 147_964_211,
        description: "Better accuracy than Tiny. Recommended for most users.",
        whisperCategory: .general
    )

    static let whisperSmall = ModelMetadata(
        id: "whisper-small",
        name: "Whisper Small",
        type: .whisper,
        filename: "ggml-small.bin",
        downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin")!,
        sizeBytes: 488_281_415,
        description: "High accuracy. Slower but more accurate transcriptions.",
        whisperCategory: .general
    )

    static let whisperMedium = ModelMetadata(
        id: "whisper-medium",
        name: "Whisper Medium",
        type: .whisper,
        filename: "ggml-medium.bin",
        downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin")!,
        sizeBytes: 1_533_000_000,
        description: "Very high accuracy. Significant quality jump over Small.",
        whisperCategory: .general
    )

    static let whisperLargeV3 = ModelMetadata(
        id: "whisper-large-v3",
        name: "Whisper Large v3",
        type: .whisper,
        filename: "ggml-large-v3.bin",
        downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin")!,
        sizeBytes: 3_090_000_000,
        description: "Best accuracy. Largest model, slowest but highest quality.",
        whisperCategory: .general
    )

    static let whisperLargeV3Turbo = ModelMetadata(
        id: "whisper-large-v3-turbo",
        name: "Whisper Large v3 Turbo",
        type: .whisper,
        filename: "ggml-large-v3-turbo.bin",
        downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!,
        sizeBytes: 1_533_000_000,
        description: "Near-Large accuracy at Medium speed. Great quality/speed tradeoff.",
        whisperCategory: .general
    )

    // MARK: - Whisper Models (Norwegian)

    static let whisperNbTiny = ModelMetadata(
        id: "whisper-nb-tiny",
        name: "Norwegian Whisper Tiny",
        type: .whisper,
        filename: "ggml-nb-tiny.bin",
        downloadURL: URL(string: "https://huggingface.co/NbAiLab/nb-whisper-tiny/resolve/main/ggml-model.bin")!,
        sizeBytes: 77_691_713,
        description: "Norwegian optimized (Tiny). Fast, lightweight.",
        whisperCategory: .norwegian
    )

    static let whisperNbBase = ModelMetadata(
        id: "whisper-nb-base",
        name: "Norwegian Whisper Base",
        type: .whisper,
        filename: "ggml-nb-base.bin",
        downloadURL: URL(string: "https://huggingface.co/NbAiLab/nb-whisper-base/resolve/main/ggml-model.bin")!,
        sizeBytes: 147_964_211,
        description: "Norwegian optimized (Base). Good balance of speed and accuracy.",
        whisperCategory: .norwegian
    )

    static let whisperNbSmall = ModelMetadata(
        id: "whisper-nb-small",
        name: "Norwegian Whisper Small",
        type: .whisper,
        filename: "ggml-nb-small.bin",
        downloadURL: URL(string: "https://huggingface.co/NbAiLab/nb-whisper-small/resolve/main/ggml-model.bin")!,
        sizeBytes: 488_281_415,
        description: "Norwegian optimized (Small). Better accuracy for Norwegian audio.",
        whisperCategory: .norwegian
    )

    static let whisperNbMedium = ModelMetadata(
        id: "whisper-nb-medium",
        name: "Norwegian Whisper Medium",
        type: .whisper,
        filename: "ggml-nb-medium.bin",
        downloadURL: URL(string: "https://huggingface.co/NbAiLab/nb-whisper-medium/resolve/main/ggml-model.bin")!,
        sizeBytes: 1_533_000_000,
        description: "Norwegian optimized (Medium). High accuracy for Norwegian audio.",
        whisperCategory: .norwegian
    )

    static let whisperNbLarge = ModelMetadata(
        id: "whisper-nb-large",
        name: "Norwegian Whisper Large",
        type: .whisper,
        filename: "ggml-nb-large.bin",
        downloadURL: URL(string: "https://huggingface.co/NbAiLab/nb-whisper-large/resolve/main/ggml-model.bin")!,
        sizeBytes: 3_090_000_000,
        description: "Norwegian optimized (Large). Best accuracy for Norwegian.",
        whisperCategory: .norwegian
    )

    // MARK: - Whisper Models (Swedish)

    static let whisperSvTiny = ModelMetadata(
        id: "whisper-sv-tiny",
        name: "Swedish Whisper Tiny",
        type: .whisper,
        filename: "ggml-sv-tiny.bin",
        downloadURL: URL(string: "https://huggingface.co/KBLab/kb-whisper-tiny/resolve/main/ggml-model.bin")!,
        sizeBytes: 77_691_713,
        description: "Swedish optimized (Tiny). Fast, lightweight.",
        whisperCategory: .swedish
    )

    static let whisperSvBase = ModelMetadata(
        id: "whisper-sv-base",
        name: "Swedish Whisper Base",
        type: .whisper,
        filename: "ggml-sv-base.bin",
        downloadURL: URL(string: "https://huggingface.co/KBLab/kb-whisper-base/resolve/main/ggml-model.bin")!,
        sizeBytes: 147_964_211,
        description: "Swedish optimized (Base). Good balance of speed and accuracy.",
        whisperCategory: .swedish
    )

    static let whisperSvSmall = ModelMetadata(
        id: "whisper-sv-small",
        name: "Swedish Whisper Small",
        type: .whisper,
        filename: "ggml-sv-small.bin",
        downloadURL: URL(string: "https://huggingface.co/KBLab/kb-whisper-small/resolve/main/ggml-model.bin")!,
        sizeBytes: 488_281_415,
        description: "Swedish optimized (Small). Better accuracy for Swedish audio.",
        whisperCategory: .swedish
    )

    static let whisperSvMedium = ModelMetadata(
        id: "whisper-sv-medium",
        name: "Swedish Whisper Medium",
        type: .whisper,
        filename: "ggml-sv-medium.bin",
        downloadURL: URL(string: "https://huggingface.co/KBLab/kb-whisper-medium/resolve/main/ggml-model.bin")!,
        sizeBytes: 1_533_000_000,
        description: "Swedish optimized (Medium). High accuracy for Swedish audio.",
        whisperCategory: .swedish
    )

    static let whisperSvLarge = ModelMetadata(
        id: "whisper-sv-large",
        name: "Swedish Whisper Large",
        type: .whisper,
        filename: "ggml-sv-large.bin",
        downloadURL: URL(string: "https://huggingface.co/KBLab/kb-whisper-large/resolve/main/ggml-model.bin")!,
        sizeBytes: 3_090_000_000,
        description: "Swedish optimized (Large). Best accuracy for Swedish.",
        whisperCategory: .swedish
    )

    // MARK: - MLX Summarization Models

    static let qwen35_4b_mlx = ModelMetadata(
        id: "qwen3.5-4b-optiq-4bit",
        name: "Qwen3.5 4B OptiQ 4-bit",
        type: .mlx,
        filename: "",
        downloadURL: URL(string: "https://huggingface.co/mlx-community/Qwen3.5-4B-OptiQ-4bit")!,
        sizeBytes: 2_950_000_000,
        description: "Compact and fast. Mixed-precision quantization for better quality. ~3GB memory.",
        huggingFaceId: "mlx-community/Qwen3.5-4B-OptiQ-4bit",
        contextWindowTokens: 262_144
    )

    static let gptOss20b_mlx = ModelMetadata(
        id: "gpt-oss-20b-mxfp4-q4",
        name: "GPT-OSS 20B MXFP4-Q4",
        type: .mlx,
        filename: "",
        downloadURL: URL(string: "https://huggingface.co/mlx-community/gpt-oss-20b-MXFP4-Q4")!,
        sizeBytes: 11_000_000_000,
        description: "High quality summaries. Requires ~12GB memory. Slower but more capable.",
        huggingFaceId: "mlx-community/gpt-oss-20b-MXFP4-Q4",
        contextWindowTokens: 32_768
    )

    static let qwen35_9b_mlx = ModelMetadata(
        id: "qwen3.5-9b-4bit",
        name: "Qwen3.5 9B 4-bit",
        type: .mlx,
        filename: "",
        downloadURL: URL(string: "https://huggingface.co/mlx-community/Qwen3.5-9B-MLX-4bit")!,
        sizeBytes: 5_500_000_000,
        description: "Mid-size model. Higher quality than 4B with moderate memory use. ~6GB memory.",
        huggingFaceId: "mlx-community/Qwen3.5-9B-MLX-4bit",
        contextWindowTokens: 131_072
    )

    static let gemma3_12b_mlx = ModelMetadata(
        id: "gemma-3-12b-it-4bit",
        name: "Gemma 3 12B IT 4-bit",
        type: .mlx,
        filename: "",
        downloadURL: URL(string: "https://huggingface.co/mlx-community/gemma-3-12b-it-4bit")!,
        sizeBytes: 7_600_000_000,
        description: "Google's Gemma 3 instruction-tuned. Strong summarization quality. ~8GB memory.",
        huggingFaceId: "mlx-community/gemma-3-12b-it-4bit",
        contextWindowTokens: 131_072
    )

    static let qwen35_35b_mlx = ModelMetadata(
        id: "qwen3.5-35b-a3b-4bit",
        name: "Qwen3.5 35B-A3B 4-bit",
        type: .mlx,
        filename: "",
        downloadURL: URL(string: "https://huggingface.co/mlx-community/Qwen3.5-35B-A3B-4bit")!,
        sizeBytes: 20_400_000_000,
        description: "MoE vision-language model — 35B total, ~3B active. ~20GB download. Requires mlx-vlm.",
        huggingFaceId: "mlx-community/Qwen3.5-35B-A3B-4bit",
        contextWindowTokens: 262_144
    )

    // MARK: - GGUF Models (Chat via llama.cpp)

    static let llama31_8b_q4 = ModelMetadata(
        id: "llama-3.1-8b-q4_k_m",
        name: "Llama 3.1 8B Q4_K_M",
        type: .gguf,
        filename: "Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf",
        downloadURL: URL(string: "https://huggingface.co/bartowski/Meta-Llama-3.1-8B-Instruct-GGUF/resolve/main/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf")!,
        sizeBytes: 4_920_000_000,
        description: "Meta's Llama 3.1 8B quantized. Great quality/speed balance. ~5GB.",
        contextWindowTokens: 131_072
    )

    static let qwen25_7b_q4 = ModelMetadata(
        id: "qwen2.5-7b-q4_k_m",
        name: "Qwen2.5 7B Q4_K_M",
        type: .gguf,
        filename: "Qwen2.5-7B-Instruct-Q4_K_M.gguf",
        downloadURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF/resolve/main/qwen2.5-7b-instruct-q4_k_m.gguf")!,
        sizeBytes: 4_680_000_000,
        description: "Alibaba's Qwen2.5 7B quantized. Strong multilingual support. ~4.7GB.",
        contextWindowTokens: 131_072
    )

    static let mistral_7b_q4 = ModelMetadata(
        id: "mistral-7b-v0.3-q4_k_m",
        name: "Mistral 7B v0.3 Q4_K_M",
        type: .gguf,
        filename: "Mistral-7B-Instruct-v0.3-Q4_K_M.gguf",
        downloadURL: URL(string: "https://huggingface.co/bartowski/Mistral-7B-Instruct-v0.3-GGUF/resolve/main/Mistral-7B-Instruct-v0.3-Q4_K_M.gguf")!,
        sizeBytes: 4_370_000_000,
        description: "Mistral AI 7B v0.3 quantized. Fast and capable. ~4.4GB.",
        contextWindowTokens: 32_768
    )

    static let allModels: [ModelMetadata] = [
        // General Whisper
        whisperTiny,
        whisperBase,
        whisperSmall,
        whisperMedium,
        whisperLargeV3Turbo,
        whisperLargeV3,
        // Norwegian Whisper
        whisperNbTiny,
        whisperNbBase,
        whisperNbSmall,
        whisperNbMedium,
        whisperNbLarge,
        // Swedish Whisper
        whisperSvTiny,
        whisperSvBase,
        whisperSvSmall,
        whisperSvMedium,
        whisperSvLarge,
        // MLX
        qwen35_4b_mlx,
        qwen35_9b_mlx,
        qwen35_35b_mlx,
        gemma3_12b_mlx,
        gptOss20b_mlx,
        // GGUF
        llama31_8b_q4,
        qwen25_7b_q4,
        mistral_7b_q4
    ]

    static let recommendedModels: [ModelMetadata] = [
        whisperBase,
        qwen35_4b_mlx
    ]

    /// Returns whisper models filtered by category
    static func whisperModels(for category: WhisperModelCategory) -> [ModelMetadata] {
        allModels.filter { $0.type == .whisper && $0.whisperCategory == category }
    }

    /// Returns all GGUF models
    static var ggufModels: [ModelMetadata] {
        allModels.filter { $0.type == .gguf }
    }

    /// Returns the context window size for the currently selected MLX model, defaulting to 32,768
    static func contextWindowForCurrentModel() -> Int {
        let selectedId = ModelSettings.selectedMLXModel
        if let model = allModels.first(where: { $0.huggingFaceId == selectedId || $0.id == selectedId }) {
            return model.contextWindowTokens ?? 32_768
        }
        return 32_768
    }
}
