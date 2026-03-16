//
//  ModelManager.swift
//  Audio Synopsis
//
//  Central model management for downloads and access
//

import Foundation
import Combine

/// Download progress information for UI display
struct DownloadProgress {
    let fractionCompleted: Double
    let totalBytesWritten: Int64
    let totalBytesExpected: Int64
    let bytesPerSecond: Double

    var isConnecting: Bool {
        totalBytesWritten == 0
    }

    var downloadedFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file)
    }

    var totalFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalBytesExpected, countStyle: .file)
    }

    var speedFormatted: String {
        if bytesPerSecond >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
        } else {
            return String(format: "%.0f KB/s", bytesPerSecond / 1_000)
        }
    }

    var percentComplete: Int {
        Int(fractionCompleted * 100)
    }
}

/// Errors related to model management
enum ModelManagerError: LocalizedError {
    case downloadFailed(String)
    case directoryAccessFailed
    case modelNotFound(String)
    case insufficientSpace
    
    var errorDescription: String? {
        switch self {
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .directoryAccessFailed:
            return "Cannot access model directory"
        case .modelNotFound(let modelId):
            return "Whisper model '\(modelId)' is not downloaded. A Whisper model is required for transcription, even when using Apple Intelligence for summarization. Please download a model in Settings."
        case .insufficientSpace:
            return "Insufficient disk space"
        }
    }
}

/// Central model management
@MainActor
class ModelManager: ObservableObject {
    
    // MARK: - Published Properties

    @Published var whisperModelDirectory: URL?
    @Published var mlxModelDirectory: URL?
    @Published var installedModels: Set<String> = []
    @Published var downloadProgress: [String: DownloadProgress] = [:]
    @Published var customModels: [ModelMetadata] = []
    @Published var error: Error?

    // MARK: - Properties

    let availableModels = ModelMetadata.allModels
    private let whisperBookmarkManager = SecurityBookmarkManager(bookmarkKey: "modelDirectoryBookmark")
    private let mlxBookmarkManager = SecurityBookmarkManager(bookmarkKey: "mlxModelDirectoryBookmark")
    private let fileManager = FileManager.default

    // MARK: - Initialization

    init() {
        Logger.info("ModelManager initialized", category: Logger.general)
        resolveWhisperModelDirectory()
        resolveMLXModelDirectory()
        scanInstalledModels()
    }

    // MARK: - Directory Management

