//
//  SimpleChatView.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI
import UIKit
import OSLog

struct SimpleChatView: View {
    let conversationId: UUID

    /// Always returns the freshest conversation from ConversationManager — never stale.
    private var conversation: Conversation? {
        conversationManager.conversations.first(where: { $0.id == conversationId })
    }
    @StateObject private var viewModel = ChatViewModel()
    @EnvironmentObject var conversationManager: ConversationManager
    @EnvironmentObject var localModelManager: LocalModelManager
    @EnvironmentObject var ggufService: GGUFService
    @EnvironmentObject var contextTracker: ContextTracker
    @State private var messageText = ""
    @State private var showScrollToBottom = false
    @FocusState private var isInputFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showRenameAlert = false
    @State private var newTitle = ""
    @State private var showExportError = false
    @State private var exportErrorMessage = ""
    @State private var currentTitle = ""
    @State private var currentModel = ""
    @State private var currentProvider: APIProvider = .openai

    // Image picker state
    @State private var showAttachmentOptions = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var pendingAttachments: [ImageAttachment] = []
    @State private var capturedImage: ImageAttachment?
    @State private var showGenerationStats = false
    @State private var showModelLoadError = false
    @State private var modelLoadErrorMessage = ""

    // Scroll to bottom action
    @State private var performScrollToBottom: (() -> Void)?

    var body: some View {
        mainContentView
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .modifier(ChatAlertsModifier(
                showError: $viewModel.showError,
                errorMessage: viewModel.errorMessage,
                showRenameAlert: $showRenameAlert,
                newTitle: $newTitle,
                showExportError: $showExportError,
                exportErrorMessage: exportErrorMessage,
                showModelLoadError: $showModelLoadError,
                modelLoadErrorMessage: modelLoadErrorMessage,
                renameChat: renameChat
            ))
            .modifier(AttachmentPickerModifier(
                showAttachmentOptions: $showAttachmentOptions,
                showPhotoPicker: $showPhotoPicker,
                showCamera: $showCamera,
                pendingAttachments: $pendingAttachments,
                capturedImage: $capturedImage
            ))
            .background(Color.theme.chatBackground)
            .onAppear(perform: handleOnAppear)
            .onChange(of: conversationManager.conversations, handleConversationsChange)
            .onChange(of: viewModel.isStreaming, handleStreamingChange)
    }
    
    // MARK: - Lifecycle Event Handlers (extracted to reduce body complexity)
    
    private func handleOnAppear() {
        guard let conversation = conversation else {
            Logger.ui.warning("SimpleChatView onAppear: conversation not found for id \(conversationId, privacy: .public)")
            return
        }
        Logger.ui.debug("SimpleChatView onAppear: conversation.id = \(conversation.id, privacy: .public), messages count = \(conversation.messages.count)")
        // Initialize the current state variables
        currentTitle = conversation.title
        currentModel = conversation.model
        currentProvider = conversation.provider
        // Refresh configuration to pick up any changes from settings
        viewModel.refreshConfiguration()
        // Ensure this conversation is selected in the manager
        conversationManager.selectConversation(conversation)
        viewModel.loadConversation(conversation)
        
        // Configure context tracker (also done in loadConversation, but ensure it's set)
        contextTracker.configure(model: conversation.model, provider: conversation.provider)
        contextTracker.updateFromMessages(conversation.messages)
        
        // Check for pending initial message + attachments from HomeView
        if let pendingData = conversationManager.pendingChatData {
            Logger.ui.debug("Found pending message: \(pendingData.message), attachments: \(pendingData.attachments.count)")
            conversationManager.pendingChatData = nil
            
            // Transfer attachments to viewModel before sending
            viewModel.pendingAttachments = pendingData.attachments
            
            Task {
                await sendPendingMessage(pendingData.message)
            }
        }
    }
    
