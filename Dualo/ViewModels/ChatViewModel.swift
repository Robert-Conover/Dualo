//
//  ChatViewModel.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import Foundation
import SwiftUI
import Combine
import OSLog

@MainActor
class ChatViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var isStreaming = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var apiConfiguration: APIConfiguration?
    @Published var streamingMessageContent = ""
    @Published var pendingAttachments: [ImageAttachment] = []

    // MARK: - Dependencies (injected for testability)
    private let apiService: APIServiceProtocol
    private let conversationManager: ConversationManaging
    private let contextTracker: ContextTracking

    private var streamingTask: Task<Void, Never>?
    private var currentConversationId: UUID?
    
    // MARK: - Streaming State
    
    /// The assistant placeholder being filled by the current stream
    private var streamingMessageId: UUID?
    /// The user message the current stream is replying to
    private var streamingUserMessageId: UUID?
    /// Whether the user message has been marked as sent (first token received)
    private var hasMarkedUserMessageSent = false
    private var throttle = StreamingThrottle()
    
    // Source-of-truth streaming buffer (NOT published).
    // We only publish snapshots to `streamingMessageContent` at a bounded cadence to
    // prevent per-chunk `@Published` updates from causing unbounded UI invalidations.
    private var streamingBuffer: String = ""
    
    /// Load of the chat's local model, so a message sent from HomeView can wait for it.
    private var localModelLoadTask: Task<Void, Error>?

    private var currentConversation: Conversation? {
        guard let conversationId = currentConversationId else { return nil }
        return conversationManager.conversations.first(where: { $0.id == conversationId })
    }

    // Read-only computed property that gets messages from ConversationManager
    var messages: [Message] {
        currentConversation?.messages ?? []
    }
    
    // MARK: - Initialization

    /// Initialize with default production dependencies
    init() {
        self.apiService = Self.defaultAPIService
        self.conversationManager = ConversationManager.shared
        self.contextTracker = ContextTracker.shared
        loadConfiguration()
    }

    private static var defaultAPIService: APIServiceProtocol {
        #if DEBUG
        if UITestSupport.isStubbingAPI { return StubAPIService() }
        #endif
        return APIService.shared
    }

    /// Initialize with custom dependencies (for testing)
    /// - Parameters:
    ///   - apiService: API service for cloud provider communication
    ///   - conversationManager: Conversation persistence manager
    ///   - contextTracker: Context window usage tracker
    init(
        apiService: APIServiceProtocol,
        conversationManager: ConversationManaging,
        contextTracker: ContextTracking
    ) {
        self.apiService = apiService
        self.conversationManager = conversationManager
        self.contextTracker = contextTracker
        loadConfiguration()
    }
    
    func loadConversation(_ conversation: Conversation) {
        Logger.chat.debug("Loading conversation \(conversation.id, privacy: .public) with \(conversation.messages.count) messages")
        currentConversationId = conversation.id
        Logger.chat.debug("Now tracking \(self.messages.count) messages")
        
        // Use the conversation's provider and model, not the currently selected default
        if let conversationConfig = configuration(for: conversation.provider, model: conversation.model) {
            apiConfiguration = conversationConfig
            Logger.chat.debug("Updated configuration to use \(conversation.provider.displayName, privacy: .public) with \(conversation.model, privacy: .public)")
        } else {
            Logger.chat.warning("No configuration found for provider \(conversation.provider.displayName, privacy: .public)")
        }
        
        if conversation.provider == .local {
            let modelId = conversation.model
            localModelLoadTask = Task { try await loadLocalModelIfNeeded(modelId: modelId) }
        }
        
        // Configure context tracker for this conversation
        contextTracker.configure(
            model: conversation.model,
            provider: conversation.provider,
            localModelManager: LocalModelManager.shared
        )
        contextTracker.updateFromMessages(conversation.messages)
        
        // Trigger UI update since messages is now a computed property
        objectWillChange.send()
    }
    
    /// The configuration for a provider and model: the stored API key for cloud providers,
    /// or a keyless configuration for local models. Nil if no key is stored for the provider.
    private func configuration(for provider: APIProvider, model: String) -> APIConfiguration? {
        if provider == .local {
            return APIConfiguration(provider: .local, apiKey: "", model: model)
        }
        #if DEBUG
        if UITestSupport.isStubbingAPI { return UITestSupport.stubConfiguration(provider: provider, model: model) }
        #endif
        do {
            guard let providerConfig = try KeychainService.shared.loadProviderConfigurations()?.configuration(for: provider) else {
                return nil
            }
            return APIConfiguration(provider: provider, apiKey: providerConfig.apiKey, model: model)
        } catch {
            Logger.chat.error("Failed to load provider configuration: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
    
    /// Load a local model if it's not already loaded
    private func loadLocalModelIfNeeded(modelId: String) async throws {
        let ggufService = GGUFService.shared
        
        // Skip if already loaded
        if ggufService.isModelLoaded && ggufService.loadedModelId == modelId {
            Logger.chat.debug("Local model \(modelId, privacy: .public) already loaded")
            return
        }
        
        // Verify the model is downloaded
        let localModelManager = LocalModelManager.shared
        guard let model = localModelManager.availableModels.first(where: { $0.id == modelId }),
              model.downloadState.isDownloaded else {
            Logger.chat.warning("Local model \(modelId, privacy: .public) not found or not downloaded")
            return
        }
        
        do {
            Logger.chat.info("Loading local model \(modelId, privacy: .public)")
            try await ggufService.loadModel(modelId: modelId)
        } catch {
            Logger.chat.error("Failed to load local model: \(String(describing: error), privacy: .public)")
            throw error
        }
    }
    
    // MARK: - Model Switching
    
    /// Whether the model can be changed right now; switching mid-generation can crash.
    var canSwitchModel: Bool {
        let ggufService = GGUFService.shared
        return !isStreaming && !isLoading && !ggufService.isLoading && !ggufService.isGenerating
    }
    
    /// Points the current conversation at a different model and reconfigures for it.
    /// For a local model this also loads it, and throws if loading fails.
    func switchModel(to modelId: String, provider: APIProvider) async throws {
        guard canSwitchModel else {
            Logger.chat.debug("Model switch blocked - streaming/loading in progress")
            return
        }
        guard var conversation = currentConversation else {
            Logger.chat.warning("Could not find conversation to switch model")
            return
        }
        
        // Free the local model's memory when moving to a cloud provider
        if provider != .local && GGUFService.shared.isModelLoaded {
            GGUFService.shared.unloadModel()
        }
        
        conversation.model = modelId
        conversation.provider = provider
        conversation.updatedAt = Date()
        conversationManager.updateConversation(conversation, moveToTop: true)
        
        contextTracker.configure(model: modelId, provider: provider, localModelManager: nil)
        contextTracker.updateFromMessages(conversation.messages)
        
        if let newConfig = configuration(for: provider, model: modelId) {
            apiConfiguration = newConfig
        }
        
        if provider == .local {
            LocalModelManager.shared.selectedModelId = modelId
            let loadTask = Task { try await loadLocalModelIfNeeded(modelId: modelId) }
            localModelLoadTask = loadTask
            try await loadTask.value
        }
    }
    
    /// Sends the message handed over from HomeView, first waiting for the chat's
    /// local model to finish loading.
    func sendWhenModelReady(_ text: String, attachments: [ImageAttachment]) async {
        if currentConversation?.provider == .local {
            try? await localModelLoadTask?.value
            guard GGUFService.shared.isModelLoaded else {
                Logger.chat.error("Local model failed to load, cannot send pending message")
                errorMessage = "Local model failed to load. Please try again."
                showError = true
                HapticFeedback.error()
                return
            }
        }
        
        pendingAttachments = attachments
        await sendMessage(text)
    }
    
    // MARK: - Sending
    
    func sendMessage(_ text: String) async {
        guard let config = sendableConfiguration(), currentConversationId != nil else { return }
        
        // Convert pending UI attachments to message attachments (dropped if the model can't take images)
        let attachments = config.provider.supportsImageAttachments
            ? pendingAttachments.compactMap { $0.toMessageAttachment() }
            : []
        pendingAttachments = []
        guard !text.isEmpty || !attachments.isEmpty else { return }

        let history = messages
        let userMessage = Message(role: Message.Role.user, content: text, attachments: attachments, sendStatus: .sending)
        addMessageToConversation(userMessage)
        
        startStreaming(text, history: history, attachments: attachments, userMessageId: userMessage.id, config: config)
    }
    
    /// Retry sending a failed message
    func retryMessage(_ messageId: UUID) async {
        guard let message = messages.first(where: { $0.id == messageId }),
              message.sendStatus == .failed,
              let config = sendableConfiguration() else {
            return
        }
        
        updateMessageStatus(messageId, status: .sending)
        
        // Get message history up to (but not including) this message
        let history = Array(messages.prefix(while: { $0.id != messageId }))
        
        startStreaming(message.content, history: history, attachments: message.attachments, userMessageId: messageId, config: config)
    }
    
    /// The current configuration if it can send (local, or cloud with a key); otherwise shows the setup error.
    private func sendableConfiguration() -> APIConfiguration? {
        guard let config = apiConfiguration,
              config.provider == .local || !config.apiKey.isEmpty else {
            errorMessage = StringConstants.Errors.configurationRequired
            showError = true
            return nil
        }
        return config
    }
    
    // MARK: - Streaming
    
    /// Adds an assistant placeholder and streams the reply to `text` into it.
    private func startStreaming(
        _ text: String,
        history: [Message],
        attachments: [MessageAttachment],
        userMessageId: UUID,
        config: APIConfiguration
    ) {
        isStreaming = true
        streamingBuffer = ""
        streamingMessageContent = ""
        streamingUserMessageId = userMessageId
        hasMarkedUserMessageSent = false
        throttle = StreamingThrottle()
        
        // Add a placeholder assistant message that we'll update
        let placeholderMessage = Message(role: Message.Role.assistant, content: "")
        addMessageToConversation(placeholderMessage)
        streamingMessageId = placeholderMessage.id
        
        Logger.chat.debug("Starting stream for conversation \(self.currentConversationId?.uuidString ?? "unknown", privacy: .public), message \(placeholderMessage.id, privacy: .public)")
        
        streamingTask = Task {
            do {
                let stream = apiService.streamMessage(
                    text,
                    history: history,
                    config: config,
                    attachments: attachments,
                    conversationId: currentConversationId
                )
                
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    
                    streamingBuffer += chunk
                    
                    // Mark user message as sent on first non-empty chunk (request was accepted)
                    if !hasMarkedUserMessageSent && !streamingBuffer.isEmpty,
                       let userMsgId = streamingUserMessageId {
                        hasMarkedUserMessageSent = true
                        updateMessageStatus(userMsgId, status: .sent)
                        
                        // Haptic feedback on first token - immediate confirmation message was accepted
                        HapticFeedback.light()
                        
                        Logger.chat.debug("Marked user message as sent (first token received)")
                    }
                    
                    // Update UI and persist with throttling (avoids excessive disk writes)
                    updateStreamingMessageContent()
                    
                    if streamingBuffer.count % AppConstants.UI.streamingProgressLogInterval == 0 {
                        Logger.chat.debug("Streaming progress - \(self.streamingBuffer.count) chars")
                    }
                }
                
                // stopStreaming() has already saved the partial reply and reset state
                guard !Task.isCancelled else { return }
                finishStreaming()
            } catch {
                if !Task.isCancelled {
                    handleStreamingError(error)
                }
            }
        }
    }
    
    private func updateStreamingMessageContent(forcePersist: Bool = false) {
        guard var conversation = currentConversation,
              let messageIndex = conversation.messages.firstIndex(where: { $0.id == streamingMessageId }) else {
            Logger.chat.warning("Unable to update streaming content: conversationId=\(self.currentConversationId?.uuidString ?? "nil", privacy: .public), streamingMessageId=\(self.streamingMessageId?.uuidString ?? "nil", privacy: .public)")
            return
        }
        
        let decision = throttle.check(length: streamingBuffer.count, force: forcePersist)
        
        if decision.persist {
            // IMPORTANT: Use streamingBuffer (source-of-truth), not the throttled published snapshot.
            conversation.messages[messageIndex].content = streamingBuffer
            conversation.updatedAt = Date()
            conversationManager.updateConversation(conversation, moveToTop: false)
            Logger.chat.debug("Persisted streaming content (\(self.streamingBuffer.count) chars\(forcePersist ? ", forced" : "", privacy: .public))")
        }
        
        if decision.updateUI {
            // Publish a snapshot for UI/autoscroll observers at a bounded cadence.
            streamingMessageContent = streamingBuffer
        }
    }
    
    private func finishStreaming() {
        // Force final persist to ensure all content is saved
        updateStreamingMessageContent(forcePersist: true)
        
        Logger.chat.debug("Streaming completed - final length: \(self.streamingBuffer.count) chars")
        
        // Update context tracker with final message content
        contextTracker.updateFromMessages(messages)
        
        // Mark user message as sent on success (if not already marked on first token)
        if !hasMarkedUserMessageSent, let userMsgId = streamingUserMessageId {
            updateMessageStatus(userMsgId, status: .sent)
        }
        
        resetStreamingState()
        
        // Explicitly trigger a view update to ensure conversation sync
        objectWillChange.send()
    }
    
    func stopStreaming() {
        Logger.chat.debug("Stopping stream - partial content length: \(self.streamingBuffer.count)")
        
        streamingTask?.cancel()
        apiService.stopStreaming()
        isStreaming = false
        
        // Preserve partial content if any exists, otherwise drop the empty placeholder
        if !streamingBuffer.isEmpty {
            updateStreamingMessageContent(forcePersist: true)
            Logger.chat.debug("Preserved partial streaming content (\(self.streamingBuffer.count) chars)")
        } else if let placeholderId = streamingMessageId {
            removeMessage(placeholderId)
            Logger.chat.debug("Removed empty placeholder message")
        }
        
        if let userMsgId = streamingUserMessageId {
            if hasMarkedUserMessageSent {
                // Content was received — user intentionally stopped, keep as sent
                updateMessageStatus(userMsgId, status: .sent)
                Logger.chat.debug("User stopped streaming after receiving content — marked as sent")
            } else {
                // No content received — mark as cancelled
                updateMessageStatus(userMsgId, status: .cancelled)
                Logger.chat.debug("User stopped streaming before content arrived — marked as cancelled")
            }
        }
        
        resetStreamingState()
        
        HapticFeedback.light()
    }
    
    private func handleStreamingError(_ error: Error) {
        if let networkError = error as? NetworkError {
            errorMessage = networkError.localizedDescription
        } else {
            errorMessage = "Streaming error: \(error.localizedDescription)"
        }
        showError = true
        
        // Remove the incomplete assistant message (placeholder)
        if let placeholderId = streamingMessageId {
            removeMessage(placeholderId)
        }
        
        // Mark user message as failed instead of removing it
        if let userMsgId = streamingUserMessageId {
            updateMessageStatus(userMsgId, status: .failed)
        }
        
        resetStreamingState()
        
        HapticFeedback.error()
    }
    
    private func resetStreamingState() {
        isStreaming = false
        streamingBuffer = ""
        streamingMessageContent = ""
        streamingMessageId = nil
        streamingUserMessageId = nil
        hasMarkedUserMessageSent = false
    }
    
    // MARK: - Configuration
    
    func refreshConfiguration() {
        loadConfiguration()
    }
    
    private func loadConfiguration() {
        do {
            if let providerConfigs = try KeychainService.shared.loadProviderConfigurations() {
                apiConfiguration = providerConfigs.currentConfiguration()
            } else if let legacyConfig = try KeychainService.shared.loadAPIConfiguration() {
                apiConfiguration = legacyConfig
            }
        } catch {
            Logger.chat.error("Failed to load API configuration: \(String(describing: error), privacy: .public)")
        }
        #if DEBUG
        if UITestSupport.isStubbingAPI && apiConfiguration == nil {
            apiConfiguration = UITestSupport.stubConfiguration()
        }
        #endif
    }
    
    // MARK: - Conversation Updates
    
    /// Applies `change` to the current conversation and saves it.
    private func updateCurrentConversation(moveToTop: Bool = false, _ change: (inout Conversation) -> Void) {
        guard var conversation = currentConversation else { return }
        change(&conversation)
        conversationManager.updateConversation(conversation, moveToTop: moveToTop)
        objectWillChange.send()
    }
    
    private func addMessageToConversation(_ message: Message) {
        updateCurrentConversation(moveToTop: true) { $0.addMessage(message) }
        
        // Update context tracker with new message count
        contextTracker.updateFromMessages(messages)
    }
    
    private func removeMessage(_ messageId: UUID) {
        updateCurrentConversation { $0.removeMessage(id: messageId) }
    }
    
    private func updateMessageStatus(_ messageId: UUID, status: SendStatus) {
        updateCurrentConversation { conversation in
            guard let index = conversation.messages.firstIndex(where: { $0.id == messageId }) else { return }
            conversation.messages[index].sendStatus = status
        }
    }
}
