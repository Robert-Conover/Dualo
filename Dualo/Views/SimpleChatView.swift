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
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var pendingAttachments: [ImageAttachment] = []
    @State private var capturedImage: ImageAttachment?
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
                showPhotoPicker: $showPhotoPicker,
                showCamera: $showCamera,
                pendingAttachments: $pendingAttachments,
                capturedImage: $capturedImage
            ))
            .background(Color.theme.chatBackground)
            .onAppear(perform: handleOnAppear)
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
    
    // MARK: - Message List

    private var messagesList: some View {
        MessageListView(
            viewModel: viewModel,
            currentProvider: currentProvider,
            showScrollToBottom: $showScrollToBottom,
            scrollToBottomAction: $performScrollToBottom,
            isInputFocused: $isInputFocused,
            onEditMessage: beginEditing,
            lastForgottenMessageId: lastForgottenMessageId
        )
    }

    private var lastForgottenMessageId: UUID? {
        guard currentProvider == .local, let memory = ggufService.memory,
              memory.conversationId == conversationId else { return nil }
        return memory.lastForgottenMessageId
    }

    private func beginEditing(_ messageId: UUID) {
        guard let text = viewModel.beginEditing(messageId) else { return }
        messageText = text
        isInputFocused = true
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
            showPhotoPicker: $showPhotoPicker,
            showCamera: $showCamera,
            isInputFocused: $isInputFocused,
            conversationId: conversationId,
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
        }
        // A bar rather than a stack row, so messages scroll on under the glass composer
        .safeAreaBar(edge: .bottom, spacing: 0) {
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
