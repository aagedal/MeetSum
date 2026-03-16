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

    // MARK: - Private Properties

    private var serverProcess: Process?
    private var serverPort: Int = 8081
    private let portRange = 8081...8089

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
        // Check local development path
        let devPath = Bundle.main.bundlePath + "/Contents/Resources/bin/llama-server"
        if FileManager.default.fileExists(atPath: devPath) {
            return devPath
        }
        Logger.error("llama-server binary not found in bundle", category: Logger.processing)
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

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "llama-server binary not found in app bundle. GGUF chat requires the llama-server binary."
        case .portConflict:
            return "Could not find an available port for llama-server (tried 8081-8089)."
        case .startupTimeout:
            return "llama-server failed to start within 30 seconds. The model may be too large for available memory."
        case .requestFailed(let reason):
            return "Chat request failed: \(reason)"
        case .serverNotRunning:
            return "llama-server is not running. Please ensure a GGUF model is selected and downloaded."
        }
    }
}
