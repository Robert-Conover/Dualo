//
//  ChatViewModel.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class ChatViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var isStreaming = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var apiConfiguration: APIConfiguration?
    @Published var streamingMessageContent = ""
    @Published var pendingAttachments: [ImageAttachment] = []

    private let apiService = APIService.shared
    private let conversationManager = ConversationManager.shared
    private let contextTracker = ContextTracker.shared
    private var streamingTask: Task<Void, Never>?
    private var currentConversationId: UUID?
    private var streamingMessageId: UUID?
    
    // Throttling for streaming persistence
    private var lastPersistTime: Date = .distantPast
    private var lastPersistedLength: Int = 0
    private let persistThrottleInterval: TimeInterval = 0.5 // Max once per 500ms
    private let persistCharThreshold: Int = 100 // Or every 100 characters
    
    // Throttling for streaming UI updates (avoids excessive view diffing)
    private var lastUIUpdateTime: Date = .distantPast
    
    // Source-of-truth streaming buffer (NOT published).
    // We only publish snapshots to `streamingMessageContent` at a bounded cadence to
    // prevent per-chunk `@Published` updates from causing unbounded UI invalidations.
    private var streamingBuffer: String = ""
    
    // Read-only computed property that gets messages from ConversationManager
    var messages: [Message] {
        guard let conversationId = currentConversationId,
              let conversation = conversationManager.conversations.first(where: { $0.id == conversationId }) else {
            return []
        }
        return conversation.messages
    }
    
    init() {
        loadConfiguration()
        // Don't auto-load messages anymore, they come from conversations
    }
    
    func loadConversation(_ conversation: Conversation) {
        print("ChatViewModel: loading conversation \(conversation.id) with \(conversation.messages.count) messages")
        currentConversationId = conversation.id
        print("ChatViewModel: viewModel now tracking \(messages.count) messages")
        
        // Get the correct API key for the conversation's provider (not the currently selected provider)
        do {
            if let providerConfigs = try KeychainService.shared.loadProviderConfigurations(),
               let providerConfig = providerConfigs.configuration(for: conversation.provider) {
                // Use the API key from the conversation's provider configuration
                let conversationConfig = APIConfiguration(
                    provider: conversation.provider,
                    apiKey: providerConfig.apiKey,
                    model: conversation.model
                )
                apiConfiguration = conversationConfig
                print("ChatViewModel: updated configuration to use \(conversation.provider.displayName) with \(conversation.model)")
            } else if conversation.provider == .local {
                // Local models don't need an API key
                let localConfig = APIConfiguration(
                    provider: .local,
                    apiKey: "",
                    model: conversation.model
                )
                apiConfiguration = localConfig
                print("ChatViewModel: updated configuration for local model \(conversation.model)")
                
                // Load the local model if not already loaded
                Task {
                    await loadLocalModelIfNeeded(modelId: conversation.model)
                }
            } else {
                print("ChatViewModel: Warning - No configuration found for provider \(conversation.provider.displayName)")
            }
        } catch {
            print("ChatViewModel: Failed to load provider configuration: \(error)")
        }
        
        // Configure context tracker for this conversation
        contextTracker.configure(
            model: conversation.model,
            provider: conversation.provider
        )
        contextTracker.updateFromMessages(conversation.messages)
        
        // Trigger UI update since messages is now a computed property
        objectWillChange.send()
    }
    
    /// Load a local model if it's not already loaded
    private func loadLocalModelIfNeeded(modelId: String) async {
        let ggufService = GGUFService.shared
        
        // Skip if already loaded
        if ggufService.isModelLoaded && ggufService.loadedModelId == modelId {
            print("ChatViewModel: Local model \(modelId) already loaded")
            return
        }
        
        // Verify the model is downloaded
        let localModelManager = LocalModelManager.shared
        guard let model = localModelManager.availableModels.first(where: { $0.id == modelId }),
              model.downloadState.isDownloaded else {
            print("ChatViewModel: Local model \(modelId) not found or not downloaded")
            return
        }
        
        do {
            print("ChatViewModel: Loading local model \(modelId)")
            try await ggufService.loadModel(modelId: modelId)
        } catch {
            print("ChatViewModel: Failed to load local model: \(error)")
        }
    }
    
    func sendMessage(_ text: String, useStreaming: Bool = true) async {
        guard let config = apiConfiguration,
              config.provider == .local || !config.apiKey.isEmpty else {
            errorMessage = StringConstants.Errors.configurationRequired
            showError = true
            return
        }

        guard currentConversationId != nil else { return }

        // Convert pending UI attachments to message attachments
        let messageAttachments = pendingAttachments.compactMap { $0.toMessageAttachment() }

        // Clear pending attachments after converting
        let attachmentsForRequest = messageAttachments
        pendingAttachments = []

        // Create user message with "sending" status
        let userMessage = Message(role: Message.Role.user, content: text, attachments: messageAttachments, sendStatus: .sending)
        addMessageToConversation(userMessage)
        let userMessageId = userMessage.id

        if useStreaming {
            await streamMessage(text, attachments: attachmentsForRequest, userMessageId: userMessageId)
        } else {
            isLoading = true

            do {
                let response = try await apiService.sendMessage(
                    text,
                    history: Array(messages.dropLast()),
                    config: config,
                    attachments: attachmentsForRequest,
                    conversationId: currentConversationId
                )

                // Mark user message as sent
                updateMessageStatus(userMessageId, status: .sent)
                
                let assistantMessage = Message(role: Message.Role.assistant, content: response)
                addMessageToConversation(assistantMessage)
            } catch {
                handleError(error, userMessageId: userMessageId)
            }

            isLoading = false
        }
    }
    
    private func addMessageToConversation(_ message: Message) {
        guard let conversationId = currentConversationId,
              var conversation = conversationManager.conversations.first(where: { $0.id == conversationId }) else {
            return
        }
        
        conversation.addMessage(message)
        conversationManager.updateConversation(conversation, moveToTop: true)
        
        // Update context tracker with new message count
        contextTracker.updateFromMessages(conversation.messages)
        
        objectWillChange.send()
    }
    
    private func updateStreamingMessageContent(forcePersist: Bool = false) {
        guard let conversationId = currentConversationId,
              var conversation = conversationManager.conversations.first(where: { $0.id == conversationId }),
              let messageIndex = conversation.messages.firstIndex(where: { $0.id == streamingMessageId }) else {
            #if DEBUG
            print("ChatViewModel: Warning - Unable to update streaming content: conversationId=\(currentConversationId?.uuidString ?? "nil"), streamingMessageId=\(streamingMessageId?.uuidString ?? "nil")")
            #endif
            return
        }
        
        // Update message content with current streaming content (in-memory)
        // IMPORTANT: Use streamingBuffer (source-of-truth), not the throttled published snapshot.
        conversation.messages[messageIndex].content = streamingBuffer
        conversation.updatedAt = Date()
        
        // Throttle persistence to avoid excessive disk writes
        // Only persist if: forced, enough time passed, OR enough new content accumulated
        let now = Date()
        let timeSinceLastPersist = now.timeIntervalSince(lastPersistTime)
        let currentLength = streamingBuffer.count
        let charsSinceLastPersist = currentLength - lastPersistedLength
        
        let shouldPersist = forcePersist ||
                           timeSinceLastPersist >= persistThrottleInterval ||
                           charsSinceLastPersist >= persistCharThreshold
        
        if shouldPersist {
            conversationManager.updateConversation(conversation, moveToTop: false)
            lastPersistTime = now
            lastPersistedLength = currentLength
            
            #if DEBUG
            print("ChatViewModel: Persisted streaming content (\(currentLength) chars, reason: \(forcePersist ? "forced" : timeSinceLastPersist >= persistThrottleInterval ? "time" : "chars"))")
            #endif
        }
        
        // Throttle UI updates to avoid excessive view diffing during high-frequency streaming
        let timeSinceLastUIUpdate = now.timeIntervalSince(lastUIUpdateTime)
        if forcePersist || timeSinceLastUIUpdate >= AppConstants.UI.streamingUIUpdateInterval {
            // Publish a snapshot for UI/autoscroll observers at a bounded cadence.
            streamingMessageContent = streamingBuffer
            lastUIUpdateTime = now
        }
    }
    
    /// Track the user message ID for the current streaming operation
    private var streamingUserMessageId: UUID?
    
    /// Track whether the user message has been marked as sent (first token received)
    private var hasMarkedUserMessageSent: Bool = false
    
    func streamMessage(_ text: String, attachments: [MessageAttachment] = [], userMessageId: UUID? = nil) async {
        guard let config = apiConfiguration,
              config.provider == .local || !config.apiKey.isEmpty else {
            errorMessage = StringConstants.Errors.configurationRequired
            showError = true
            return
        }

        isStreaming = true
        streamingBuffer = ""
        streamingMessageContent = ""
        streamingUserMessageId = userMessageId
        hasMarkedUserMessageSent = false

        // Add a placeholder assistant message that we'll update
        let placeholderMessage = Message(role: Message.Role.assistant, content: "")
        addMessageToConversation(placeholderMessage)
        streamingMessageId = placeholderMessage.id

        #if DEBUG
        print("ChatViewModel: Starting stream for conversation \(currentConversationId?.uuidString ?? "unknown"), message \(placeholderMessage.id)")
        #endif

        // Reset throttling state for new stream
        lastPersistTime = .distantPast
        lastPersistedLength = 0
        lastUIUpdateTime = .distantPast
        
        streamingTask = Task {
            do {
                let stream = apiService.streamMessage(
                    text,
                    history: Array(messages.dropLast(2)), // Exclude user message and placeholder
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
                        let sentFeedback = UIImpactFeedbackGenerator(style: .light)
                        sentFeedback.impactOccurred()

                        #if DEBUG
                        print("ChatViewModel: Marked user message as sent (first token received)")
                        #endif
                    }
                    
                    // Update UI and persist with throttling (avoids excessive disk writes)
                    updateStreamingMessageContent()
                    
                    #if DEBUG
                    if streamingBuffer.count % AppConstants.UI.streamingProgressLogInterval == 0 {
                        print("ChatViewModel: Streaming progress - \(streamingBuffer.count) chars")
                    }
                    #endif
                }
                
                // Force final persist to ensure all content is saved
                updateStreamingMessageContent(forcePersist: true)
                
                #if DEBUG
                print("ChatViewModel: Streaming completed - final length: \(streamingMessageContent.count) chars")
                #endif
                
                // Update context tracker with final message content
                if let conversationId = currentConversationId,
                   let conversation = conversationManager.conversations.first(where: { $0.id == conversationId }) {
                    contextTracker.updateFromMessages(conversation.messages)
                }
                
                // Mark user message as sent on success (if not already marked on first token)
                if !hasMarkedUserMessageSent, let userMsgId = streamingUserMessageId {
                    updateMessageStatus(userMsgId, status: .sent)
                }
                
                // Streaming completed successfully
                isStreaming = false
                streamingBuffer = ""
                streamingMessageContent = ""
                streamingMessageId = nil
                streamingUserMessageId = nil
                
                // Explicitly trigger a view update to ensure conversation sync
                objectWillChange.send()

            } catch {
                if !Task.isCancelled {
                    handleStreamingError(error)
                }
            }
        }
    }
    
    func stopStreaming() {
        #if DEBUG
        print("ChatViewModel: Stopping stream - partial content length: \(streamingBuffer.count)")
        #endif
        
        streamingTask?.cancel()
        apiService.stopStreaming()
        isStreaming = false
        
        // Preserve partial content if any exists
        if !streamingBuffer.isEmpty {
            updateStreamingMessageContent(forcePersist: true) // Force persist on stop
            #if DEBUG
            print("ChatViewModel: Preserved partial streaming content (\(streamingBuffer.count) chars)")
            #endif
        } else if !messages.isEmpty && messages.last?.content.isEmpty == true {
            // Only remove if truly empty
            removeLastMessage()
            #if DEBUG
            print("ChatViewModel: Removed empty placeholder message")
            #endif
        }
        
        // Mark user message as failed on stop (shows retry affordance)
        // Must do this BEFORE clearing streamingUserMessageId
        if let userMsgId = streamingUserMessageId {
            updateMessageStatus(userMsgId, status: .failed)
            #if DEBUG
            print("ChatViewModel: Marked user message as failed due to stop")
            #endif
        }
        
        streamingBuffer = ""
        streamingMessageContent = ""
        streamingMessageId = nil
        streamingUserMessageId = nil  // Clear to prevent background task from overwriting status
        hasMarkedUserMessageSent = false
        
        let cancelFeedback = UIImpactFeedbackGenerator(style: .light)
        cancelFeedback.impactOccurred()
    }
    
    func clearConversation() {
        guard let conversationId = currentConversationId,
              var conversation = conversationManager.conversations.first(where: { $0.id == conversationId }) else {
            return
        }
        
        conversation.clearMessages()
        conversationManager.updateConversation(conversation, moveToTop: false)
        objectWillChange.send()
    }
    
    func retryLastMessage() async {
        guard let lastUserMessage = messages.last(where: { $0.role == Message.Role.user }) else {
            return
        }
        
        if messages.last?.role == Message.Role.assistant {
            removeLastMessage()
        }
        
        await sendMessage(lastUserMessage.content)
    }
    
    private func removeLastMessage() {
        guard let conversationId = currentConversationId,
              var conversation = conversationManager.conversations.first(where: { $0.id == conversationId }) else {
            return
        }
        
        conversation.removeLastMessage()
        conversationManager.updateConversation(conversation, moveToTop: false)
        objectWillChange.send()
    }
    
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
            print("Failed to load API configuration: \(error)")
        }
    }
    
    
    private func handleError(_ error: Error, userMessageId: UUID? = nil) {
        if let networkError = error as? NetworkError {
            errorMessage = networkError.localizedDescription
        } else {
            errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
        }
        showError = true
        
        // Mark user message as failed instead of removing it
        if let msgId = userMessageId {
            updateMessageStatus(msgId, status: .failed)
        }
    }
    
    private func handleStreamingError(_ error: Error) {
        isStreaming = false
        streamingBuffer = ""
        streamingMessageContent = ""
        
        if let networkError = error as? NetworkError {
            errorMessage = networkError.localizedDescription
        } else {
            errorMessage = "Streaming error: \(error.localizedDescription)"
        }
        showError = true
        
        // Remove the incomplete assistant message (placeholder)
        if !messages.isEmpty && messages.last?.role == Message.Role.assistant {
            removeLastMessage()
        }
        
        // Mark user message as failed instead of removing it
        if let userMsgId = streamingUserMessageId {
            updateMessageStatus(userMsgId, status: .failed)
        }
        
        streamingUserMessageId = nil
        
        let errorFeedback = UINotificationFeedbackGenerator()
        errorFeedback.notificationOccurred(.error)
    }
    
    // MARK: - Message Status Updates
    
    private func updateMessageStatus(_ messageId: UUID, status: SendStatus) {
        guard let conversationId = currentConversationId,
              var conversation = conversationManager.conversations.first(where: { $0.id == conversationId }),
              let messageIndex = conversation.messages.firstIndex(where: { $0.id == messageId }) else {
            return
        }
        
        conversation.messages[messageIndex].sendStatus = status
        conversationManager.updateConversation(conversation, moveToTop: false)
        objectWillChange.send()
    }
    
    /// Retry sending a failed message
    func retryMessage(_ messageId: UUID) async {
        guard let conversationId = currentConversationId,
              let conversation = conversationManager.conversations.first(where: { $0.id == conversationId }),
              let message = conversation.messages.first(where: { $0.id == messageId }),
              message.sendStatus == .failed else {
            return
        }
        
        // Mark as sending again
        updateMessageStatus(messageId, status: .sending)
        
        guard let config = apiConfiguration,
              config.provider == .local || !config.apiKey.isEmpty else {
            updateMessageStatus(messageId, status: .failed)
            errorMessage = StringConstants.Errors.configurationRequired
            showError = true
            return
        }
        
        // Get message history up to (but not including) this message
        let historyUpToMessage = Array(messages.prefix(while: { $0.id != messageId }))
        
        isStreaming = true
        streamingBuffer = ""
        streamingMessageContent = ""
        streamingUserMessageId = messageId
        hasMarkedUserMessageSent = false
        
        // Add a placeholder assistant message
        let placeholderMessage = Message(role: Message.Role.assistant, content: "")
        addMessageToConversation(placeholderMessage)
        streamingMessageId = placeholderMessage.id
        
        // Reset throttling state
        lastPersistTime = .distantPast
        lastPersistedLength = 0
        lastUIUpdateTime = .distantPast
        
        streamingTask = Task {
            do {
                let stream = apiService.streamMessage(
                    message.content,
                    history: historyUpToMessage,
                    config: config,
                    attachments: message.attachments,
                    conversationId: conversationId
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
                        let sentFeedback = UIImpactFeedbackGenerator(style: .light)
                        sentFeedback.impactOccurred()
                    }

                    updateStreamingMessageContent()
                }

                updateStreamingMessageContent(forcePersist: true)

                // Mark user message as sent (if not already marked on first token)
                if !hasMarkedUserMessageSent {
                    updateMessageStatus(messageId, status: .sent)
                }

                isStreaming = false
                streamingBuffer = ""
                streamingMessageContent = ""
                streamingMessageId = nil
                streamingUserMessageId = nil

                objectWillChange.send()
                
            } catch {
                if !Task.isCancelled {
                    handleStreamingError(error)
                }
            }
        }
    }
    
}