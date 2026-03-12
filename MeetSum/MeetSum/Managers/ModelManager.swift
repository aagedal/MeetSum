//
//  ModelManager.swift
//  MeetSum
//
//  Central model management for downloads and access
//

import Foundation
import Combine

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
    
    @Published var modelDirectory: URL?
    @Published var installedModels: Set<String> = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var error: Error?
    
    // MARK: - Properties
    
    let availableModels = ModelMetadata.allModels
    private let bookmarkManager = SecurityBookmarkManager()
    private let fileManager = FileManager.default
    
    // MARK: - Initialization
    
    init() {
        Logger.info("ModelManager initialized", category: Logger.general)
        resolveModelDirectory()
        scanInstalledModels()
    }
    
    // MARK: - Directory Management
    
    /// Resolve the model directory (user-selected or fallback)
    private func resolveModelDirectory() {
        Logger.info("Resolving model directory", category: Logger.general)
        
        // Try to restore bookmarked directory
        if let bookmarkedURL = bookmarkManager.restoreBookmark() {
            if bookmarkManager.startAccessingSecurityScopedResource(url: bookmarkedURL) {
                modelDirectory = bookmarkedURL
                Logger.info("Using bookmarked model directory: \(bookmarkedURL.path)", category: Logger.general)
                return
            }
        }
        
        // Fall back to Application Support
        do {
            let appSupport = try AudioUtils.getRecordingsDirectory()
                .deletingLastPathComponent()
                .appendingPathComponent("Models")
            
            try fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true, attributes: nil)
            modelDirectory = appSupport
            Logger.info("Using Application Support for models: \(appSupport.path)", category: Logger.general)
            
        } catch {
            Logger.error("Failed to create model directory", error: error, category: Logger.general)
            self.error = error
        }
    }
    
    /// Set a new user-selected model directory
    /// - Parameter url: URL to the directory
    func setModelDirectory(_ url: URL) {
        Logger.info("Setting model directory: \(url.path)", category: Logger.general)
        
        // Save bookmark
        guard bookmarkManager.saveBookmark(for: url) else {
            Logger.error("Failed to save bookmark for directory", category: Logger.general)
            error = SecurityBookmarkError.bookmarkCreationFailed
            return
        }
        
        // Start accessing
        guard bookmarkManager.startAccessingSecurityScopedResource(url: url) else {
            Logger.error("Failed to access directory", category: Logger.general)
            error = SecurityBookmarkError.accessDenied
            return
        }
        
        modelDirectory = url
        scanInstalledModels()
    }
    
    // MARK: - Model Discovery
    
    /// Scan the model directory for installed models
    private func scanInstalledModels() {
        guard let directory = modelDirectory else {
            Logger.warning("Cannot scan models: no directory set", category: Logger.general)
            return
        }
        
        Logger.debug("Scanning for installed models in: \(directory.path)", category: Logger.general)
        
        var found = Set<String>()
        
        for model in availableModels {
            let modelPath = directory.appendingPathComponent(model.filename)
            if fileManager.fileExists(atPath: modelPath.path) {
                found.insert(model.id)
                Logger.debug("Found installed model: \(model.name)", category: Logger.general)
            }
        }
        
        installedModels = found
        Logger.info("Found \(found.count) installed models", category: Logger.general)
    }
    
    /// Get the file path for a specific model
    /// - Parameter modelId: Model identifier
    /// - Returns: URL to the model file, or nil if not installed
    func getModelPath(for modelId: String) -> URL? {
        guard let directory = modelDirectory else {
            Logger.warning("Cannot get model path: no directory set", category: Logger.general)
            return nil
        }
        
        guard let model = availableModels.first(where: { $0.id == modelId }) else {
            Logger.warning("Model not found in available models: \(modelId)", category: Logger.general)
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
        
        guard let directory = modelDirectory else {
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
            downloadProgress[metadata.id] = 0.0
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
    
    /// Delete a downloaded model
    /// - Parameter metadata: Model metadata
    func deleteModel(_ metadata: ModelMetadata) throws {
        Logger.info("Deleting model: \(metadata.name)", category: Logger.general)
        
        guard let directory = modelDirectory else {
            throw ModelManagerError.directoryAccessFailed
        }
        
        let modelPath = directory.appendingPathComponent(metadata.filename)
        
        if fileManager.fileExists(atPath: modelPath.path) {
            try fileManager.removeItem(at: modelPath)
            installedModels.remove(metadata.id)
            Logger.info("Model deleted successfully: \(metadata.name)", category: Logger.general)
        }
    }
    
    // MARK: - Disk Space
    
    /// Get available disk space in bytes
    var availableDiskSpace: Int64? {
        guard let directory = modelDirectory else { return nil }
        
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
    let onProgress: (Double) -> Void
    let expectedBytes: Int64
    private var lastReportedPercent: Int = -1

    init(expectedBytes: Int64, onProgress: @escaping (Double) -> Void) {
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

        let progress = min(max(Double(totalBytesWritten) / Double(totalBytes), 0.0), 1.0)

        // Throttle: only report on whole-percent changes
        let currentPercent = Int(progress * 100)
        guard currentPercent > lastReportedPercent else { return }
        lastReportedPercent = currentPercent

        onProgress(progress)
    }
}
