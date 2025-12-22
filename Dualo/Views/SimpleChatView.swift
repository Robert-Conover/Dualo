//
//  SimpleChatView.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI
import UIKit

// MARK: - Scroll Offset Tracking

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct SimpleChatView: View {
    let conversation: Conversation
    @StateObject private var viewModel = ChatViewModel()
    @ObservedObject private var conversationManager = ConversationManager.shared
    @ObservedObject private var localModelManager = LocalModelManager.shared
    @ObservedObject private var ggufService = GGUFService.shared
    @ObservedObject private var contextTracker = ContextTracker.shared
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
    @State private var currentProvider: APIProvider = .anthropic
    @State private var isInitialLoad = true

    // Image picker state
    @State private var showAttachmentOptions = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var pendingAttachments: [ImageAttachment] = []
    @State private var capturedImage: ImageAttachment?
    @State private var showGenerationStats = false
    @State private var showModelLoadError = false
    @State private var modelLoadErrorMessage = ""
    
    // Scroll tracking state
    @State private var scrollViewHeight: CGFloat = 0
    
    // Quick prompts for empty state
    private let quickPrompts = [
        ("💡", "Explain a concept to me"),
        ("✍️", "Help me write something"),
        ("🐛", "Debug this code")
    ]
    
    var body: some View {
        mainContentView
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .modifier(AlertsModifier(
                viewModel: viewModel,
                showRenameAlert: $showRenameAlert,
                newTitle: $newTitle,
                showExportError: $showExportError,
                exportErrorMessage: exportErrorMessage,
                showModelLoadError: $showModelLoadError,
                modelLoadErrorMessage: modelLoadErrorMessage,
                renameChat: renameChat
            ))
            .modifier(AttachmentModifier(
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
        print("SimpleChatView onAppear: conversation.id = \(conversation.id), messages count = \(conversation.messages.count)")
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
            print("Found pending message: \(pendingData.message), attachments: \(pendingData.attachments.count)")
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
        if conversation.provider == .local {
            print("SimpleChatView: Waiting for local model to load...")
            // Wait for model to be loaded (with timeout)
            var waitAttempts = 0
            let maxWaitAttempts = 100 // 10 seconds max (100 * 100ms)
            while !ggufService.isModelLoaded && ggufService.isLoading && waitAttempts < maxWaitAttempts {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                waitAttempts += 1
            }
            
            if !ggufService.isModelLoaded {
                print("SimpleChatView: Local model failed to load, cannot send pending message")
                viewModel.errorMessage = "Local model failed to load. Please try again."
                viewModel.showError = true
                return
            }
            print("SimpleChatView: Local model loaded, sending pending message")
        }
        
        await viewModel.sendMessage(message, useStreaming: true)
    }
    
    private func handleConversationsChange(_ oldValue: [Conversation], _ newValue: [Conversation]) {
        // Update local state when the conversation changes
        if let updatedConversation = newValue.first(where: { $0.id == conversation.id }) {
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
            
            if isInitialLoad && !updatedConversation.messages.isEmpty {
                isInitialLoad = false
            }
        }
    }
    
    private func handleStreamingChange(_ oldValue: Bool, _ newValue: Bool) {
        // Streaming state changed - no need to manually persist since ChatViewModel handles it
        if oldValue && !newValue {
            #if DEBUG
            print("SimpleChatView: Streaming completed")
            #endif
            
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
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Animated conversation icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.1), .purple.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue.opacity(0.7), .purple.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.pulse.wholeSymbol, options: .speed(0.5).repeat(.continuous))
            }
            
            VStack(spacing: 8) {
                Text("Start a Conversation")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                
                Text("Ask me anything — I'm here to help!")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                
                // Loading indicator for local model
                if ggufService.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .secondary))
                            .scaleEffect(0.8)
                        
                        Text("Loading model...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            
            // Quick prompt buttons
            VStack(spacing: 10) {
                ForEach(quickPrompts, id: \.1) { emoji, text in
                    Button(action: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        messageText = text
                        isInputFocused = true
                    }) {
                        HStack(spacing: 10) {
                            Text(emoji)
                                .font(.system(size: 18))
                            Text(text)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(.secondarySystemGroupedBackground))
                                .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
            
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.theme.chatBackground)
    }
    
    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                        let isCurrentlyStreaming = viewModel.isStreaming && message.id == viewModel.messages.last?.id && message.role == Message.Role.assistant
                        MessageBubbleView(
                            message: message,
                            isStreaming: isCurrentlyStreaming,
                            provider: currentProvider,
                            streamingContent: isCurrentlyStreaming ? viewModel.streamingMessageContent : nil,
                            onRetry: message.isFailed ? {
                                Task {
                                    await viewModel.retryMessage(message.id)
                                }
                            } : nil
                        )
                        .id(message.id)
                        .transition(.asymmetric(
                            insertion: .push(from: .bottom)
                                .combined(with: .scale(scale: 0.9, anchor: .bottom))
                                .combined(with: .opacity)
                                .animation(.spring(response: 0.35, dampingFraction: 0.85).delay(Double(index) * 0.03)),
                            removal: .scale(scale: 0.8)
                                .combined(with: .opacity)
                                .animation(.spring(response: 0.25, dampingFraction: 0.9))
                        ))
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: message.content)
                    }
                    
                    if viewModel.isLoading && !viewModel.isStreaming {
                        HStack(spacing: 12) {
                            HStack(spacing: 10) {
                                // Animated dots
                                HStack(spacing: 4) {
                                    ForEach(0..<3) { index in
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [.blue.opacity(0.7), .purple.opacity(0.7)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 8, height: 8)
                                            .scaleEffect(viewModel.isLoading ? 1.0 : 0.3)
                                            .opacity(viewModel.isLoading ? 1.0 : 0.3)
                                            .animation(
                                                .spring(response: 0.5, dampingFraction: 0.5)
                                                .repeatForever()
                                                .delay(Double(index) * 0.12),
                                                value: viewModel.isLoading
                                            )
                                    }
                                }
                                
                                Text("Thinking...")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .glassEffect(in: .capsule)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .id("loading")
                        .transition(.asymmetric(
                            insertion: .push(from: .bottom).combined(with: .opacity),
                            removal: .scale(scale: 0.8).combined(with: .opacity)
                        ))
                    }
                    
                    // Bottom anchor for scroll detection
                    GeometryReader { geometry in
                        Color.clear
                            .preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geometry.frame(in: .named("scrollView")).maxY
                            )
                    }
                    .frame(height: 1)
                    .id("bottom")
                }
                .padding(.vertical, 16)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.messages.count)
            }
            .coordinateSpace(name: "scrollView")
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            scrollViewHeight = geometry.size.height
                        }
                        .onChange(of: geometry.size.height) { _, newValue in
                            scrollViewHeight = newValue
                        }
                }
            )
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { bottomY in
                // bottomY is the Y position of the bottom of content relative to scroll view
                // When at bottom: bottomY ≈ scrollViewHeight
                // When scrolled up: bottomY > scrollViewHeight
                let distanceFromBottom = bottomY - scrollViewHeight
                updateScrollToBottomVisibility(distanceFromBottom: distanceFromBottom)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChangeCompat(of: viewModel.messages.count) { _ in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    if viewModel.isLoading && !viewModel.isStreaming {
                        proxy.scrollTo("loading", anchor: .bottom)
                        showScrollToBottom = false
                    } else if let lastMessage = viewModel.messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        showScrollToBottom = false
                    }
                }
            }
            .onChange(of: viewModel.streamingMessageContent) { oldValue, newValue in
                // Auto-scroll while streaming - only if content is growing
                if viewModel.isStreaming && newValue.count > oldValue.count {
                    if let lastMessage = viewModel.messages.last {
                        // Use minimal animation to keep up with fast token generation
                        withAnimation(.linear(duration: 0.1)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isInputFocused = false
            }
            .background(
                // Store proxy reference for scroll to bottom button
                Color.clear.onAppear {
                    DispatchQueue.main.async {
                        // Store the proxy for later use
                        self.performScrollToBottom = {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                if viewModel.isLoading && !viewModel.isStreaming {
                                    proxy.scrollTo("loading", anchor: .bottom)
                                } else if let lastMessage = viewModel.messages.last {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                } else {
                                    proxy.scrollTo("bottom", anchor: .bottom)
                                }
                                showScrollToBottom = false
                            }
                        }
                    }
                }
            )
        }
        .background(Color.theme.chatBackground)
    }
    
    private func updateScrollToBottomVisibility(distanceFromBottom: CGFloat) {
        // Don't update while streaming - it interferes with auto-scroll
        guard !viewModel.isStreaming else { return }
        guard !viewModel.messages.isEmpty else { return }
        
        // Show button when user has scrolled up more than threshold from bottom
        let threshold: CGFloat = 100
        let shouldShow = distanceFromBottom > threshold
        
        if shouldShow != showScrollToBottom {
            withAnimation(.easeInOut(duration: 0.3)) {
                showScrollToBottom = shouldShow
            }
        }
    }
    
    @State private var performScrollToBottom: (() -> Void)?
    
    private func scrollToBottom() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        performScrollToBottom?()
    }
    
    private var inputBar: some View {
        VStack(spacing: 0) {
            // Live streaming stats (for local models while generating)
            if viewModel.isStreaming && currentProvider == .local && ggufService.isGenerating {
                HStack {
                    LocalModelStreamingIndicator(
                        tokenCount: ggufService.currentTokenCount,
                        startTime: ggufService.generationStartTime
                    )
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemGroupedBackground).opacity(0.95))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            // Post-generation stats banner (for local models after completion)
            else if showGenerationStats, let stats = ggufService.lastGenerationStats, currentProvider == .local {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                    
                    Text("\(stats.tokenCount) tokens")
                        .font(.system(size: 12, weight: .medium))
                    
                    Text("•")
                        .foregroundStyle(Color(.tertiaryLabel))
                    
                    Text(stats.formattedDuration)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    
                    Text("•")
                        .foregroundStyle(Color(.tertiaryLabel))
                    
                    Text(stats.formattedSpeed)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.green)
                    
                    Spacer()
                    
                    // Context usage indicator (compact, in stats banner)
                    ContextUsageIndicator(usageInfo: contextTracker.usageInfo, style: .compact)
                    
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showGenerationStats = false
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            // Context usage indicator (when not streaming/showing stats but has messages)
            else if !viewModel.messages.isEmpty && contextTracker.contextLimit > 0 {
                ContextUsageIndicator(usageInfo: contextTracker.usageInfo, style: .full)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .transition(.opacity)
            }
            
            // Pending attachments preview
            if !pendingAttachments.isEmpty {
                PendingAttachmentPreview(attachments: pendingAttachments) { attachment in
                    pendingAttachments.removeAll { $0.id == attachment.id }
                }
            }

            // Modern pill-shaped input container
            HStack(spacing: 12) {
                // Text input container with embedded send button
                HStack(spacing: 8) {
                    // + button for attachments - NOW FUNCTIONAL
                    Button(action: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        showAttachmentOptions = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.blue)
                            .frame(width: 24, height: 24)
                    }
                    .disabled(viewModel.isLoading || viewModel.isStreaming)

                    TextField("Message", text: $messageText, axis: .vertical)
                        .font(.body)
                        .lineLimit(1...6)
                        .textFieldStyle(.plain)
                        .focused($isInputFocused)
                        .disabled(viewModel.isLoading || viewModel.isStreaming)
                        .onSubmit {
                            if canSendMessage && !viewModel.isStreaming {
                                sendMessage()
                            }
                        }

                    // Embedded send button
                    Button(action: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()

                        if viewModel.isStreaming {
                            viewModel.stopStreaming()
                        } else {
                            sendMessage()
                        }
                    }) {
                        Image(systemName: viewModel.isStreaming ? "stop.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(
                                viewModel.isStreaming ? .red :
                                canSendMessage ? .blue : .secondary
                            )
                            .scaleEffect(canSendMessage || viewModel.isStreaming ? 1.0 : 0.8)
                            .rotationEffect(.degrees(viewModel.isStreaming ? 90 : 0))
                    }
                    .disabled(!canSendMessage && !viewModel.isStreaming)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: canSendMessage)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: viewModel.isStreaming)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect(in: .rect(cornerRadius: 22))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color.theme.chatBackground.opacity(0.95))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 0)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showGenerationStats)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.isStreaming)
    }

    private var canSendMessage: Bool {
        let hasText = !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !pendingAttachments.isEmpty
        let hasContent = hasText || hasAttachments
        let notBusy = !viewModel.isLoading && !viewModel.isStreaming
        
        // For local models, also check if model is loaded and not currently loading
        if currentProvider == .local {
            let modelReady = ggufService.isModelLoaded && !ggufService.isLoading
            return hasContent && notBusy && modelReady
        }
        
        return hasContent && notBusy
    }
    
    // MARK: - Main Content View (extracted to reduce body complexity)
    
    @ViewBuilder
    private var mainContentView: some View {
        VStack(spacing: 0) {
            if viewModel.messages.isEmpty {
                emptyStateView
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isInputFocused = false
                    }
            } else {
                ZStack(alignment: .bottomTrailing) {
                    messagesList
                    scrollToBottomButton
                }
            }
            
            inputBar
        }
    }
    
    @ViewBuilder
    private var scrollToBottomButton: some View {
        if showScrollToBottom && !viewModel.messages.isEmpty && !viewModel.isStreaming {
            Button(action: scrollToBottom) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: Circle()
                    )
                    .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 4)
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
            .padding(.trailing, 16)
            .padding(.bottom, 8)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.7, anchor: .bottomTrailing)
                    .combined(with: .opacity)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7)),
                removal: .scale(scale: 0.5, anchor: .bottomTrailing)
                    .combined(with: .opacity)
                    .animation(.spring(response: 0.25, dampingFraction: 0.9))
            ))
            .scaleEffect(showScrollToBottom ? 1.0 : 0.9)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showScrollToBottom)
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            modelSelectorToolbarItem
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            optionsMenuToolbarItem
        }
    }
    
    // MARK: - Extracted Toolbar Views (fixes compiler type-check complexity)
    
    /// Whether model switching should be disabled (during streaming/loading to prevent crashes)
    private var isModelSwitchingDisabled: Bool {
        viewModel.isStreaming || viewModel.isLoading || ggufService.isLoading || ggufService.isGenerating
    }
    
    @ViewBuilder
    private var modelSelectorToolbarItem: some View {
        Menu {
            cloudProvidersMenuSection
            localModelsMenuSection
        } label: {
            modelSelectorLabel
        }
        .disabled(isModelSwitchingDisabled)
        .opacity(isModelSwitchingDisabled ? 0.5 : 1.0)
    }
    
    @ViewBuilder
    private var cloudProvidersMenuSection: some View {
        ForEach([APIProvider.anthropic, APIProvider.openai], id: \.self) { provider in
            Section(provider.displayName) {
                ForEach(provider.availableModels, id: \.self) { model in
                    Button(action: {
                        changeConversationModel(to: model, provider: provider)
                    }) {
                        HStack {
                            Text(modelDisplayName(for: model))
                            if model == currentModel && provider == currentProvider {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(!isProviderConfigured(provider))
                }
            }
        }
    }
    
    @ViewBuilder
    private var localModelsMenuSection: some View {
        Section(StringConstants.UI.localModelsTitle) {
            if localModelManager.downloadedModels.isEmpty {
                Text(StringConstants.UI.noModelsDownloaded)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(localModelManager.downloadedModels) { model in
                    Button(action: {
                        changeToLocalModel(model)
                    }) {
                        HStack {
                            Text(model.displayName)
                            if currentProvider == .local && currentModel == model.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(!DeviceCapability.supportsLocalLLM)
                }
            }
        }
    }
    
    private var modelSelectorLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: providerIcon(for: currentProvider))
                .font(.system(size: 12, weight: .medium))
            
            Text(modelDisplayName(for: currentModel))
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
            
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(in: .capsule)
    }
    
    @ViewBuilder
    private var optionsMenuToolbarItem: some View {
        Menu {
            Button(action: {
                newTitle = currentTitle.isEmpty ? conversation.title : currentTitle
                showRenameAlert = true
            }) {
                Label("Rename Chat", systemImage: "pencil")
            }
            
            Divider()
            
            Button(action: {
                exportAsPDF()
            }) {
                Label("Export as PDF", systemImage: "doc.richtext")
            }
            
            Button(action: {
                exportAsMarkdown()
            }) {
                Label("Export as Markdown", systemImage: "doc.text")
            }
            
            Button(action: {
                exportAsText()
            }) {
                Label("Export as Text", systemImage: "doc.plaintext")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 20, height: 20)
                .padding(10)
                .glassEffect(in: .circle)
                .accessibilityLabel("Options")
        }
        .disabled(viewModel.messages.isEmpty)
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
        #if DEBUG
        print("SimpleChatView: Renaming chat from '\(conversation.title)' to '\(newTitle)'")
        #endif
        
        // IMPORTANT: Get the CURRENT conversation from conversationManager, not the stale `conversation` prop
        // The `conversation` prop is a snapshot from when the view was created and doesn't include new messages
        guard var updatedConversation = conversationManager.conversations.first(where: { $0.id == conversation.id }) else {
            print("SimpleChatView: Could not find conversation to rename")
            return
        }
        updatedConversation.title = newTitle
        updatedConversation.updatedAt = Date()
        conversationManager.updateConversation(updatedConversation, moveToTop: true) // Title changes should move to top
        currentTitle = newTitle // Update the local state to reflect immediately
    }
    
    private func changeConversationModel(to newModel: String, provider: APIProvider) {
        // Safety guard: prevent model switching during streaming/generation
        guard !isModelSwitchingDisabled else {
            print("SimpleChatView: Model switch blocked - streaming/loading in progress")
            return
        }
        
        // Unload local model when switching to API provider
        if provider != .local && GGUFService.shared.isModelLoaded {
            GGUFService.shared.unloadModel()
        }
        
        // IMPORTANT: Get the CURRENT conversation from conversationManager, not the stale `conversation` prop
        // The `conversation` prop is a snapshot from when the view was created and doesn't include new messages
        guard var updatedConversation = conversationManager.conversations.first(where: { $0.id == conversation.id }) else {
            print("SimpleChatView: Could not find conversation to update model")
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
                var providerConfig: APIConfiguration?
                switch provider {
                case .anthropic:
                    providerConfig = configs.anthropic
                case .openai:
                    providerConfig = configs.openai
                case .local:
                    providerConfig = configs.local
                }
                
                if let existingConfig = providerConfig {
                    let newConfig = APIConfiguration(
                        provider: provider,
                        apiKey: existingConfig.apiKey,
                        model: newModel
                    )
                    viewModel.apiConfiguration = newConfig
                }
            }
        } catch {
            print("Failed to load provider configuration for \(provider): \(error)")
        }
    }
    
    private func changeToLocalModel(_ model: LocalModel) {
        // Safety guard: prevent model switching during streaming/generation
        guard !isModelSwitchingDisabled else {
            print("SimpleChatView: Local model switch blocked - streaming/loading in progress")
            return
        }
        
        // IMPORTANT: Get the CURRENT conversation from conversationManager, not the stale `conversation` prop
        // The `conversation` prop is a snapshot from when the view was created and doesn't include new messages
        guard var updatedConversation = conversationManager.conversations.first(where: { $0.id == conversation.id }) else {
            print("SimpleChatView: Could not find conversation to update to local model")
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
                print("Failed to load local model: \(error)")
                modelLoadErrorMessage = error.localizedDescription
                showModelLoadError = true
            }
        }
    }
    
    private func isProviderConfigured(_ provider: APIProvider) -> Bool {
        ModelUtilities.isConfigured(provider, downloadedModels: localModelManager.downloadedModels)
    }
    
    private func providerIcon(for provider: APIProvider) -> String {
        ModelUtilities.icon(for: provider)
    }
    
    private func modelDisplayName(for model: String) -> String {
        ModelUtilities.displayName(for: model, localModels: localModelManager.availableModels)
    }
    
    private func exportAsPDF() {
        Task {
            do {
                let exportService = ChatExportService()
                let pdfData = try await exportService.makePDF(for: conversation)
                await MainActor.run {
                    shareExport(data: pdfData, filename: "\(conversation.title).pdf")
                }
            } catch {
                await MainActor.run {
                    exportErrorMessage = "Failed to export PDF: \(error.localizedDescription)"
                    showExportError = true
                }
            }
        }
    }
    
    private func exportAsMarkdown() {
        let exportService = ChatExportService()
        let markdownData = exportService.makeMarkdown(for: conversation)
        shareExport(data: markdownData, filename: "\(conversation.title).md")
    }
    
    private func exportAsText() {
        let exportService = ChatExportService()
        let textData = exportService.makeText(for: conversation)
        shareExport(data: textData, filename: "\(conversation.title).txt")
    }
    
    @MainActor
    private func shareExport(data: Data, filename: String) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        do {
            try data.write(to: tempURL)
            
            let shareSheet = UIActivityViewController(
                activityItems: [tempURL],
                applicationActivities: nil
            )
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootViewController = window.rootViewController {
                
                var presentingVC = rootViewController
                while let presented = presentingVC.presentedViewController {
                    presentingVC = presented
                }
                
                if let popover = shareSheet.popoverPresentationController {
                    popover.sourceView = window
                    popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                
                presentingVC.present(shareSheet, animated: true)
            }
        } catch {
            exportErrorMessage = "Failed to save file: \(error.localizedDescription)"
            showExportError = true
        }
    }
}

