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
class GGUFService: ObservableObject, GGUFServicing {
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
    private let localModelManager = LocalModelManager.shared
    
    /// Store model info for context recreation
    private var loadedModelPath: URL?
    private var loadedModelTemplate: Template?
    private var loadedModelContextSize: Int32 = Int32(AppConstants.LocalModels.maxMobileContextTokens)

    /// Cached regex for stripping thinking blocks (compiled once for performance)
    nonisolated private static let thinkingBlockRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "<think>[\\s\\S]*?</think>", options: [])
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
        
        // Get the model's context size, capped for mobile memory constraints
        // Full context (32K+) would use too much RAM for the KV cache
        let maxMobileContext = Int32(AppConstants.LocalModels.maxMobileContextTokens)
        let modelContextSize = Int32(modelInfo?.contextSize ?? AppConstants.LocalModels.maxMobileContextTokens)
        let contextSize = min(modelContextSize, maxMobileContext)
        print("📐 Using context size: \(contextSize) tokens (model supports \(modelContextSize))")
        
        // Load the model using LLM.swift with proper context size
        // The "Compiler failed to build request" error occurs when Metal shaders fail to compile
        guard let loadedLLM = LLM(from: modelPath, template: template, maxTokenCount: contextSize) else {
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
        loadedModelContextSize = contextSize
        
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
        loadedModelContextSize = Int32(AppConstants.LocalModels.maxMobileContextTokens)
        currentConversationId = nil
        print("🗑️ GGUF model unloaded")
    }
    
    // MARK: - Text Generation
    
    /// Generate a streaming response for the given message
    /// - Parameters:
    ///   - message: The user's message to respond to
    ///   - history: The conversation history (excluding the current message) - only used when switching conversations
    ///   - conversationId: The ID of the current conversation - used to detect conversation switches
    func streamMessage(_ message: String, history: [Message], conversationId: UUID) -> AsyncThrowingStream<String, Error> {
        // Capture values needed for the detached task BEFORE creating the stream
        let isLoaded = self.isModelLoaded
        let modelPath = self.loadedModelPath
        let template = self.loadedModelTemplate
        let contextSize = self.loadedModelContextSize
        let previousConversationId = self.currentConversationId
        let isNewConversation = previousConversationId != conversationId

        // Only convert history if we're switching conversations
        let historyForLLM: [Chat]? = isNewConversation ? self.convertToLLMHistory(history) : nil

        let (stream, continuation) = AsyncThrowingStream.makeStream(of: String.self)
        let generationId = UUID()

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

            // Update UI state and track current conversation
            await MainActor.run {
                self.isGenerating = true
                self.currentTokenCount = 0
                self.generationStartTime = Date()
                self.lastGenerationStats = nil
                self.currentConversationId = conversationId
            }

            // Get or create LLM instance
            let activeLLM: LLM

            if let existingLLM = await MainActor.run(body: { self.llm }) {
                if isNewConversation {
                    // Conversation changed - reset context and load new history
                    // LLM.swift v2.0.1: reset() clears history and resets KV cache
                    print("🔄 GGUFService: Conversation changed, resetting context")
                    existingLLM.reset()

                    // Load the new conversation's history (if any)
                    if let history = historyForLLM, !history.isEmpty {
                        print("📜 GGUFService: Loading \(history.count) history turns for new conversation")
                        existingLLM.history = history
                    }
                } else {
                    // Same conversation - let LLM.swift manage history naturally
                    // Don't touch history - it already has the previous turns
                    print("💬 GGUFService: Continuing conversation (LLM history: \(existingLLM.history.count) turns)")
                }
                activeLLM = existingLLM
            } else {
                // First use - create fresh LLM instance
                print("🔄 GGUFService: Creating new LLM instance (context: \(contextSize) tokens)")
                guard let freshLLM = LLM(from: modelPath, template: template, maxTokenCount: contextSize) else {
                    continuation.finish(throwing: GGUFServiceError.modelLoadFailed("Failed to load LLM"))
                    await MainActor.run {
                        self.isGenerating = false
                    }
                    return
                }

                // Load initial history if provided
                if let history = historyForLLM, !history.isEmpty {
                    print("📜 GGUFService: Loading \(history.count) initial history turns")
                    freshLLM.history = history
                }

                await MainActor.run {
                    self.llm = freshLLM
                }

                activeLLM = freshLLM
            }

            // Set up the update callback to stream tokens
            activeLLM.update = { [weak self] token in
                if let token = token {
                    let sanitizedToken = self?.sanitizeText(token) ?? token
                    continuation.yield(sanitizedToken)

                    Task { @MainActor in
                        self?.currentTokenCount += 1
                    }
                }
            }

            // Let LLM.swift handle everything - it will:
            // 1. Preprocess the message with its internal history
            // 2. Generate the response
            // 3. Automatically append this turn to history
            await activeLLM.respond(to: message)

            // Clean up: Strip thinking blocks from history to save context space
            // Thinking blocks are verbose (~200-400 tokens each) but not needed for context
            let cleanedHistory = Self.buildCleanedHistory(from: activeLLM.history)
            if cleanedHistory.count != activeLLM.history.count ||
               zip(cleanedHistory, activeLLM.history).contains(where: { $0.content != $1.content }) {
                activeLLM.history = cleanedHistory
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
                self.isGenerating = false
            }

            continuation.finish()
        }

        // Synchronous assignments on MainActor (no async hop needed with makeStream)
        self.currentGenerationTask = task
        self.currentGenerationId = generationId

        continuation.onTermination = { @Sendable [weak self] _ in
            task.cancel()
            Task { @MainActor in
                self?.llm?.stop()
                if self?.currentGenerationId == generationId {
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
        print("🧹 GGUFService: Conversation context cleared")
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
    nonisolated private static func stripThinkingBlocks(from content: String) -> String {
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
        
        // LLM.swift v2.x supports GGUF v3 format (recommended)
        // Older versions (v1, v2) or future versions may not be compatible
        if version < 2 || version > 3 {
            print("⚠️ Warning: GGUF version \(version) may not be fully supported. LLM.swift works best with GGUF v3.")
        }
    }
}

