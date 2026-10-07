//
//  GGUFService.swift
//  Dualo
//
//  Local LLM inference service using GGUF models via LLM.swift (llama.cpp).
//

import Foundation
import SwiftUI
import LLM
import OSLog

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
    private var currentGenerationId: UUID?
    /// The most recent generation, stopped or not. Each new one waits for it to wind down,
    /// because LLM.swift silently ignores a `respond` call while another is still running.
    private var lastGenerationTask: Task<Void, Never>?
    private let localModelManager = LocalModelManager.shared

    nonisolated private static let systemPrompt = "You are a helpful assistant."

    /// Cached regex for stripping thinking blocks (compiled once for performance).
    /// Like `MessageContentRenderer`, an unclosed <think> (reply stopped mid-thought) runs to the end.
    nonisolated private static let thinkingBlockRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "<think>[\\s\\S]*?(?:</think>|$)", options: [])
    }()
    
    /// Track which conversation the LLM is currently serving
    /// When this changes, we need to reset context for the new conversation
    private var currentConversationId: UUID?
    
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
                Logger.inference.debug("Auto-load skipped: Last provider was not local")
                return
            }
            
            // Get the selected model ID
            guard let modelId = localModelManager.selectedModelId else {
                Logger.inference.debug("Auto-load skipped: No local model selected")
                return
            }
            
            // Verify the model is downloaded
            guard let model = localModelManager.availableModels.first(where: { $0.id == modelId }),
                  model.downloadState.isDownloaded else {
                Logger.inference.debug("Auto-load skipped: Model not downloaded")
                return
            }
            
            Logger.inference.info("Auto-loading local model: \(modelId, privacy: .public)")
            try await loadModel(modelId: modelId)
            
        } catch {
            Logger.inference.error("Auto-load failed: \(error.localizedDescription, privacy: .public)")
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
            Logger.inference.debug("Model file size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file), privacy: .public)")
        } catch let error as GGUFServiceError {
            throw error
        } catch {
            Logger.inference.warning("Could not verify file attributes: \(String(describing: error), privacy: .public)")
        }
        
        // Validate GGUF file header
        do {
            try validateGGUFHeader(at: modelPath)
        } catch {
            throw error
        }
        
        let modelInfo = localModelManager.availableModels.first { $0.id == modelId }
        
        // Unload any existing model first
        unloadModel()
        
        isLoading = true
        errorMessage = nil
        
        Logger.inference.info("Loading GGUF model from: \(modelPath.path, privacy: .public)")
        
        // Get the model's context size, capped for mobile memory constraints
        // Full context (32K+) would use too much RAM for the KV cache
        let maxMobileContext = Int32(AppConstants.LocalModels.maxMobileContextTokens)
        let modelContextSize = Int32(modelInfo?.contextSize ?? AppConstants.LocalModels.maxMobileContextTokens)
        let contextSize = min(modelContextSize, maxMobileContext)
        Logger.inference.info("Using context size: \(contextSize) tokens (model supports \(modelContextSize))")
        
        // Load the model using LLM.swift with proper context size
        // The "Compiler failed to build request" error occurs when Metal shaders fail to compile
        guard let loadedLLM = await Self.makeLLM(from: modelPath, contextSize: contextSize) else {
            isLoading = false
            // Provide more helpful error message
            let errorDetails = """
            Failed to initialize LLM from file. This can happen due to:
            1. Incompatible GGUF format - try re-downloading the model
            2. Metal shader compilation failure - try restarting the app
            3. Insufficient memory - close other apps and try again
            4. Corrupted model file - delete and re-download
            """
            Logger.inference.error("\(errorDetails, privacy: .public)")
            let userFacingError = "Failed to load model. The model file may be incompatible or corrupted. Try deleting and re-downloading it."
            errorMessage = userFacingError
            throw GGUFServiceError.modelLoadFailed(userFacingError)
        }
        
        llm = loadedLLM

        Logger.inference.info("GGUF model loaded successfully")
        
        isModelLoaded = true
        loadedModelId = modelId
        isLoading = false
    }
    
    /// Unload the current model to free memory
    func unloadModel() {
        llm = nil
        isModelLoaded = false
        loadedModelId = nil
        currentConversationId = nil
        Logger.inference.info("GGUF model unloaded")
    }
    
    // MARK: - Text Generation
    
    /// Generate a streaming response for the given message
    /// - Parameters:
    ///   - message: The user's message to respond to
    ///   - history: The conversation history (excluding the current message) - only used when switching conversations
    ///   - conversationId: The ID of the current conversation - used to detect conversation switches
    func streamMessage(_ message: String, history: [Message], conversationId: UUID) -> AsyncThrowingStream<String, Error> {
        // Capture values needed for the detached task BEFORE creating the stream
        let llm = self.llm
        let previousGeneration = self.lastGenerationTask
        let isNewConversation = self.currentConversationId != conversationId

        // Only convert history if we're switching conversations
        let historyForLLM: [Chat]? = isNewConversation ? self.convertToLLMHistory(history) : nil

        let (stream, continuation) = AsyncThrowingStream.makeStream(of: String.self)
        let generationId = UUID()

        let task = Task.detached { [weak self] in
            await previousGeneration?.value

            guard let self, let llm, !Task.isCancelled else {
                continuation.finish(throwing: llm == nil ? GGUFServiceError.modelNotLoaded : nil)
                return
            }

            // Update UI state and track current conversation
            await MainActor.run {
                self.isGenerating = true
                self.currentTokenCount = 0
                self.generationStartTime = Date()
                self.lastGenerationStats = nil
                self.currentConversationId = conversationId
            }

            if isNewConversation {
                // Conversation changed - clear history and the KV cache, then load this chat's turns
                Logger.inference.debug("Conversation changed, resetting context")
                llm.reset()
                llm.history = historyForLLM ?? []
            } else {
                // Same conversation - LLM.swift already holds the previous turns and reuses
                // the KV cache for them, so only the new message gets evaluated
                Logger.inference.debug("Continuing conversation (LLM history: \(llm.history.count) turns)")
            }

            // Stream reasoning and the answer as one string, with reasoning wrapped in
            // <think> tags so MessageContentRenderer shows it as a thinking block.
            let output = ThinkingTagStream { text in
                if case .terminated = continuation.yield(text) {
                    // The reader is gone (Stop tapped or chat closed), so stop generating
                    llm.stop()
                }
                Task { @MainActor in
                    self.currentTokenCount += 1
                }
            }
            llm.updateThinking = { delta in
                if let delta {
                    output.thinking(Self.sanitizeText(delta))
                } else {
                    output.finish()
                }
            }
            llm.update = { delta in
                if let delta {
                    output.answer(Self.sanitizeText(delta))
                } else {
                    output.finish()
                }
            }

            // Renders the prompt with the model's own chat template, generates,
            // and appends this turn (answer only, no reasoning) to llm.history.
            // Reasoning is suppressed: LLM.swift otherwise forces it on, and small models
            // (Qwen3.5 ships with it off) can think for minutes on a phone before answering.
            await llm.respond(to: message, thinking: .suppressed)

            // Models without an embedded template fall back to ChatML, where <think> blocks
            // land in the answer. Strip them from history to save context space.
            let cleanedHistory = Self.buildCleanedHistory(from: llm.history)
            if cleanedHistory.count != llm.history.count ||
               zip(cleanedHistory, llm.history).contains(where: { $0.content != $1.content }) {
                llm.history = cleanedHistory
            }

            await MainActor.run {
                if let startTime = self.generationStartTime {
                    let duration = Date().timeIntervalSince(startTime)
                    let tokensPerSecond = duration > 0 ? Double(self.currentTokenCount) / duration : 0
                    self.lastGenerationStats = GenerationStats(
                        tokenCount: self.currentTokenCount,
                        durationSeconds: duration,
                        tokensPerSecond: tokensPerSecond
                    )
                }
                if self.currentGenerationId == generationId {
                    self.isGenerating = false
                }
            }

            continuation.finish()
        }

        // Synchronous assignments on MainActor (no async hop needed with makeStream)
        self.currentGenerationTask = task
        self.currentGenerationId = generationId
        self.lastGenerationTask = task

        continuation.onTermination = { @Sendable [weak self] _ in
            task.cancel()
            Task { @MainActor in
                if self?.currentGenerationId == generationId {
                    self?.llm?.stop()
                    self?.isGenerating = false
                    self?.currentGenerationTask = nil
                    self?.currentGenerationId = nil
                }
            }
        }

        return stream
    }
    
    /// Clear the current conversation context
    /// Call this when starting a brand new conversation
    func clearConversationContext() {
        if isGenerating { stopGeneration() }
        llm?.reset()
        currentConversationId = nil
        Logger.inference.debug("Conversation context cleared")
    }

    /// Build a cleaned copy of LLM history with thinking blocks stripped from bot responses.
    /// Pure function — operates on values, safe to call from any isolation context.
    nonisolated private static func buildCleanedHistory(from history: [Chat]) -> [Chat] {
        guard !history.isEmpty else { return [] }

        var cleanedHistory: [Chat] = []
        for chat in history {
            if chat.role == .bot {
                let cleanedContent = stripThinkingBlocks(from: chat.content)
                if !cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    cleanedHistory.append((role: .bot, content: cleanedContent))
                }
            } else {
                cleanedHistory.append(chat)
            }
        }
        return cleanedHistory
    }
    
    /// Convert app's Message array to LLM.swift's Chat history format
    /// Only used when switching conversations - for continuing the same conversation,
    /// we let LLM.swift manage history naturally.
    private func convertToLLMHistory(_ messages: [Message]) -> [Chat] {
        // Convert Message to Chat format, stripping thinking blocks from assistant responses
        // to avoid confusing the model (it should generate fresh thinking, not see old thinking in history)
        return messages.compactMap { message -> Chat? in
            let role: Role = message.role == Message.Role.user ? .user : .bot
            let content: String
            if role == .bot {
                // Strip <think>...</think> blocks from assistant messages
                content = Self.stripThinkingBlocks(from: message.content)
            } else {
                content = message.content
            }
            // Skip empty messages after stripping
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return (role: role, content: content)
        }
    }
    
    /// Remove <think>...</think> blocks from content
    /// These are the model's internal reasoning and shouldn't be included in history
    nonisolated static func stripThinkingBlocks(from content: String) -> String {
        // Use cached regex for performance (avoid recompiling on every call)
        guard let regex = Self.thinkingBlockRegex else {
            return content
        }
        let range = NSRange(content.startIndex..., in: content)
        let result = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
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
    nonisolated private static func sanitizeText(_ text: String) -> String {
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
    
    /// Create an LLM that formats chats with the template embedded in the GGUF file,
    /// falling back to ChatML for files that don't include one.
    nonisolated private static func makeLLM(from path: URL, contextSize: Int32) async -> LLM? {
        guard let llm = LLM(from: path, maxTokenCount: contextSize) else { return nil }
        llm.systemPrompt = systemPrompt
        if await llm.core.getChatTemplateHint() == nil {
            Logger.inference.info("Model has no embedded chat template, using ChatML")
            llm.template = .chatML(systemPrompt)
        }
        return llm
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
        Logger.inference.debug("GGUF file version: \(version)")
        
        // llama.cpp reads GGUF v3 (current); older versions may not load
        // Older versions (v1, v2) or future versions may not be compatible
        if version < 2 || version > 3 {
            Logger.inference.warning("GGUF version \(version) may not be fully supported. Current llama.cpp expects GGUF v3.")
        }
    }
}