// MARK: - Local Model Streaming Indicator

struct LocalModelStreamingIndicator: View {
    let tokenCount: Int
    let startTime: Date?
    
    @State private var isPulsing = false
    
    private var elapsedTime: TimeInterval {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }
    
    private var tokensPerSecond: Double {
        guard elapsedTime > 0.5 else { return 0 } // Wait a bit before showing speed
        return Double(tokenCount) / elapsedTime
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // Pulsing indicator - uses its own state, not tokenCount
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
                .scaleEffect(isPulsing ? 1.2 : 0.8)
                .opacity(isPulsing ? 1.0 : 0.6)
            
            Text("\(tokenCount)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .monospacedDigit()
            
            Text("tokens")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            
            if tokensPerSecond > 0 {
                Text("•")
                    .foregroundStyle(Color(.tertiaryLabel))
                
                Text(String(format: "%.1f tok/s", tokensPerSecond))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.green)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    Capsule()
                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                )
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Context Usage Indicator

struct ContextUsageIndicator: View {
    let usageInfo: ContextUsageInfo
    var style: Style = .full
    
    enum Style {
        case full       // Shows full info with progress bar
        case compact    // Just percentage badge
    }
    
    private var progressColor: Color {
        if usageInfo.isAtLimit {
            return .red
        } else if usageInfo.isNearLimit {
            return .orange
        } else {
            return .blue
        }
    }
    
    private var statusIcon: String {
        if usageInfo.isAtLimit {
            return "exclamationmark.triangle.fill"
        } else if usageInfo.isNearLimit {
            return "exclamationmark.circle.fill"
        } else {
            return "circle.dotted"
        }
    }
    
    var body: some View {
        switch style {
        case .full:
            fullIndicator
        case .compact:
            compactIndicator
        }
    }
    
    private var fullIndicator: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: statusIcon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(progressColor)
            
            // Progress bar with text
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Context")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text(usageInfo.formattedUsage)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                }
                
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        Capsule()
                            .fill(Color(.systemGray5))
                            .frame(height: 4)
                        
                        // Fill
                        Capsule()
                            .fill(progressColor)
                            .frame(width: max(0, geometry.size.width * usageInfo.usagePercentage / 100), height: 4)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: usageInfo.usagePercentage)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: 160)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    Capsule()
                        .stroke(progressColor.opacity(usageInfo.isNearLimit ? 0.3 : 0.1), lineWidth: 1)
                )
        )
    }
    
    private var compactIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.system(size: 10, weight: .medium))
            
            Text(usageInfo.compactUsage)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(progressColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(progressColor.opacity(0.1))
        )
    }
}

