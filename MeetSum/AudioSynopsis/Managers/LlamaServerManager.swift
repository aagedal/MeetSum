//
//  LlamaServerManager.swift
//  Audio Synopsis
//
//  Manages the llama-server subprocess lifecycle and HTTP API
//

import Foundation
import Combine
import AppKit

/// Manages a bundled llama-server process for GGUF model inference
@MainActor
class LlamaServerManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isRunning = false
    @Published var isLoading = false
    @Published var loadedModelPath: URL?
    @Published var error: Error?
    @Published var isDownloadingBinary = false
    @Published var binaryDownloadProgress: DownloadProgress?

    // MARK: - Constants

    /// Pinned llama.cpp release version
    private static let llamaCppVersion = "b8391"
    private static let downloadURL = URL(string: "https://github.com/ggml-org/llama.cpp/releases/download/\(llamaCppVersion)/llama-\(llamaCppVersion)-bin-macos-arm64.tar.gz")!
    /// Approximate download size for progress estimation
    private static let downloadSizeBytes: Int64 = 38_000_000

    // MARK: - Private Properties

    private var serverProcess: Process?
    private var serverPort: Int = 8081
    private let portRange = 8081...8089
    private var downloadTask: URLSessionDownloadTask?

    // MARK: - Initialization

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Can't await in notification handler, so use sync stop
            Task { @MainActor [weak self] in
                self?.stopServer()
            }
        }
    }

    // MARK: - Binary Management

    /// Directory where the downloaded llama-server binary and dylibs are stored
    private var llamaServerDirectory: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport.appendingPathComponent("LlamaServer")
    }

    /// Check if llama-server binary is available (bundled or downloaded)
    var isBinaryAvailable: Bool {
        findLlamaServerBinary() != nil
    }

    /// Ensure the llama-server binary is available, downloading if necessary
    func ensureBinaryAvailable() async throws {
        if findLlamaServerBinary() != nil {
            return
        }
        try await downloadLlamaServer()
    }

    /// Maximum number of retry attempts when a download stalls during connection
    private static let maxDownloadRetries = 3
    /// Seconds to wait for first data bytes before retrying the download
    private static let connectionTimeoutSeconds: TimeInterval = 15

    /// Download llama-server from GitHub releases
    private func downloadLlamaServer() async throws {
        guard let installDir = llamaServerDirectory else {
            throw LlamaServerError.downloadFailed("Cannot determine Application Support directory")
        }

        isDownloadingBinary = true
        error = nil
        binaryDownloadProgress = DownloadProgress(
            fractionCompleted: 0,
            totalBytesWritten: 0,
            totalBytesExpected: Self.downloadSizeBytes,
            bytesPerSecond: 0
        )

        Logger.info("Downloading llama-server \(Self.llamaCppVersion) from GitHub", category: Logger.processing)

        // Retry loop for connection-phase stalls
        var lastError: Error?
        for attempt in 1...Self.maxDownloadRetries {
            if attempt > 1 {
                Logger.info("llama-server download retry attempt \(attempt)/\(Self.maxDownloadRetries)", category: Logger.processing)
                binaryDownloadProgress = DownloadProgress(fractionCompleted: 0, totalBytesWritten: 0, totalBytesExpected: Self.downloadSizeBytes, bytesPerSecond: 0)
            }

            do {
                let tarballURL = try await attemptBinaryDownload()

                // Extract the tarball
                try await extractLlamaServer(tarball: tarballURL, to: installDir)

                // Clean up tarball
                try? FileManager.default.removeItem(at: tarballURL)

                isDownloadingBinary = false
                binaryDownloadProgress = nil
                downloadTask = nil

                Logger.info("llama-server downloaded and installed to \(installDir.path)", category: Logger.processing)
                return // Success
            } catch {
                lastError = error
                // Don't retry if user cancelled
                if (error as NSError).code == NSURLErrorCancelled {
                    isDownloadingBinary = false
                    binaryDownloadProgress = nil
                    downloadTask = nil
                    throw error
                }
                // Only retry connection timeouts
                if let serverError = error as? LlamaServerError,
                   case .downloadFailed(let reason) = serverError,
                   reason.contains("Connection timed out") {
                    Logger.warning("llama-server download stalled in connecting phase (attempt \(attempt)/\(Self.maxDownloadRetries))", category: Logger.processing)
                    continue
                }
                // For other errors, don't retry
                isDownloadingBinary = false
                binaryDownloadProgress = nil
                downloadTask = nil
                if (error as NSError).code != NSURLErrorCancelled {
                    self.error = error
                    Logger.error("Failed to download llama-server", error: error, category: Logger.processing)
                }
                throw error
            }
        }

        // All retries exhausted
        isDownloadingBinary = false
        binaryDownloadProgress = nil
        downloadTask = nil
        self.error = lastError
        Logger.error("Failed to download llama-server after \(Self.maxDownloadRetries) attempts", category: Logger.processing)
        throw LlamaServerError.downloadFailed("Download failed after \(Self.maxDownloadRetries) connection attempts. Please check your network and try again.")
    }

    /// Single download attempt with connection timeout
    private func attemptBinaryDownload() async throws -> URL {
        let delegate = DownloadDelegate(expectedBytes: Self.downloadSizeBytes) { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.binaryDownloadProgress = progress
            }
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = false  // Fail fast so we can retry instead of silently waiting
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        do {
            let tarballURL: URL = try await withCheckedThrowingContinuation { continuation in
                let task = session.downloadTask(with: Self.downloadURL) { tempURL, response, error in
                    defer { session.finishTasksAndInvalidate() }

                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200,
                          let tempURL else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                        continuation.resume(throwing: LlamaServerError.downloadFailed("HTTP \(statusCode)"))
                        return
                    }

                    // Move to a stable temp location before the closure exits
                    let stableTempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("llama-server-\(UUID().uuidString).tar.gz")
                    do {
                        try FileManager.default.moveItem(at: tempURL, to: stableTempURL)
                        continuation.resume(returning: stableTempURL)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                self.downloadTask = task
                task.resume()

                // Connection timeout: cancel the task if no data arrives within the timeout
                let connectionTimeout = Self.connectionTimeoutSeconds
                DispatchQueue.global().asyncAfter(deadline: .now() + connectionTimeout) { [weak delegate, weak task] in
                    guard let delegate = delegate, let task = task else { return }
                    if !delegate.hasReceivedData && task.state == .running {
                        Logger.warning("llama-server connection timed out after \(Int(connectionTimeout))s — no data received", category: Logger.processing)
                        task.cancel()
                    }
                }
            }
            return tarballURL
        } catch {
            // Remap cancellation from connection timeout into a retryable error
            if (error as NSError).code == NSURLErrorCancelled && !delegate.hasReceivedData {
                throw LlamaServerError.downloadFailed("Connection timed out waiting for data")
            }
            throw error
        }
    }

    /// Extract llama-server binary and required dylibs from the release tarball
    private func extractLlamaServer(tarball: URL, to directory: URL) async throws {
        // Create the install directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let prefix = "llama-\(Self.llamaCppVersion)"

        // Files we need: the server binary and all dylibs it links against
        let neededFiles = [
            "\(prefix)/llama-server",
            "\(prefix)/libmtmd.0.dylib",
            "\(prefix)/libllama.0.dylib",
            "\(prefix)/libggml.0.dylib",
            "\(prefix)/libggml-cpu.0.dylib",
            "\(prefix)/libggml-blas.0.dylib",
            "\(prefix)/libggml-metal.0.dylib",
            "\(prefix)/libggml-rpc.0.dylib",
            "\(prefix)/libggml-base.0.dylib"
        ]

        // Use tar to extract only what we need into a temp directory, then move
        let tempExtractDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("llama-extract-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempExtractDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = [
            "-xzf", tarball.path,
            "-C", tempExtractDir.path,
            "--include=\(prefix)/llama-server",
            "--include=\(prefix)/lib*.dylib"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw LlamaServerError.downloadFailed("Failed to extract llama-server archive (exit code \(process.terminationStatus))")
        }

        let extractedDir = tempExtractDir.appendingPathComponent(prefix)

        // Move extracted files to install directory
        if let contents = try? FileManager.default.contentsOfDirectory(at: extractedDir, includingPropertiesForKeys: nil) {
            for file in contents {
                let dest = directory.appendingPathComponent(file.lastPathComponent)
                // Remove existing file if present (e.g. from a previous version)
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: file, to: dest)
            }
        }

        // Resolve symlinks: tar extracts symlinks, but we need the actual .0.dylib files
        // The release has: libfoo.0.dylib -> libfoo.0.x.y.dylib
        // After extraction both the symlink and target should be present

        // Make the server binary executable
        let serverPath = directory.appendingPathComponent("llama-server").path
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: serverPath)

        // Clean up temp extraction directory
        try? FileManager.default.removeItem(at: tempExtractDir)

        // Verify the binary exists
        guard FileManager.default.isExecutableFile(atPath: serverPath) else {
            throw LlamaServerError.downloadFailed("llama-server binary not found after extraction")
        }
    }

    /// Cancel an in-progress binary download
    func cancelBinaryDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloadingBinary = false
        binaryDownloadProgress = nil
    }

    // MARK: - Server Lifecycle

    /// Start the llama-server with the given GGUF model
    func startServer(modelPath: URL) async throws {
        // If already running with same model, no-op
        if isRunning && loadedModelPath == modelPath {
            Logger.info("llama-server already running with requested model", category: Logger.processing)
            return
        }

        // Stop existing server if running
        if isRunning {
            stopServer()
        }

        isLoading = true
        error = nil

        // Auto-download binary if not available
        if findLlamaServerBinary() == nil {
            try await downloadLlamaServer()
        }

        guard let binaryPath = findLlamaServerBinary() else {
            let err = LlamaServerError.binaryNotFound
            self.error = err
            isLoading = false
            throw err
        }

        // Find available port
        guard let port = await findAvailablePort() else {
            let err = LlamaServerError.portConflict
            self.error = err
            isLoading = false
            throw err
        }
        serverPort = port

        let contextSize = ModelSettings.ggufContextSize

        Logger.info("Starting llama-server on port \(port) with model: \(modelPath.lastPathComponent), ctx: \(contextSize)", category: Logger.processing)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = [
            "--model", modelPath.path,
            "--port", String(port),
            "--host", "127.0.0.1",
            "--ctx-size", String(contextSize),
            "--n-gpu-layers", "99"
        ]

        // Set environment so dylibs next to the binary are found
        let binaryDir = (binaryPath as NSString).deletingLastPathComponent
        process.environment = ProcessInfo.processInfo.environment
        process.currentDirectoryURL = URL(fileURLWithPath: binaryDir)

        let stderrPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = stdoutPipe

        do {
            try process.run()
            serverProcess = process
            loadedModelPath = modelPath

            // Poll /health until ready (max ~30 seconds)
            let ready = await pollHealthEndpoint(port: port, maxAttempts: 60, interval: 0.5)
            if ready {
                isRunning = true
                isLoading = false
                Logger.info("llama-server is ready on port \(port)", category: Logger.processing)
            } else {
                stopServer()
                let err = LlamaServerError.startupTimeout
                self.error = err
                isLoading = false
                throw err
            }
        } catch let err as LlamaServerError {
            isLoading = false
            throw err
        } catch {
            Logger.error("Failed to start llama-server", error: error, category: Logger.processing)
            self.error = error
            isLoading = false
            throw error
        }
    }

    /// Stop the running llama-server
    func stopServer() {
        guard let process = serverProcess, process.isRunning else {
            isRunning = false
            loadedModelPath = nil
            serverProcess = nil
            return
        }

        Logger.info("Stopping llama-server", category: Logger.processing)
        process.terminate()

        // Give it a moment to terminate gracefully
        DispatchQueue.global().async {
            process.waitUntilExit()
        }

        serverProcess = nil
        isRunning = false
        loadedModelPath = nil
    }

    /// Restart with a new model
    func restartWithModel(modelPath: URL) async throws {
        stopServer()
        try await startServer(modelPath: modelPath)
    }

    // MARK: - Chat Completion API

    /// Send a chat completion request and stream the response
    func sendChatCompletion(
        messages: [[String: String]],
        temperature: Double = 0.7,
        maxTokens: Int = 2000
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: "http://127.0.0.1:\(serverPort)/v1/chat/completions")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let body: [String: Any] = [
                        "messages": messages,
                        "temperature": temperature,
                        "max_tokens": maxTokens,
                        "stream": true
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: LlamaServerError.requestFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"))
                        return
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let data = String(line.dropFirst(6))
                        if data == "[DONE]" { break }

                        guard let jsonData = data.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String else {
                            continue
                        }

                        continuation.yield(content)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func findLlamaServerBinary() -> String? {
        // Check bundle resources first
        if let bundlePath = Bundle.main.path(forResource: "llama-server", ofType: nil) {
            return bundlePath
        }
        // Check bin directory in bundle
        if let bundlePath = Bundle.main.resourcePath {
            let binPath = (bundlePath as NSString).appendingPathComponent("bin/llama-server")
            if FileManager.default.fileExists(atPath: binPath) {
                return binPath
            }
        }
        // Check downloaded location in Application Support
        if let dir = llamaServerDirectory {
            let downloadedPath = dir.appendingPathComponent("llama-server").path
            if FileManager.default.isExecutableFile(atPath: downloadedPath) {
                return downloadedPath
            }
        }
        // Fall back to system-installed llama-server (e.g. Homebrew, for development)
        let systemPaths = [
            "/opt/homebrew/bin/llama-server",
            "/usr/local/bin/llama-server"
        ]
        for path in systemPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                Logger.info("Using system llama-server at \(path)", category: Logger.processing)
                return path
            }
        }
        Logger.info("llama-server binary not found, download required", category: Logger.processing)
        return nil
    }

    private func findAvailablePort() async -> Int? {
        for port in portRange {
            let available = await checkPortAvailable(port)
            if available {
                return port
            }
        }
        return nil
    }

    private func checkPortAvailable(_ port: Int) async -> Bool {
        // Try connecting — if it fails, port is available
        let url = URL(string: "http://127.0.0.1:\(port)/health")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            // If we get a response, something is already on this port
            _ = response
            return false
        } catch {
            // Connection refused = port is available
            return true
        }
    }

    private func pollHealthEndpoint(port: Int, maxAttempts: Int, interval: TimeInterval) async -> Bool {
        let url = URL(string: "http://127.0.0.1:\(port)/health")!

        for _ in 0..<maxAttempts {
            do {
                let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    // Check if status is "ok" in the JSON response
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let status = json["status"] as? String, status == "ok" {
                        return true
                    }
                    // Some versions just return 200 without JSON
                    return true
                }
            } catch {
                // Server not ready yet
            }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
        return false
    }

    nonisolated deinit {}
}

// MARK: - Errors

enum LlamaServerError: LocalizedError {
    case binaryNotFound
    case portConflict
    case startupTimeout
    case requestFailed(String)
    case serverNotRunning
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "llama-server binary not found. Please check your internet connection and try again."
        case .portConflict:
            return "Could not find an available port for llama-server (tried 8081-8089)."
        case .startupTimeout:
            return "llama-server failed to start within 30 seconds. The model may be too large for available memory."
        case .requestFailed(let reason):
            return "Chat request failed: \(reason)"
        case .serverNotRunning:
            return "llama-server is not running. Please ensure a GGUF model is selected and downloaded."
        case .downloadFailed(let reason):
            return "Failed to download llama-server: \(reason)"
        }
    }
}
