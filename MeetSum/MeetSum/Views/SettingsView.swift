//
//  SettingsView.swift
//  MeetSum
//
//  Settings window for model management
//

import SwiftUI
import UniformTypeIdentifiers
import Combine
import MLXLLM
import MLXLMCommon

struct SettingsView: View {
    @EnvironmentObject var modelManager: ModelManager

    @State private var showingWhisperDirectoryPicker = false
    @State private var showingMLXDirectoryPicker = false
    @State private var showingModelImporter = false
    @State private var downloadingModels: Set<String> = []
    @State private var selectedEngine: SummarizationEngine = ModelSettings.summarizationEngine
    @State private var customPrompt: String = ModelSettings.summarizationSystemPrompt
    @StateObject private var mlxLoader = MLXModelLoader()

    var body: some View {
        TabView {
            // General tab
            ScrollView {
                VStack(spacing: 24) {
                    whisperDirectorySection
                    Divider()
                    mlxDirectorySection
                    Divider()
                    dataDirectorySection
                }
                .padding()
            }
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            // Transcription tab
            ScrollView {
                VStack(spacing: 24) {
                    installedModelsSection

                    if !modelManager.customModels.isEmpty {
                        Divider()
                        customModelsSection
                    }

                    Divider()
                    availableWhisperModelsSection
                }
                .padding()
            }
            .tabItem {
                Label("Transcription", systemImage: "waveform")
            }

            // Summarization tab
            ScrollView {
                VStack(spacing: 24) {
                    summarizationEngineSection

                    if selectedEngine == .mlx {
                        Divider()
                        mlxModelSection
                    }

                    Divider()
                    summarizationPromptSection
                }
                .padding()
            }
            .tabItem {
                Label("Summarization", systemImage: "sparkles")
            }
        }
        .frame(width: 620, height: 520)
        .fileImporter(
            isPresented: $showingWhisperDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleWhisperDirectorySelection(result)
        }
        .fileImporter(
            isPresented: $showingMLXDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleMLXDirectorySelection(result)
        }
        .fileImporter(
            isPresented: $showingModelImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            handleModelImport(result)
        }
    }

    // MARK: - Whisper Directory Section

    private var whisperDirectorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Whisper Model Directory", systemImage: "folder.fill")
                .font(.headline)

            Text("Directory for Whisper speech-to-text model files (.bin).")
                .font(.caption)
                .foregroundColor(.secondary)

