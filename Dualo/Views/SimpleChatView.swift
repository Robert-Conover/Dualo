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
    private var currentModel: String { conversation?.model ?? "" }
    private var currentProvider: APIProvider { conversation?.provider ?? .openai }
    @StateObject private var viewModel = ChatViewModel()
    @EnvironmentObject var conversationManager: ConversationManager
    @EnvironmentObject var ggufService: GGUFService
    @EnvironmentObject var contextTracker: ContextTracker
    @State private var messageText = ""
    @State private var showScrollToBottom = false
    @FocusState private var isInputFocused: Bool
    @State private var showRenameAlert = false
    @State private var newTitle = ""
    @State private var showExportError = false
    @State private var exportErrorMessage = ""

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
            .onChange(of: viewModel.isStreaming, handleStreamingChange)
            .onChange(of: currentProvider) { _, provider in
                if !provider.supportsImageAttachments { pendingAttachments = [] }
            }
    }
    
    // MARK: - Lifecycle Event Handlers (extracted to reduce body complexity)
    
    private func handleOnAppear() {
        guard let conversation = conversation else {
            Logger.ui.warning("SimpleChatView onAppear: conversation not found for id \(conversationId, privacy: .public)")
            return
        }
        Logger.ui.debug("SimpleChatView onAppear: conversation.id = \(conversation.id, privacy: .public), messages count = \(conversation.messages.count)")
        // Refresh configuration to pick up any changes from settings
        viewModel.refreshConfiguration()
        // Ensure this conversation is selected in the manager
        conversationManager.selectConversation(conversation)
        viewModel.loadConversation(conversation)
        
        // Check for pending initial message + attachments from HomeView
        if let pendingData = conversationManager.pendingChatData {
            Logger.ui.debug("Found pending message: \(pendingData.message), attachments: \(pendingData.attachments.count)")
            conversationManager.pendingChatData = nil
            
            Task {
                await viewModel.sendWhenModelReady(pendingData.message, attachments: pendingData.attachments)
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
                isDisabled: !viewModel.canSwitchModel,
                onSelectCloudModel: { model, provider in switchModel(to: model, provider: provider) },
                onSelectLocalModel: { model in switchModel(to: model.id, provider: .local) }
            )
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            ChatOptionsMenu(
                isDisabled: viewModel.messages.isEmpty,
                onRename: {
                    newTitle = conversation?.title ?? ""
                    showRenameAlert = true
                },
                onExport: export
            )
        }
    }

    private func sendMessage() {
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Allow sending with just attachments (no text required)
        guard !trimmedMessage.isEmpty || !pendingAttachments.isEmpty else { return }

        // Transfer attachments to viewModel
        viewModel.pendingAttachments = pendingAttachments
        pendingAttachments = []

        Task {
            await viewModel.sendMessage(trimmedMessage)
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
    }
    
    private func switchModel(to modelId: String, provider: APIProvider) {
        Task {
            do {
                try await viewModel.switchModel(to: modelId, provider: provider)
            } catch {
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