    /// Resolve the Whisper model directory (user-selected or fallback)
    private func resolveWhisperModelDirectory() {
        Logger.info("Resolving Whisper model directory", category: Logger.general)

        // Try to restore bookmarked directory
        if let bookmarkedURL = whisperBookmarkManager.restoreBookmark() {
            if whisperBookmarkManager.startAccessingSecurityScopedResource(url: bookmarkedURL) {
                whisperModelDirectory = bookmarkedURL
                Logger.info("Using bookmarked Whisper model directory: \(bookmarkedURL.path)", category: Logger.general)
                return
            }
        }

        // Fall back to Application Support
        do {
            let appSupport = try AudioUtils.getRecordingsDirectory()
                .deletingLastPathComponent()
                .appendingPathComponent("Models")

            try fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true, attributes: nil)
            whisperModelDirectory = appSupport
            Logger.info("Using Application Support for Whisper models: \(appSupport.path)", category: Logger.general)

        } catch {
            Logger.error("Failed to create Whisper model directory", error: error, category: Logger.general)
            self.error = error
        }
    }

    /// Resolve the MLX model directory (user-selected or default cache)
    private func resolveMLXModelDirectory() {
        Logger.info("Resolving MLX model directory", category: Logger.general)

        // Try to restore bookmarked directory
        if let bookmarkedURL = mlxBookmarkManager.restoreBookmark() {
            if mlxBookmarkManager.startAccessingSecurityScopedResource(url: bookmarkedURL) {
                mlxModelDirectory = bookmarkedURL
                Logger.info("Using bookmarked MLX model directory: \(bookmarkedURL.path)", category: Logger.general)
                return
            }
        }

        // Fall back to Application Support/MLXModels
        if let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let defaultMLXDir = appSupportDir.appendingPathComponent("MLXModels")
            try? fileManager.createDirectory(at: defaultMLXDir, withIntermediateDirectories: true, attributes: nil)
            mlxModelDirectory = defaultMLXDir
            Logger.info("Using default MLX model directory: \(defaultMLXDir.path)", category: Logger.general)
        }
    }

    /// Set a new user-selected Whisper model directory
    func setWhisperModelDirectory(_ url: URL) {
        Logger.info("Setting Whisper model directory: \(url.path)", category: Logger.general)

        guard whisperBookmarkManager.saveBookmark(for: url) else {
            Logger.error("Failed to save bookmark for Whisper directory", category: Logger.general)
            error = SecurityBookmarkError.bookmarkCreationFailed
            return
        }

        guard whisperBookmarkManager.startAccessingSecurityScopedResource(url: url) else {
            Logger.error("Failed to access Whisper directory", category: Logger.general)
            error = SecurityBookmarkError.accessDenied
            return
        }

        whisperModelDirectory = url
        scanInstalledModels()
    }

    /// Set a new user-selected MLX model directory
    func setMLXModelDirectory(_ url: URL) {
        Logger.info("Setting MLX model directory: \(url.path)", category: Logger.general)

        guard mlxBookmarkManager.saveBookmark(for: url) else {
            Logger.error("Failed to save bookmark for MLX directory", category: Logger.general)
            error = SecurityBookmarkError.bookmarkCreationFailed
            return
        }

        guard mlxBookmarkManager.startAccessingSecurityScopedResource(url: url) else {
            Logger.error("Failed to access MLX directory", category: Logger.general)
            error = SecurityBookmarkError.accessDenied
            return
        }

        mlxModelDirectory = url
    }
    
    // MARK: - Model Discovery
    
    /// Scan the model directory for installed models (known + custom ggml-*.bin files)
    func scanInstalledModels() {
        guard let directory = whisperModelDirectory else {
            Logger.warning("Cannot scan models: no directory set", category: Logger.general)
            return
        }

        Logger.debug("Scanning for installed models in: \(directory.path)", category: Logger.general)

        var found = Set<String>()
        let knownFilenames = Set(availableModels.map { $0.filename })

        // Check known models
        for model in availableModels {
            let modelPath = directory.appendingPathComponent(model.filename)
            if fileManager.fileExists(atPath: modelPath.path) {
                found.insert(model.id)
                Logger.debug("Found installed model: \(model.name)", category: Logger.general)
            }
        }

        // Discover custom ggml-*.bin files not in the known list
        var discovered: [ModelMetadata] = []
        if let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles) {
            for fileURL in contents {
                let filename = fileURL.lastPathComponent
                guard filename.hasSuffix(".bin"), !knownFilenames.contains(filename) else { continue }

                let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
                let sizeBytes = Int64(attrs?.fileSize ?? 0)
                let displayName = filename
                    .replacingOccurrences(of: ".bin", with: "")
                    .replacingOccurrences(of: "ggml-", with: "")
                    .replacingOccurrences(of: "-", with: " ")
                    .replacingOccurrences(of: "_", with: " ")
                    .localizedCapitalized

                let id = "custom-\(filename)"
                let model = ModelMetadata(
                    id: id,
                    name: displayName,
                    type: .whisper,
                    filename: filename,
                    downloadURL: URL(string: "file:///unused")!,
                    sizeBytes: sizeBytes,
                    description: "Custom model (\(filename))"
                )
                discovered.append(model)
                found.insert(id)
                Logger.debug("Discovered custom model: \(filename)", category: Logger.general)
            }
        }

        customModels = discovered
        installedModels = found
        Logger.info("Found \(found.count) installed models (\(discovered.count) custom)", category: Logger.general)
    }
    
    /// Get the file path for a specific model
    /// - Parameter modelId: Model identifier
    /// - Returns: URL to the model file, or nil if not installed
    func getModelPath(for modelId: String) -> URL? {
        // Check custom path models first
        if modelId.hasPrefix("custom-whisper-") {
            return getCustomWhisperModelPath(for: modelId)
        }

        guard let directory = whisperModelDirectory else {
            Logger.warning("Cannot get model path: no directory set", category: Logger.general)
            return nil
        }

        // Check known models first, then custom models
        let allModels = availableModels + customModels
        guard let model = allModels.first(where: { $0.id == modelId }) else {
            Logger.warning("Model not found in available or custom models: \(modelId)", category: Logger.general)
            return nil
        }

        let modelPath = directory.appendingPathComponent(model.filename)

        if fileManager.fileExists(atPath: modelPath.path) {
            Logger.debug("Model path for \(modelId): \(modelPath.path)", category: Logger.general)
            return modelPath
        } else {
            Logger.warning("Model file does not exist: \(modelId)", category: Logger.general)
            return nil
        }
    }

    /// Get the file path for a custom path whisper model by resolving its bookmark
    private func getCustomWhisperModelPath(for modelId: String) -> URL? {
        guard let entry = ModelSettings.customWhisperModels.first(where: { $0.id == modelId }),
              let url = entry.resolveURL() else {
            Logger.warning("Cannot resolve custom whisper model: \(modelId)", category: Logger.general)
            return nil
        }

        guard url.startAccessingSecurityScopedResource() else {
            Logger.warning("Cannot access custom whisper model: \(url.path)", category: Logger.general)
            return nil
        }

        if fileManager.fileExists(atPath: url.path) {
            Logger.debug("Custom whisper model path for \(modelId): \(url.path)", category: Logger.general)
            return url
        }

        url.stopAccessingSecurityScopedResource()
        Logger.warning("Custom whisper model file does not exist: \(url.path)", category: Logger.general)
        return nil
    }
    
    /// Check if a model is installed
    /// - Parameter modelId: Model identifier
    /// - Returns: true if installed
    func isModelInstalled(_ modelId: String) -> Bool {
        installedModels.contains(modelId)
    }
    
    // MARK: - Model Download
    
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    
    /// Download a model
    /// - Parameter metadata: Model metadata
    func downloadModel(_ metadata: ModelMetadata) async throws {
        Logger.info("Starting download for model: \(metadata.name)", category: Logger.general)
        
        guard let directory = whisperModelDirectory else {
            Logger.error("Cannot download: no directory set", category: Logger.general)
            throw ModelManagerError.directoryAccessFailed
        }
        
        let destination = directory.appendingPathComponent(metadata.filename)
        
        // Check if already exists
        if fileManager.fileExists(atPath: destination.path) {
            Logger.info("Model already exists: \(metadata.name)", category: Logger.general)
            _ = await MainActor.run {
                installedModels.insert(metadata.id)
            }
            return
        }
        
        // Mark as downloading
        await MainActor.run {
            downloadProgress[metadata.id] = DownloadProgress(fractionCompleted: 0, totalBytesWritten: 0, totalBytesExpected: metadata.sizeBytes, bytesPerSecond: 0)
        }

        // Create session with delegate
        let delegate = DownloadDelegate(expectedBytes: metadata.sizeBytes) { progress in
            Task { @MainActor [weak self] in
                self?.downloadProgress[metadata.id] = progress
            }
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 3600
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        
        do {
            Logger.info("Downloading from: \(metadata.downloadURL)", category: Logger.general)
            
            return try await withCheckedThrowingContinuation { continuation in
                let task = session.downloadTask(with: metadata.downloadURL) { [weak self] tempURL, response, error in
                    defer { session.finishTasksAndInvalidate() }

                    guard let self = self else {
                        continuation.resume(throwing: ModelManagerError.downloadFailed("ModelManager was deallocated during download"))
                        return
                    }
                    
                    // Remove task from tracking (on main actor)
                    Task { @MainActor in
                        self.downloadTasks.removeValue(forKey: metadata.id)
                    }
                    
                    if let error = error {
                        Task { @MainActor in
                            self.downloadProgress.removeValue(forKey: metadata.id)
                            // Don't set error if cancelled
                            if (error as NSError).code != NSURLErrorCancelled {
                                self.error = error
                            }
                        }
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let tempURL = tempURL else {
                        let error = ModelManagerError.downloadFailed("HTTP error: \(response?.description ?? "unknown")")
                        Task { @MainActor in
                            self.downloadProgress.removeValue(forKey: metadata.id)
                            self.error = error
                        }
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    do {
                        // Move to destination (fileManager is safe to use from background)
                        try FileManager.default.moveItem(at: tempURL, to: destination)
                        
                        Logger.info("Model downloaded successfully: \(metadata.name)", category: Logger.general)
                        
                        Task { @MainActor in
                            self.installedModels.insert(metadata.id)
                            self.downloadProgress.removeValue(forKey: metadata.id)
                        }
                        continuation.resume()
                    } catch {
                        Logger.error("Failed to move downloaded model", error: error, category: Logger.general)
                        Task { @MainActor in
                            self.downloadProgress.removeValue(forKey: metadata.id)
                            self.error = error
                        }
                        continuation.resume(throwing: error)
                    }
                }
                
                // Store task for cancellation
                self.downloadTasks[metadata.id] = task
                task.resume()
            }
            
        } catch {
            Logger.error("Model download failed", error: error, category: Logger.general)
            await MainActor.run {
                downloadProgress.removeValue(forKey: metadata.id)
                // Only set error if not cancelled
                if (error as NSError).code != NSURLErrorCancelled {
                    self.error = error
                }
            }
            throw ModelManagerError.downloadFailed(error.localizedDescription)
        }
    }
    
    /// Cancel a model download
    /// - Parameter modelId: ID of the model to cancel
    func cancelDownload(for modelId: String) {
        Logger.info("Cancelling download for model: \(modelId)", category: Logger.general)
        downloadTasks[modelId]?.cancel()
        downloadTasks.removeValue(forKey: modelId)
        
        Task { @MainActor in
            downloadProgress.removeValue(forKey: modelId)
        }
    }
    
    /// Import a custom model file into the model directory
    /// - Parameter sourceURL: URL of the model file to import
    func importModel(from sourceURL: URL) throws {
        guard let directory = whisperModelDirectory else {
            throw ModelManagerError.directoryAccessFailed
        }

        let filename = sourceURL.lastPathComponent
        let destination = directory.appendingPathComponent(filename)

        if fileManager.fileExists(atPath: destination.path) {
            Logger.info("Model file already exists in directory: \(filename)", category: Logger.general)
        } else {
            let accessing = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
            try fileManager.copyItem(at: sourceURL, to: destination)
            Logger.info("Imported custom model: \(filename)", category: Logger.general)
        }

        scanInstalledModels()
    }

    /// Delete a downloaded model
    /// - Parameter metadata: Model metadata
    func deleteModel(_ metadata: ModelMetadata) throws {
        Logger.info("Deleting model: \(metadata.name)", category: Logger.general)

        guard let directory = whisperModelDirectory else {
            throw ModelManagerError.directoryAccessFailed
        }

        let modelPath = directory.appendingPathComponent(metadata.filename)

        if fileManager.fileExists(atPath: modelPath.path) {
            try fileManager.removeItem(at: modelPath)
            installedModels.remove(metadata.id)
            Logger.info("Model deleted successfully: \(metadata.name)", category: Logger.general)

            // Rescan to update custom models list
            if metadata.id.hasPrefix("custom-") {
                scanInstalledModels()
            }
        }
    }
    
    // MARK: - Disk Space
    
    /// Get available disk space in bytes
    var whisperAvailableDiskSpace: Int64? {
        guard let directory = whisperModelDirectory else { return nil }
        
        do {
            let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage
        } catch {
            Logger.error("Failed to get disk space", error: error, category: Logger.general)
            return nil
        }
    }
    
    nonisolated deinit {
        // Note: Can't call main actor methods in deinit
        // The bookmark resource will be released when the manager is deallocated
    }
}

// MARK: - Download Delegate

class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: (DownloadProgress) -> Void
    let expectedBytes: Int64
    private var lastReportedPercent: Int = -1
    private var lastTimestamp: CFAbsoluteTime = 0
    private var lastBytesWritten: Int64 = 0
    private var currentSpeed: Double = 0

    init(expectedBytes: Int64, onProgress: @escaping (DownloadProgress) -> Void) {
        self.expectedBytes = expectedBytes
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Handled by completion handler
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // Use server-reported size if available, otherwise fall back to metadata
        let totalBytes: Int64
        if totalBytesExpectedToWrite != NSURLSessionTransferSizeUnknown && totalBytesExpectedToWrite > 0 {
            totalBytes = totalBytesExpectedToWrite
        } else {
            totalBytes = expectedBytes
        }

        guard totalBytes > 0 else { return }

        let fraction = min(max(Double(totalBytesWritten) / Double(totalBytes), 0.0), 1.0)

        // Calculate speed over 0.5s intervals to avoid jitter
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastTimestamp
        if elapsed >= 0.5 {
            let bytesDelta = totalBytesWritten - lastBytesWritten
            currentSpeed = Double(bytesDelta) / elapsed
            lastTimestamp = now
            lastBytesWritten = totalBytesWritten
        }

        // Throttle: only report on whole-percent changes
        let currentPercent = Int(fraction * 100)
        guard currentPercent > lastReportedPercent else { return }
        lastReportedPercent = currentPercent

        let progress = DownloadProgress(
            fractionCompleted: fraction,
            totalBytesWritten: totalBytesWritten,
            totalBytesExpected: totalBytes,
            bytesPerSecond: currentSpeed
        )
        onProgress(progress)
    }
}
