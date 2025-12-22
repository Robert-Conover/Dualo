//
//  GGUFService.swift
//  Dualo
//
//  Local LLM inference service using GGUF models via LLM.swift (llama.cpp).
//

import Foundation
import SwiftUI
import LLM

// MARK: - GGUF Service Error

enum GGUFServiceError: LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(String)
    case generationFailed(String)
    case cancelled
    case invalidModelPath
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Model not loaded. Please select and load a model first."
        case .modelLoadFailed(let message):
            return "Failed to load the model: \(message)"
        case .generationFailed(let message):
            return "Generation failed: \(message)"
        case .cancelled:
            return "Generation was cancelled"
        case .invalidModelPath:
            return "Invalid model file path"
        }
    }
}

// MARK: - Generation Statistics

struct GenerationStats {
    let tokenCount: Int
    let durationSeconds: Double
    let tokensPerSecond: Double
    
    var formattedDuration: String {
        if durationSeconds < 1 {
            return String(format: "%.0fms", durationSeconds * 1000)
        } else if durationSeconds < 60 {
            return String(format: "%.1fs", durationSeconds)
        } else {
            let minutes = Int(durationSeconds / 60)
            let seconds = Int(durationSeconds.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        }
    }
    
    var formattedSpeed: String {
        String(format: "%.1f tok/s", tokensPerSecond)
    }
}

// MARK: - GGUF Service

@MainActor
class GGUFService: ObservableObject {
    static let shared = GGUFService()
    
    // MARK: - Published Properties
    
    @Published var isModelLoaded: Bool = false
    @Published var isLoading: Bool = false
    @Published var isGenerating: Bool = false
    @Published var loadedModelId: String?
    @Published var errorMessage: String?
    
    // MARK: - Performance Statistics
    @Published var lastGenerationStats: GenerationStats?
    @Published var currentTokenCount: Int = 0
    @Published var generationStartTime: Date?
    
    // MARK: - Private Properties
    
    private var llm: LLM?
    private var currentGenerationTask: Task<Void, Never>?
    private let localModelManager = LocalModelManager.shared
    
    /// Store model info for context recreation
    private var loadedModelPath: URL?
    private var loadedModelTemplate: Template?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Auto-load
    