            if let directory = modelManager.whisperModelDirectory {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(directory.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)

                        if let diskSpace = modelManager.whisperAvailableDiskSpace {
                            Text("Available: \(ByteCountFormatter.string(fromByteCount: diskSpace, countStyle: .file))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button("Open in Finder") {
                        NSWorkspace.shared.open(directory)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Change...") {
                        showingWhisperDirectoryPicker = true
                    }
                    .controlSize(.small)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            } else {
                Button("Select Whisper Models Directory") {
                    showingWhisperDirectoryPicker = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - MLX Directory Section

    private var mlxDirectorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("MLX Model Directory", systemImage: "folder.fill")
                .font(.headline)

            Text("Directory for MLX summarization model caches. Point this to an existing HuggingFace cache to reuse downloads from other apps.")
                .font(.caption)
                .foregroundColor(.secondary)

            if let directory = modelManager.mlxModelDirectory {
                HStack {
                    Text(directory.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button("Open in Finder") {
                        NSWorkspace.shared.open(directory)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Change...") {
                        showingMLXDirectoryPicker = true
                    }
                    .controlSize(.small)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            } else {
                Button("Select MLX Models Directory") {
                    showingMLXDirectoryPicker = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Installed Models Section

    private var installedWhisperModels: [ModelMetadata] {
        modelManager.availableModels.filter { modelManager.isModelInstalled($0.id) && $0.type == .whisper }
    }

    private var installedModelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Installed Whisper Models", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundColor(.green)

            if installedWhisperModels.isEmpty && modelManager.customModels.isEmpty {
                Text("No Whisper models installed")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(installedWhisperModels) { model in
                    installedModelRow(model)
                }
            }
        }
    }

    private func installedModelRow(_ model: ModelMetadata) -> some View {
        HStack {
            Image(systemName: "waveform")
                .foregroundColor(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(.subheadline.weight(.medium))
                Text(model.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(model.sizeFormatted)
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: {
                deleteModel(model)
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Custom Models Section

    private var customModelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Custom Models", systemImage: "doc.badge.gearshape")
                .font(.headline)

            Text("Models discovered in your model directory that aren't in the built-in list.")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(modelManager.customModels) { model in
                customModelRow(model)
            }
        }
    }

    private func customModelRow(_ model: ModelMetadata) -> some View {
        HStack {
            Image(systemName: "waveform")
                .foregroundColor(.orange)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(.subheadline.weight(.medium))
                Text(model.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(model.sizeFormatted)
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: {
                deleteModel(model)
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Summarization Engine Section

    private var summarizationEngineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Summarization Engine", systemImage: "cpu")
                .font(.headline)

            Text("Choose how meeting transcriptions are summarized.")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(SummarizationEngine.allCases) { engine in
                engineRow(engine)
            }
        }
    }

    private func engineRow(_ engine: SummarizationEngine) -> some View {
        let isSelected = selectedEngine == engine

        return HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .green : .secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(engine.displayName)
                        .font(.subheadline.weight(.medium))
                    if engine == .appleIntelligence {
                        Image(systemName: "apple.logo")
                            .font(.caption)
                    }
                }
                Text(engine.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !isSelected {
                Button("Select") {
                    selectedEngine = engine
                    ModelSettings.summarizationEngine = engine
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.05) : Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - MLX Model Section

    private var mlxModelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("MLX Model Selection", systemImage: "brain")
                .font(.headline)

            Text("Select a model for meeting summarization. The model will be downloaded on first use.")
                .font(.caption)
                .foregroundColor(.secondary)

            let mlxModels = ModelMetadata.allModels.filter { $0.type == .mlx }
            ForEach(mlxModels) { model in
                mlxModelRow(model)
            }

            if let error = mlxLoader.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private func mlxModelRow(_ model: ModelMetadata) -> some View {
        let isSelected = ModelSettings.selectedMLXModel == (model.huggingFaceId ?? model.id)
        let isCached = isMLXModelCached(model)

        return VStack(spacing: 0) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .green : .secondary)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.subheadline.weight(.medium))
                    Text(model.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        Text("Size: ~\(model.sizeFormatted)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if isCached {
                            Text("Downloaded")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                }

                Spacer()

                if !isSelected {
                    Button("Select") {
                        if let hfId = model.huggingFaceId {
                            ModelSettings.selectedMLXModel = hfId
                            mlxLoader.reset()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if mlxLoader.isLoading {
                    VStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(mlxLoader.status)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else if mlxLoader.isLoaded {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Ready")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                } else {
                    Button(isCached ? "Verify" : "Download") {
                        Task {
                            await mlxLoader.downloadAndLoad()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            // Cache management row for selected model
            if isSelected && isCached && !mlxLoader.isLoading {
                HStack {
                    Spacer()

                    Button("Open in Finder") {
                        if let dir = mlxModelCacheDirectory(model) {
                            NSWorkspace.shared.open(dir)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    Button("Clear Cache") {
                        clearMLXModelCache(model)
                        mlxLoader.reset()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(.red)
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.05) : Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Available Whisper Models Section

    private var availableWhisperModelsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Available Whisper Downloads", systemImage: "arrow.down.circle")
                    .font(.headline)

                Spacer()

                Button(action: {
                    showingModelImporter = true
                }) {
                    Label("Import Model...", systemImage: "doc.badge.plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ForEach(modelManager.availableModels.filter { $0.type == .whisper }) { model in
                availableModelRow(model)
            }
        }
    }

    private func availableModelRow(_ model: ModelMetadata) -> some View {
        let isDownloading = modelManager.downloadProgress[model.id] != nil

        return VStack(spacing: 0) {
            // Top row: model info + action button
            HStack {
                Image(systemName: "waveform")
                    .foregroundColor(.blue)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.subheadline.weight(.medium))
                    Text(model.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(model.sizeFormatted)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)

                if modelManager.isModelInstalled(model.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if isDownloading {
                    Button(action: {
                        modelManager.cancelDownload(for: model.id)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: {
                        downloadModel(model)
                    }) {
                        Label("Download", systemImage: "arrow.down.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            // Progress bar + details below the model info row
            if let progress = modelManager.downloadProgress[model.id] {
                VStack(spacing: 6) {
                    ProgressView(value: progress.fractionCompleted)
                        .progressViewStyle(.linear)

                    HStack {
                        Text("\(progress.downloadedFormatted) of \(progress.totalFormatted)")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Spacer()

                        if progress.bytesPerSecond > 0 {
                            Text(progress.speedFormatted)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Text("\(progress.percentComplete)%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Data Directory Section

    private var dataDirectorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Data Directory", systemImage: "internaldrive")
                .font(.headline)

            Text("Recordings, transcripts, and meeting data are stored here.")
                .font(.caption)
                .foregroundColor(.secondary)

            if let dir = try? AudioUtils.getRecordingsDirectory().deletingLastPathComponent() {
                HStack {
                    Text(dir.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button("Open in Finder") {
                        NSWorkspace.shared.open(dir)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Summarization Prompt Section

    private var summarizationPromptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Summarization Prompt", systemImage: "text.bubble")
                .font(.headline)

            Text("Customize the system prompt used when generating meeting summaries.")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $customPrompt)
                .font(.system(.body, design: .monospaced))
                .frame(height: 100)
                .padding(4)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                )
                .onChange(of: customPrompt) { _, newValue in
                    ModelSettings.summarizationSystemPrompt = newValue
                }

            HStack {
                Spacer()
                if customPrompt != ModelSettings.defaultSummarizationPrompt {
                    Button("Reset to Default") {
                        customPrompt = ModelSettings.defaultSummarizationPrompt
                        ModelSettings.summarizationSystemPrompt = customPrompt
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - MLX Cache Helpers

    private func mlxModelCacheDirectory(_ model: ModelMetadata) -> URL? {
        guard let hfId = model.huggingFaceId else { return nil }
        guard let mlxDir = modelManager.mlxModelDirectory else { return nil }
        return mlxDir.appendingPathComponent(hfId)
    }

    private func isMLXModelCached(_ model: ModelMetadata) -> Bool {
        guard let dir = mlxModelCacheDirectory(model) else { return false }
        return FileManager.default.fileExists(atPath: dir.path)
    }

    private func clearMLXModelCache(_ model: ModelMetadata) {
        guard let dir = mlxModelCacheDirectory(model) else { return }
        do {
            try FileManager.default.removeItem(at: dir)
            Logger.info("Cleared MLX cache for \(model.name) at \(dir.path)", category: Logger.ui)
        } catch {
            Logger.error("Failed to clear MLX cache for \(model.name)", error: error, category: Logger.ui)
        }
    }

    // MARK: - Actions

    private func handleWhisperDirectorySelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            modelManager.setWhisperModelDirectory(url)
            Logger.info("User selected Whisper model directory: \(url.path)", category: Logger.ui)

        case .failure(let error):
            Logger.error("Failed to select Whisper directory", error: error, category: Logger.ui)
        }
    }

    private func handleMLXDirectorySelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            modelManager.setMLXModelDirectory(url)
            Logger.info("User selected MLX model directory: \(url.path)", category: Logger.ui)

        case .failure(let error):
            Logger.error("Failed to select MLX directory", error: error, category: Logger.ui)
        }
    }

    private func handleModelImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                do {
                    try modelManager.importModel(from: url)
                    Logger.info("Imported model: \(url.lastPathComponent)", category: Logger.ui)
                } catch {
                    Logger.error("Failed to import model: \(url.lastPathComponent)", error: error, category: Logger.ui)
                }
            }
        case .failure(let error):
            Logger.error("Model import picker failed", error: error, category: Logger.ui)
        }
    }

    private func downloadModel(_ model: ModelMetadata) {
        Logger.info("User initiated download for: \(model.name)", category: Logger.ui)
        downloadingModels.insert(model.id)

        Task {
            do {
                try await modelManager.downloadModel(model)
                await MainActor.run {
                    downloadingModels.remove(model.id)
                }
            } catch {
                Logger.error("Download failed for \(model.name)", error: error, category: Logger.ui)
                await MainActor.run {
                    downloadingModels.remove(model.id)
                }
            }
        }
    }

    private func deleteModel(_ model: ModelMetadata) {
        Logger.info("User deleting model: \(model.name)", category: Logger.ui)

        do {
            try modelManager.deleteModel(model)
        } catch {
            Logger.error("Failed to delete model", error: error, category: Logger.ui)
        }
    }
}

// MARK: - MLX Model Loader Helper

@MainActor
class MLXModelLoader: ObservableObject {
    @Published var isLoading = false
    @Published var isLoaded = false
    @Published var status: String = ""
    @Published var error: String?

    func reset() {
        isLoading = false
        isLoaded = false
        status = ""
        error = nil
    }

    func downloadAndLoad() async {
        isLoading = true
        error = nil
        status = "Downloading model..."

        do {
            let config = ModelConfiguration(id: ModelSettings.selectedMLXModel)
            let _ = try await LLMModelFactory.shared.loadContainer(configuration: config) { progress in
                Task { @MainActor in
                    self.status = "Downloading: \(Int(progress.fractionCompleted * 100))%"
                }
            }

            isLoaded = true
            isLoading = false
            status = "Model ready"

        } catch {
            self.error = error.localizedDescription
            isLoading = false
            status = "Failed"
        }
    }
}