    private func sendPendingMessage(_ message: String) async {
        // For local models, wait for the model to load before sending
        if conversation?.provider == .local {
            Logger.ui.debug("SimpleChatView: Waiting for local model to load...")
            // Wait for model to be loaded (with timeout)
            var waitAttempts = 0
            let maxWaitAttempts = 100 // 10 seconds max (100 * 100ms)
            while !ggufService.isModelLoaded && ggufService.isLoading && waitAttempts < maxWaitAttempts {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                waitAttempts += 1
            }
            
            if !ggufService.isModelLoaded {
                Logger.ui.error("SimpleChatView: Local model failed to load, cannot send pending message")
                viewModel.errorMessage = "Local model failed to load. Please try again."
                viewModel.showError = true
                HapticFeedback.error()
                return
            }
            Logger.ui.debug("SimpleChatView: Local model loaded, sending pending message")
        }
        
        await viewModel.sendMessage(message, useStreaming: true)
    }
    
    private func handleConversationsChange(_ oldValue: [Conversation], _ newValue: [Conversation]) {
        // Update local state when the conversation changes
        if let updatedConversation = newValue.first(where: { $0.id == conversationId }) {
            // Only update UI state if the conversation data actually changed
            if updatedConversation.title != currentTitle {
                currentTitle = updatedConversation.title
            }
            if updatedConversation.model != currentModel {
                currentModel = updatedConversation.model
            }
            if updatedConversation.provider != currentProvider {
                currentProvider = updatedConversation.provider
            }
        }
    }
    
