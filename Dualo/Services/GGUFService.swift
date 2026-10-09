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
    case messageTooLong

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
        case .messageTooLong:
            return "This message is too long for the model to read. Try a shorter one."
        }
    }
}

// MARK: - Generation Statistics

struct GenerationStats {
    /// The chat the reply was for, so other chats don't show its stats
    let conversationId: UUID
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
    /// What the model remembers of the chat it's serving
    @Published private(set) var memory: ModelMemory?
    
    // MARK: - Performance Statistics
    @Published var lastGenerationStats: GenerationStats?
    @Published var currentTokenCount: Int = 0
    @Published var generationStartTime: Date?
    
    // MARK: - Private Properties
    
    private(set) var llm: LLM?
    private var currentGenerationTask: Task<Void, Never>?
    private var currentGenerationId: UUID?
    /// The most recent generation, stopped or not. Each new one waits for it to wind down,
    /// because LLM.swift silently ignores a `respond` call while another is still running.
    private var lastGenerationTask: Task<Void, Never>?
    /// Tokens the loaded model's context holds
    private var contextSize = AppConstants.LocalModels.maxMobileContextTokens
    private let localModelManager = LocalModelManager.shared

    nonisolated private static let baseSystemPrompt = "You are a helpful assistant."

    /// The system prompt with the user's custom instructions, if any, added after the base prompt.
    nonisolated static func systemPrompt(with instructions: String) -> String {
        instructions.isEmpty ? baseSystemPrompt : "\(baseSystemPrompt)\n\n\(instructions)"
    }

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
        self.contextSize = Int(contextSize)

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
        memory = nil
        Logger.inference.info("GGUF model unloaded")
    }
    
    // MARK: - Text Generation
    
    /// Generate a streaming response for the given message
    /// - Parameters:
    ///   - message: The user's message to respond to
    ///   - history: The conversation so far (excluding the current message). The model sees
    ///     as much of it as fits in its context, newest first.
    ///   - conversationId: The ID of the current conversation - used to detect conversation switches
    func streamMessage(_ message: String, history: [Message], conversationId: UUID) -> AsyncThrowingStream<String, Error> {
        // Capture values needed for the detached task BEFORE creating the stream
        let llm = self.llm
        let previousGeneration = self.lastGenerationTask
        let isNewConversation = self.currentConversationId != conversationId
        let systemPrompt = Self.systemPrompt(with: CustomInstructions.current)
        let entries = Self.memoryEntries(from: history)
        let contextSize = self.contextSize
        let lastForgottenId = lastForgottenMessageId(in: conversationId)

        let (stream, continuation) = AsyncThrowingStream.makeStream(of: String.self)
        let generationId = UUID()

        let task = Task.detached { [weak self] in
            await previousGeneration?.value

            guard let self, let llm, !Task.isCancelled else {
                continuation.finish(throwing: llm == nil ? GGUFServiceError.modelNotLoaded : nil)
                return
            }

            let plan = await Self.planMemory(
                for: entries, message: message, systemPrompt: systemPrompt, lastForgottenId: lastForgottenId,
                conversationId: conversationId, contextSize: contextSize, llm: llm
            )
            guard plan.fits else {
                continuation.finish(throwing: GGUFServiceError.messageTooLong)
                return
            }

            // Update UI state and track current conversation
            await MainActor.run {
                self.isGenerating = true
                self.currentTokenCount = 0
                self.generationStartTime = Date()
                self.lastGenerationStats = nil
                self.currentConversationId = conversationId
                self.memory = plan.memory
            }

            Self.apply(systemPrompt, to: llm)

            if isNewConversation {
                // Conversation changed - clear the KV cache
                Logger.inference.debug("Conversation changed, resetting context")
                llm.reset()
            }
            // The app's copy of the chat is the one the model sees, so edits and removed turns
            // carry over. LLM.swift reuses the KV cache for however much of the prompt still
            // matches, which within a chat is everything before the new message (for Qwen3.5,
            // from a checkpoint at the end of the last one).
            llm.history = plan.history
            Logger.inference.debug("Remembering \(plan.history.count) of \(entries.count) messages")

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

            // Renders the prompt with the model's own chat template and generates.
            // Reasoning is suppressed: LLM.swift otherwise forces it on, and small models
            // (Qwen3.5 ships with it off) can think for minutes on a phone before answering.
            await llm.respond(to: message, thinking: .suppressed)

            await MainActor.run {
                if let startTime = self.generationStartTime {
                    let duration = Date().timeIntervalSince(startTime)
                    let tokensPerSecond = duration > 0 ? Double(self.currentTokenCount) / duration : 0
                    self.lastGenerationStats = GenerationStats(
                        conversationId: conversationId,
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
    
    /// Works out what the model will remember of a chat when its next message is sent,
    /// so the chat can show where that memory starts before then.
    func refreshMemory(of messages: [Message], conversationId: UUID) async {
        await lastGenerationTask?.value
        guard let llm else { return }
        let plan = await Self.planMemory(
            for: Self.memoryEntries(from: messages), message: nil,
            systemPrompt: Self.systemPrompt(with: CustomInstructions.current),
            lastForgottenId: lastForgottenMessageId(in: conversationId),
            conversationId: conversationId, contextSize: contextSize, llm: llm
        )
        // The model may have changed or started on another chat in the meantime
        guard llm === self.llm, !isGenerating else { return }
        memory = plan.memory
    }

    /// Clear the current conversation context
    /// Call this when starting a brand new conversation
    func clearConversationContext() {
        if isGenerating { stopGeneration() }
        llm?.reset()
        currentConversationId = nil
        Logger.inference.debug("Conversation context cleared")
    }

    /// A chat's messages as the model sees them, each with the id of the message it came from.
    /// Reasoning is left out of replies, since the model should think afresh rather than
    /// read old thinking, and messages left empty are skipped.
    nonisolated static func memoryEntries(from messages: [Message]) -> [(id: UUID, chat: Chat)] {
        messages.compactMap { message in
            let role: Role = message.role == Message.Role.user ? .user : .bot
            let content = role == .bot ? stripThinkingBlocks(from: message.content) : message.content
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return (id: message.id, chat: (role: role, content: content))
        }
    }

    /// The newest message the model has already forgotten in this chat, if any
    private func lastForgottenMessageId(in conversationId: UUID) -> UUID? {
        memory?.conversationId == conversationId ? memory?.lastForgottenMessageId : nil
    }

    /// The newest messages that fit in the model's context alongside the system prompt, the
    /// new message (none when looking ahead to the next one) and room for the reply. Messages
    /// after `lastForgottenId` stay while they fit, so the chat's start doesn't move every time.
    nonisolated private static func planMemory(
        for entries: [(id: UUID, chat: Chat)],
        message: String?,
        systemPrompt: String,
        lastForgottenId: UUID?,
        conversationId: UUID,
        contextSize: Int,
        llm: LLM
    ) async -> (history: [Chat], memory: ModelMemory, fits: Bool) {
        func tokens(_ text: String) async -> Int {
            await llm.encode(text, shouldAddBOS: false).count + ModelMemoryBudget.tokensPerMessage
        }

        var fixedTokens = await tokens(systemPrompt) + ModelMemoryBudget.replyPreambleTokens
        if let message {
            fixedTokens += await tokens(message)
        }
        var sizes: [Int] = []
        for entry in entries {
            sizes.append(await tokens(entry.chat.content))
        }

        let available = contextSize - ModelMemoryBudget.replyReserve(contextSize: contextSize)
        let kept = ModelMemoryBudget.rememberedCount(
            sizes: sizes,
            isUserMessage: entries.map { $0.chat.role == .user },
            budget: available - fixedTokens,
            forgottenCount: entries.firstIndex { $0.id == lastForgottenId }.map { $0 + 1 } ?? 0
        )
        let memory = ModelMemory(
            conversationId: conversationId,
            lastForgottenMessageId: kept < entries.count ? entries[entries.count - kept - 1].id : nil,
            usedTokens: fixedTokens + sizes.suffix(kept).reduce(0, +),
            availableTokens: available
        )
        return (
            history: entries.suffix(kept).map(\.chat),
            memory: memory,
            fits: fixedTokens <= contextSize - ModelMemoryBudget.minimumReplyTokens
        )
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
    /// Makes the loaded model always pick its most likely next token, so the same
    /// prompts get the same replies. Tests use it so a lucky or unlucky draw can't decide
    /// whether they pass; the app keeps sampling.
    func useGreedySampling() {
        llm?.temp = 0
    }

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
        llm.systemPrompt = baseSystemPrompt
        if await llm.core.getChatTemplateHint() == nil {
            Logger.inference.info("Model has no embedded chat template, using ChatML")
            llm.template = .chatML(baseSystemPrompt)
        }
        return llm
    }

    /// Switch the LLM to a new system prompt (custom instructions can change between messages).
    /// The KV cache keeps whatever still matches, so the next reply re-reads the chat from the change.
    nonisolated private static func apply(_ systemPrompt: String, to llm: LLM) {
        guard llm.systemPrompt != systemPrompt else { return }
        llm.systemPrompt = systemPrompt
        // The ChatML fallback bakes the system prompt into its template
        if llm.template != nil {
            llm.template = .chatML(systemPrompt)
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
        Logger.inference.debug("GGUF file version: \(version)")
        
        // llama.cpp reads GGUF v3 (current); older versions may not load
        // Older versions (v1, v2) or future versions may not be compatible
        if version < 2 || version > 3 {
            Logger.inference.warning("GGUF version \(version) may not be fully supported. Current llama.cpp expects GGUF v3.")
        }
    }
}