    /// Auto-load the previously selected local model on app startup
    /// Only loads if the last selected provider was .local
    func autoLoadLastModel() async {
        do {
            // Check if the last selected provider was .local
            guard let configs = try KeychainService.shared.loadProviderConfigurations(),
                  configs.selectedProvider == .local else {
                print("📱 Auto-load skipped: Last provider was not local")
                return
            }
            
            // Get the selected model ID
            guard let modelId = localModelManager.selectedModelId else {
                print("📱 Auto-load skipped: No local model selected")
                return
            }
            
            // Verify the model is downloaded
            guard let model = localModelManager.availableModels.first(where: { $0.id == modelId }),
                  model.downloadState.isDownloaded else {
                print("📱 Auto-load skipped: Model not downloaded")
                return
            }
            
            print("📱 Auto-loading local model: \(modelId)")
            try await loadModel(modelId: modelId)
            
        } catch {
            print("❌ Auto-load failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Model Loading
    
    /// Load a GGUF model from a local file path
    func loadModel(modelId: String) async throws {
        // Get the local path for this model
        guard let modelPath = localModelManager.getModelLocalPath(modelId) else {
            throw GGUFServiceError.invalidModelPath
        }
        
        // Verify the file exists and is readable
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: modelPath.path) else {
            throw GGUFServiceError.modelLoadFailed("Model file not found at path: \(modelPath.path)")
        }
        
        // Check file size to ensure it's not corrupted/empty
        do {
            let attributes = try fileManager.attributesOfItem(atPath: modelPath.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            if fileSize < 1_000_000 { // Less than 1MB is definitely invalid for a GGUF model
                throw GGUFServiceError.modelLoadFailed("Model file appears to be corrupted (size: \(fileSize) bytes). Please re-download the model.")
            }
            print("📂 Model file size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))")
        } catch let error as GGUFServiceError {
            throw error
        } catch {
            print("⚠️ Could not verify file attributes: \(error)")
        }
        
        // Validate GGUF file header
        do {
            try validateGGUFHeader(at: modelPath)
        } catch {
            throw error
        }
        
        // Get model info for template selection
        let modelInfo = localModelManager.availableModels.first { $0.id == modelId }
        
        // Unload any existing model first
        unloadModel()
        
        isLoading = true
        errorMessage = nil
        
        print("🔄 Loading GGUF model from: \(modelPath.path)")
        
        // Determine the template based on model info
        let template = getTemplate(for: modelInfo)
        
        // Load the model using LLM.swift
        // This runs on the main thread but we need to handle Metal shader compilation errors
        // The "Compiler failed to build request" error occurs when Metal shaders fail to compile
        guard let loadedLLM = LLM(from: modelPath, template: template) else {
            isLoading = false
            // Provide more helpful error message
            let errorDetails = """
            Failed to initialize LLM from file. This can happen due to:
            1. Incompatible GGUF format - try re-downloading the model
            2. Metal shader compilation failure - try restarting the app
            3. Insufficient memory - close other apps and try again
            4. Corrupted model file - delete and re-download
            """
            print("❌ \(errorDetails)")
            let userFacingError = "Failed to load model. The model file may be incompatible or corrupted. Try deleting and re-downloading it."
            errorMessage = userFacingError
            throw GGUFServiceError.modelLoadFailed(userFacingError)
        }
        
        llm = loadedLLM
        
        // Store model info for context recreation (needed for KV cache clearing)
        loadedModelPath = modelPath
        loadedModelTemplate = template
        
        print("✅ GGUF model loaded successfully!")
        
        isModelLoaded = true
        loadedModelId = modelId
        isLoading = false
    }
    
    /// Unload the current model to free memory
    func unloadModel() {
        llm = nil
        isModelLoaded = false
        loadedModelId = nil
        loadedModelPath = nil
        loadedModelTemplate = nil
        print("🗑️ GGUF model unloaded")
    }
    
    // MARK: - Text Generation
    
    /// Generate a streaming response for the given message
    /// - Parameters:
    ///   - message: The user's message to respond to
    ///   - history: The conversation history (excluding the current message)
    ///   - conversationId: The ID of the current conversation (unused, kept for API compatibility)
    func streamMessage(_ message: String, history: [Message], conversationId: UUID) -> AsyncThrowingStream<String, Error> {
        // Capture values needed for the detached task BEFORE creating the stream
        // This avoids capturing `self` directly in the detached task
        let isLoaded = self.isModelLoaded
        let modelPath = self.loadedModelPath
        let template = self.loadedModelTemplate
        let historyForLLM = self.convertToLLMHistory(history)
        
        return AsyncThrowingStream { continuation in
            // Use Task.detached to run heavy LLM work OFF the main thread
            // Regular Task {} inherits @MainActor isolation from GGUFService,
            // which would block the UI during model loading and inference.
            let task = Task.detached { [weak self] in
                guard let self = self else {
                    continuation.finish()
                    return
                }
                
                guard isLoaded,
                      let modelPath = modelPath,
                      let template = template else {
                    continuation.finish(throwing: GGUFServiceError.modelNotLoaded)
                    return
                }
                
                // Update UI state on MainActor
                await MainActor.run {
                    self.isGenerating = true
                    self.currentTokenCount = 0
                    self.generationStartTime = Date()
                    self.lastGenerationStats = nil
                }
                
                // Clear KV cache efficiently using resetContext() (LLM.swift v2.0.1+)
                // This avoids expensive model reloading from disk while preventing
                // position mismatches in llama.cpp's KV cache between generations.
                let activeLLM: LLM
                
                if let existingLLM = await MainActor.run(body: { self.llm }) {
                    // Use existing LLM instance - just reset the context (clear KV cache)
                    // LLM.reset() calls core.resetContext() which clears the KV cache efficiently
                    print("🔄 GGUFService: Resetting context (clearing KV cache)")
                    existingLLM.reset()  // Clears history and resets core context
                    existingLLM.history = historyForLLM
                    activeLLM = existingLLM
                } else {
                    // Fallback: Load model if not already loaded (first use or after unload)
                    print("🔄 GGUFService: Loading model (first use)")
                    guard let freshLLM = LLM(from: modelPath, template: template) else {
                        continuation.finish(throwing: GGUFServiceError.modelLoadFailed("Failed to load LLM"))
                        await MainActor.run {
                            self.isGenerating = false
                        }
                        return
                    }
                    
                    // Set the conversation history
                    freshLLM.history = historyForLLM
                    
                    // Update the stored LLM reference on MainActor
                    await MainActor.run {
                        self.llm = freshLLM
                    }
                    
                    activeLLM = freshLLM
                }
                
                // Set up the update callback to stream tokens
                activeLLM.update = { [weak self] token in
                    if let token = token {
                        // Sanitize the token to fix common encoding issues (e.g., mojibake from curly quotes)
                        let sanitizedToken = self?.sanitizeText(token) ?? token
                        continuation.yield(sanitizedToken)
                        
                        // Update token count on main actor
                        Task { @MainActor in
                            self?.currentTokenCount += 1
                        }
                    }
                }
                
                // Heavy inference now runs on background thread (not MainActor)
                await activeLLM.respond(to: message)
                
                await MainActor.run {
                    // Calculate final statistics
                    if let startTime = self.generationStartTime {
                        let duration = Date().timeIntervalSince(startTime)
                        let tokensPerSecond = duration > 0 ? Double(self.currentTokenCount) / duration : 0
                        self.lastGenerationStats = GenerationStats(
                            tokenCount: self.currentTokenCount,
                            durationSeconds: duration,
                            tokensPerSecond: tokensPerSecond
                        )
                    }
                    self.isGenerating = false
                }
                
                continuation.finish()
            }
            
            // Store the task reference on MainActor for cancellation support
            Task { @MainActor [weak self] in
                self?.currentGenerationTask = task
            }
            
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor [weak self] in
                    self?.stopGeneration()
                }
            }
        }
    }
    
    /// Convert app's Message array to LLM.swift's Chat history format
    private func convertToLLMHistory(_ messages: [Message]) -> [Chat] {
        // Filter out the current message (it will be added by respond(to:))
        // and convert Message to Chat format
        return messages.compactMap { message -> Chat? in
            let role: Role = message.role == Message.Role.user ? .user : .bot
            return (role: role, content: message.content)
        }
    }
    
    /// Stop the current generation
    func stopGeneration() {
        currentGenerationTask?.cancel()
        currentGenerationTask = nil
        llm?.stop()
        isGenerating = false
    }
    
    /// Send a non-streaming message (convenience method)
    func sendMessage(_ message: String, history: [Message], conversationId: UUID) async throws -> String {
        var fullResponse = ""
        
        for try await chunk in streamMessage(message, history: history, conversationId: conversationId) {
            fullResponse += chunk
        }
        
        return fullResponse.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Private Helpers
    
    /// Sanitize text to fix common encoding issues
    /// Handles mojibake from UTF-8 being misinterpreted as Latin-1/Windows-1252
    nonisolated private func sanitizeText(_ text: String) -> String {
        var result = text
        
        // Common mojibake patterns for curly/smart quotes when UTF-8 is read as Latin-1
        // These occur when multi-byte UTF-8 sequences are interpreted as single-byte Latin-1
        
        // Fix common mojibake patterns using Unicode escape sequences
        let mojibakeReplacements: [(String, String)] = [
            // Double quotes mojibake patterns (UTF-8 E2 80 9C/9D read as Latin-1)
            ("\u{00E2}\u{20AC}\u{0153}", "\""),   // LEFT DOUBLE QUOTATION MARK mojibake
            ("\u{00E2}\u{20AC}\u{009D}", "\""),   // RIGHT DOUBLE QUOTATION MARK mojibake
            ("\u{00E2}\u{20AC}", "\""),           // Partial quote mojibake
            
            // Single quotes mojibake patterns (UTF-8 E2 80 98/99 read as Latin-1)
            ("\u{00E2}\u{20AC}\u{2122}", "'"),    // RIGHT SINGLE QUOTATION MARK mojibake
            ("\u{00E2}\u{20AC}\u{02DC}", "'"),    // LEFT SINGLE QUOTATION MARK mojibake
            
            // Em dash mojibake (UTF-8 E2 80 94 read as Latin-1)
            ("\u{00E2}\u{20AC}\u{201D}", "\u{2014}"),  // EM DASH mojibake -> em dash
            
            // En dash mojibake (UTF-8 E2 80 93 read as Latin-1)
            ("\u{00E2}\u{20AC}\u{201C}", "\u{2013}"),  // EN DASH mojibake -> en dash
            
            // Ellipsis mojibake (UTF-8 E2 80 A6 read as Latin-1)
            ("\u{00E2}\u{20AC}\u{00A6}", "\u{2026}"),  // HORIZONTAL ELLIPSIS mojibake
        ]
        
        for (pattern, replacement) in mojibakeReplacements {
            result = result.replacingOccurrences(of: pattern, with: replacement)
        }
        
        // Also normalize any actual curly quotes to straight quotes for consistency
        // This prevents future mojibake issues
        // Using Unicode escape sequences for the curly quotes
        result = result.replacingOccurrences(of: "\u{201C}", with: "\"")  // LEFT DOUBLE QUOTATION MARK
        result = result.replacingOccurrences(of: "\u{201D}", with: "\"")  // RIGHT DOUBLE QUOTATION MARK
        result = result.replacingOccurrences(of: "\u{2018}", with: "'")   // LEFT SINGLE QUOTATION MARK
        result = result.replacingOccurrences(of: "\u{2019}", with: "'")   // RIGHT SINGLE QUOTATION MARK
        
        return result
    }
    
    /// Get the appropriate template for the model
    private func getTemplate(for model: LocalModel?) -> Template {
        let systemPrompt = "You are a helpful assistant."
        
        guard let model = model else {
            return .chatML(systemPrompt)
        }
        
        // Select template based on model family
        switch model.templateType {
        case .chatML:
            return .chatML(systemPrompt)
        case .gemma:
            // Custom Gemma 3 template with proper stop sequence
            // Gemma 3 uses: <start_of_turn>user\n...<end_of_turn>\n<start_of_turn>model\n...<end_of_turn>
            return Template(
                system: ("", ""),  // Gemma 3 doesn't use a separate system turn
                user: ("<start_of_turn>user\n", "<end_of_turn>\n"),
                bot: ("<start_of_turn>model\n", "<end_of_turn>"),
                stopSequence: "<end_of_turn>",
                systemPrompt: systemPrompt
            )
        case .llama:
            return .alpaca(systemPrompt)
        case .mistral:
            return .chatML(systemPrompt)
        case .qwen:
            return .chatML(systemPrompt)
        }
    }
    
    // MARK: - GGUF File Validation
    
    /// Validates a GGUF file header to ensure it's a valid GGUF file
    /// GGUF format: https://github.com/ggerganov/ggml/blob/master/docs/gguf.md
    private func validateGGUFHeader(at url: URL) throws {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            throw GGUFServiceError.modelLoadFailed("Cannot open model file for reading")
        }
        defer { try? fileHandle.close() }
        
        // Read the magic number (first 4 bytes should be "GGUF")
        guard let magicData = try? fileHandle.read(upToCount: 4),
              magicData.count == 4 else {
            throw GGUFServiceError.modelLoadFailed("Cannot read GGUF magic number")
        }
        
        // GGUF magic number is 0x46554747 ("GGUF" in little-endian ASCII)
        let magic = magicData.withUnsafeBytes { $0.load(as: UInt32.self) }
        let expectedMagic: UInt32 = 0x46554747 // "GGUF" in little-endian
        
        guard magic == expectedMagic else {
            let magicString = String(data: magicData, encoding: .ascii) ?? "unknown"
            throw GGUFServiceError.modelLoadFailed("Invalid GGUF file format. Expected 'GGUF' header but got '\(magicString)'. The file may be corrupted or not a GGUF model.")
        }
        
        // Read the version number (next 4 bytes)
        guard let versionData = try? fileHandle.read(upToCount: 4),
              versionData.count == 4 else {
            throw GGUFServiceError.modelLoadFailed("Cannot read GGUF version")
        }
        
        let version = versionData.withUnsafeBytes { $0.load(as: UInt32.self) }
        print("📋 GGUF file version: \(version)")
        
        // LLM.swift v2.1.0 supports GGUF v3 format
        // Older versions (v1, v2) or future versions may not be compatible
        if version < 2 || version > 3 {
            print("⚠️ Warning: GGUF version \(version) may not be fully supported. LLM.swift works best with GGUF v3.")
        }
    }
}