    private func handleStreamingChange(_ oldValue: Bool, _ newValue: Bool) {
        // Streaming state changed - no need to manually persist since ChatViewModel handles it
        if oldValue && !newValue {
            Logger.ui.debug("SimpleChatView: Streaming completed")
            
            // Show generation stats for local models
            if currentProvider == .local && ggufService.lastGenerationStats != nil {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showGenerationStats = true
                }
                
                // Auto-hide after 8 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showGenerationStats = false
                    }
                }
            }
        }
    }
    
    // MARK: - Message List

    private var messagesList: some View {
        MessageListView(
            viewModel: viewModel,
            currentProvider: currentProvider,
            showScrollToBottom: $showScrollToBottom,
            scrollToBottomAction: $performScrollToBottom,
            isInputFocused: $isInputFocused
        )
    }

    private func scrollToBottom() {
        HapticFeedback.light()
        performScrollToBottom?()
    }
    
    // MARK: - Input Bar

    private var inputBar: some View {
        ChatInputBar(
            viewModel: viewModel,
            ggufService: ggufService,
            contextTracker: contextTracker,
            messageText: $messageText,
            pendingAttachments: $pendingAttachments,
            showAttachmentOptions: $showAttachmentOptions,
            showGenerationStats: $showGenerationStats,
            isInputFocused: $isInputFocused,
            currentProvider: currentProvider,
            onSendMessage: sendMessage
        )
    }
    
    // MARK: - Main Content View (extracted to reduce body complexity)
    
    @ViewBuilder
    private var mainContentView: some View {
        VStack(spacing: 0) {
            if viewModel.messages.isEmpty {
                ChatEmptyStateView(isLoadingModel: ggufService.isLoading) { prompt in
                    messageText = prompt
                    isInputFocused = true
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isInputFocused = false
                }
            } else {
                ZStack(alignment: .bottomTrailing) {
                    messagesList
                    ScrollToBottomButton(
                        isVisible: showScrollToBottom && !viewModel.isStreaming,
                        action: scrollToBottom
                    )
                }
            }
            
            inputBar
        }
    }
    
    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            ModelSelectorMenu(
                currentModel: currentModel,
                currentProvider: currentProvider,
                isDisabled: isModelSwitchingDisabled,
                onSelectCloudModel: changeConversationModel,
                onSelectLocalModel: changeToLocalModel
            )
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            ChatOptionsMenu(
                isDisabled: viewModel.messages.isEmpty,
                onRename: {
                    newTitle = currentTitle.isEmpty ? (conversation?.title ?? "") : currentTitle
                    showRenameAlert = true
                },
                onExport: export
            )
        }
    }

    /// Whether model switching should be disabled (during streaming/loading to prevent crashes)
    private var isModelSwitchingDisabled: Bool {
        viewModel.isStreaming || viewModel.isLoading || ggufService.isLoading || ggufService.isGenerating
    }

    private func sendMessage() {
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Allow sending with just attachments (no text required)
        guard !trimmedMessage.isEmpty || !pendingAttachments.isEmpty else { return }

        // Transfer attachments to viewModel
        viewModel.pendingAttachments = pendingAttachments
        pendingAttachments = []

        Task {
            await viewModel.sendMessage(trimmedMessage, useStreaming: true)
        }

        messageText = ""
        isInputFocused = false
    }
    
    private func renameChat(to newTitle: String) {
        Logger.ui.debug("SimpleChatView: Renaming chat from '\(conversation?.title ?? "")' to '\(newTitle)'")
        
        guard var updatedConversation = conversation else {
            Logger.ui.warning("SimpleChatView: Could not find conversation to rename")
            return
        }
        updatedConversation.title = newTitle
        updatedConversation.updatedAt = Date()
        conversationManager.updateConversation(updatedConversation, moveToTop: true)
        currentTitle = newTitle
    }
    
    private func changeConversationModel(to newModel: String, provider: APIProvider) {
        // Safety guard: prevent model switching during streaming/generation
        guard !isModelSwitchingDisabled else {
            Logger.ui.debug("SimpleChatView: Model switch blocked - streaming/loading in progress")
            return
        }
        
        // Unload local model when switching to API provider
        if provider != .local && GGUFService.shared.isModelLoaded {
            GGUFService.shared.unloadModel()
        }
        
        guard var updatedConversation = conversation else {
            Logger.ui.warning("SimpleChatView: Could not find conversation to update model")
            return
        }
        updatedConversation.model = newModel
        updatedConversation.provider = provider
        updatedConversation.updatedAt = Date()
        conversationManager.updateConversation(updatedConversation, moveToTop: true)
        
        // Update local state immediately to reflect the change in UI
        currentModel = newModel
        currentProvider = provider
        
        // Update context tracker for new model
        contextTracker.configure(model: newModel, provider: provider)
        contextTracker.updateFromMessages(viewModel.messages)
        
        // Update the ChatViewModel configuration to use the new provider and model
        do {
            if let configs = try KeychainService.shared.loadProviderConfigurations() {
                if let existingConfig = configs.configuration(for: provider) {
                    let newConfig = APIConfiguration(
                        provider: provider,
                        apiKey: existingConfig.apiKey,
                        model: newModel
                    )
                    viewModel.apiConfiguration = newConfig
                }
            }
        } catch {
            Logger.config.error("Failed to load provider configuration for \(provider.displayName, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
    
    private func changeToLocalModel(_ model: LocalModel) {
        // Safety guard: prevent model switching during streaming/generation
        guard !isModelSwitchingDisabled else {
            Logger.ui.debug("SimpleChatView: Local model switch blocked - streaming/loading in progress")
            return
        }
        
        guard var updatedConversation = conversation else {
            Logger.ui.warning("SimpleChatView: Could not find conversation to update to local model")
            return
        }
        updatedConversation.model = model.id
        updatedConversation.provider = .local
        updatedConversation.updatedAt = Date()
        conversationManager.updateConversation(updatedConversation, moveToTop: true)
        
        // Update local state
        currentModel = model.id
        currentProvider = .local
        
        // Update context tracker for local model
        contextTracker.configure(model: model.id, provider: .local)
        contextTracker.updateFromMessages(viewModel.messages)
        
        // Set the selected model in LocalModelManager
        localModelManager.selectedModelId = model.id
        
        // Create local configuration
        let localConfig = APIConfiguration(
            provider: .local,
            apiKey: "",
            model: model.id
        )
        viewModel.apiConfiguration = localConfig
        
        // Load the model in GGUFService
        Task {
            do {
                try await GGUFService.shared.loadModel(modelId: model.id)
            } catch {
                Logger.inference.error("Failed to load local model: \(String(describing: error), privacy: .public)")
                modelLoadErrorMessage = error.localizedDescription
                showModelLoadError = true
            }
        }
    }
    
    private func export(_ format: ChatExportService.Format) {
        guard let conversation = conversation else { return }
        Task { @MainActor in
            do {
                try await ChatExportService().share(conversation, as: format)
            } catch {
                exportErrorMessage = "Failed to export \(format.displayName): \(error.localizedDescription)"
                showExportError = true
            }
        }
    }
}

#Preview {
    NavigationStack {
        SimpleChatView(conversationId: UUID())
            .environmentObject(ConversationManager.shared)
            .environmentObject(LocalModelManager.shared)
            .environmentObject(GGUFService.shared)
            .environmentObject(ContextTracker.shared)
    }
}