// MARK: - Alerts View Modifier (extracted to reduce body complexity)

private struct AlertsModifier: ViewModifier {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var showRenameAlert: Bool
    @Binding var newTitle: String
    @Binding var showExportError: Bool
    let exportErrorMessage: String
    @Binding var showModelLoadError: Bool
    let modelLoadErrorMessage: String
    let renameChat: (String) -> Void
    
    func body(content: Content) -> some View {
        content
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") {
                    viewModel.showError = false
                    let notificationFeedback = UINotificationFeedbackGenerator()
                    notificationFeedback.notificationOccurred(.error)
                }
            } message: {
                Text(viewModel.errorMessage)
            }
            .alert("Rename Chat", isPresented: $showRenameAlert) {
                TextField("Chat Title", text: $newTitle)
                    .textInputAutocapitalization(.words)
                Button("Cancel", role: .cancel) { }
                Button("Rename") {
                    let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedTitle.isEmpty {
                        renameChat(trimmedTitle)
                    }
                }
            } message: {
                Text("Enter a new title for this chat")
            }
            .alert("Export Error", isPresented: $showExportError) {
                Button("OK") { }
            } message: {
                Text(exportErrorMessage)
            }
            .alert("Model Load Error", isPresented: $showModelLoadError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(modelLoadErrorMessage)
            }
    }
}

// MARK: - Attachment View Modifier (extracted to reduce body complexity)

private struct AttachmentModifier: ViewModifier {
    @Binding var showAttachmentOptions: Bool
    @Binding var showPhotoPicker: Bool
    @Binding var showCamera: Bool
    @Binding var pendingAttachments: [ImageAttachment]
    @Binding var capturedImage: ImageAttachment?
    
    func body(content: Content) -> some View {
        content
            .confirmationDialog("Add Attachment", isPresented: $showAttachmentOptions, titleVisibility: .visible) {
                Button("Photo Library") {
                    showPhotoPicker = true
                }
                Button("Take Photo") {
                    showCamera = true
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showPhotoPicker) {
                PhotoPicker(selectedImages: $pendingAttachments, selectionLimit: 4) {
                    showPhotoPicker = false
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker(capturedImage: $capturedImage) {
                    showCamera = false
                }
            }
            .onChange(of: capturedImage) { oldValue, newValue in
                if let newImage = newValue {
                    pendingAttachments.append(newImage)
                    capturedImage = nil
                }
            }
    }
}

#Preview {
    NavigationStack {
        SimpleChatView(conversation: Conversation(title: "Sample Chat"))
    }
}