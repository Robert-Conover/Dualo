//
//  HomeView.swift
//  Dualo
//
//  Created by Robert Conover on 12/7/25.
//

import SwiftUI
import OSLog

struct HomeView: View {
    @StateObject private var viewModel = ChatViewModel()
    @StateObject private var voiceInput = VoiceInputController()
    @EnvironmentObject var conversationManager: ConversationManager
    @EnvironmentObject var localModelManager: LocalModelManager
    @EnvironmentObject var ggufService: GGUFService
    
    @State private var messageText = ""
    @State private var showConversations = false
    @State private var showSettings = false
    @State private var selectedConversation: Conversation?
    @State private var pendingAttachments: [ImageAttachment] = []
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var capturedImage: ImageAttachment?
    @State private var showModelLoadError = false
    @State private var modelLoadErrorMessage = ""
    
    @FocusState private var isInputFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    // MARK: - Prompt Suggestions
    private let promptSuggestions = [
        ("lightbulb", "Explain a concept"),
        ("pencil.line", "Help me write"),
        ("ladybug", "Debug my code"),
        ("checklist", "Plan a project")
    ]
    
    private var currentModelName: String {
        if let config = viewModel.apiConfiguration {
            return modelDisplayName(for: config.model)
        }
        return "Select Model"
    }
    
    private var supportsImageAttachments: Bool {
        viewModel.apiConfiguration?.provider.supportsImageAttachments ?? true
    }

    private var currentProviderIcon: String {
        if let config = viewModel.apiConfiguration {
            return ModelUtilities.icon(for: config.provider)
        }
        return "cpu"
    }
    
    var body: some View {
        NavigationStack {
            welcomeContent
            // A bar, like the chat composer, so it rides on top of the keyboard as it moves
            .safeAreaBar(edge: .bottom, spacing: 0) {
                inputBar
            }
            .background {
                // The chat background with a still glow of the brand colors at the top; both
                // follow light and dark mode
                ZStack {
                    Color.theme.chatBackground
                    LinearGradient(
                        colors: [Color.theme.gradientEnd.opacity(0.28), Color.theme.gradientStart.opacity(0.12), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                }
                .ignoresSafeArea()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    settingsButton
                    conversationsButton
                }
                
                ToolbarItem(placement: .principal) {
                    modelSelector
                }
            }
            .gesture(
                DragGesture()
                    .onEnded { gesture in
                        if gesture.translation.width > 100 {
                            // Swipe right to open conversations
                            HapticFeedback.light()
                            showConversations = true
                        }
                    }
            )
            .navigationDestination(item: $selectedConversation) { conversation in
                SimpleChatView(conversationId: conversation.id)
            }
            .sheet(isPresented: $showConversations) {
                ConversationsSheetView(
                    selectedConversation: $selectedConversation,
                    isPresented: $showConversations
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .alert("Model Load Error", isPresented: $showModelLoadError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(modelLoadErrorMessage)
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
            .onChange(of: supportsImageAttachments) { _, supported in
                if !supported { pendingAttachments = [] }
            }
        }
    }
    
    // MARK: - Top Navigation Bar
    
    // Plain buttons: the toolbar draws their glass
    private var settingsButton: some View {
        Button("Settings", systemImage: "gearshape") {
            HapticFeedback.light()
            showSettings = true
        }
    }
    
    private var conversationsButton: some View {
        Button("Conversations", systemImage: "bubble.left") {
            HapticFeedback.light()
            showConversations = true
        }
    }
    
    // MARK: - Model Selector with Native Menu
    
    /// Whether model switching should be disabled (during streaming/generation to prevent crashes)
    private var isModelSwitchingDisabled: Bool {
        ggufService.isLoading || ggufService.isGenerating
    }
    
    @ViewBuilder
    private var modelSelector: some View {
        Menu {
            // Cloud providers
            ForEach([APIProvider.openai], id: \.self) { provider in
                Section(provider.displayName) {
                    ForEach(provider.availableModels, id: \.self) { model in
                        Button(action: {
                            updateModelWithProvider(model, provider: provider)
                        }) {
                            HStack {
                                Text(modelDisplayName(for: model))
                                if let config = viewModel.apiConfiguration,
                                   model == config.model && provider == config.provider {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .disabled(!isProviderConfigured(provider))
                    }
                }
            }
            
            // Local models section
            Section(StringConstants.UI.localModelsTitle) {
                if localModelManager.downloadedModels.isEmpty {
                    Text(StringConstants.UI.noModelsDownloaded)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(localModelManager.downloadedModels) { model in
                        Button(action: {
                            selectLocalModel(model)
                        }) {
                            HStack {
                                Text(model.displayName)
                                if let config = viewModel.apiConfiguration,
                                   config.provider == .local && config.model == model.id {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .disabled(!DeviceCapability.supportsLocalLLM)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: currentProviderIcon)
                    .font(.caption.weight(.medium))
                
                Text(currentModelName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
        }
        .disabled(isModelSwitchingDisabled || (viewModel.apiConfiguration == nil && localModelManager.downloadedModels.isEmpty))
    }
    
    // MARK: - Welcome Content
    
    /// Scrolls only when it doesn't fit, which takes the largest text sizes
    private var welcomeContent: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 24)

                    VStack(spacing: 8) {
                        Text("Welcome to Dualo")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .multilineTextAlignment(.center)

                        Text("Cloud & local AI, unified")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        if ggufService.isLoading {
                            ProgressView("Loading model…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer(minLength: 24)

                    promptSuggestionsView
                        .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                .contentShape(Rectangle())
                .onTapGesture {
                    isInputFocused = false
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
    }
    
    // MARK: - Prompt Suggestions

    /// Capsules, until accessibility text sizes wrap them onto more lines
    private var chipCornerRadius: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 20 : .infinity
    }
    
    private var promptSuggestionsView: some View {
        VStack(spacing: 12) {
            Text("Try asking")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            
            // One column at accessibility text sizes, so the suggestions aren't cut off
            GlassEffectContainer(spacing: 10) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                    ForEach(promptSuggestions, id: \.1) { symbol, text in
                        Button {
                            HapticFeedback.light()
                            messageText = text
                            isInputFocused = true
                        } label: {
                            Label(text, systemImage: symbol)
                                .font(.subheadline)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .contentShape(.rect(cornerRadius: chipCornerRadius))
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: chipCornerRadius))
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Input Bar with Glass Effect
    
    private var inputBar: some View {
        VStack(spacing: 0) {
            // Pending attachments preview
            if !pendingAttachments.isEmpty {
                PendingAttachmentPreview(attachments: pendingAttachments) { attachment in
                    pendingAttachments.removeAll { $0.id == attachment.id }
                }
            }
            
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    // + button for attachments (hidden for models that can't take images)
                    if supportsImageAttachments {
                        AttachmentMenu(showPhotoPicker: $showPhotoPicker, showCamera: $showCamera, color: .secondary)
                            .accessibilityIdentifier("homeAttachButton")
                    }
                    
                    TextField("Ask anything", text: $messageText, axis: .vertical)
                        .accessibilityIdentifier("homeComposer")
                        .font(.body)
                        .lineLimit(1...6)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .tint(.accentColor)
                        .focused($isInputFocused)
                        .onSubmit {
                            if canSendMessage {
                                sendMessage()
                            }
                        }
                    
                    VoiceInputButton(
                        voiceInput: voiceInput,
                        text: $messageText,
                        isInputFocused: $isInputFocused,
                        identifierPrefix: "home"
                    )

                    // Send button with bounce animation
                    Button(action: {
                        HapticFeedback.medium()
                        sendMessage()
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title.weight(.medium))
                            .foregroundStyle(canSendMessage ? .blue : .secondary.opacity(0.5))
                            .scaleEffect(canSendMessage ? 1.0 : 0.8)
                    }
                    .disabled(!canSendMessage)
                    .accessibilityLabel("Send")
                    .accessibilityIdentifier("homeSendButton")
                    .animation(.spring(response: 0.35, dampingFraction: 0.5, blendDuration: 0), value: canSendMessage)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .glassEffect(in: .capsule)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
    
    // MARK: - Helpers
    
    private var canSendMessage: Bool {
        let hasText = !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !pendingAttachments.isEmpty
        let hasContent = hasText || hasAttachments
        let hasConfig = viewModel.apiConfiguration != nil
        
        // For local models, also check if model is loaded and not currently loading
        if let config = viewModel.apiConfiguration, config.provider == .local {
            let modelReady = ggufService.isModelLoaded && !ggufService.isLoading
            return hasContent && hasConfig && modelReady
        }
        
        return hasContent && hasConfig
    }
    
    private func sendMessage() {
        // Send what's been heard so far; later results mustn't refill the cleared composer
        voiceInput.cancel()
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty || !pendingAttachments.isEmpty else { return }
        
        // Create new conversation
        let conversation = conversationManager.createNewConversation()
        
        // Store the pending message + attachments for SimpleChatView to pick up
        conversationManager.pendingChatData = PendingChatData(
            message: trimmedMessage,
            attachments: pendingAttachments
        )
        
        // Clear input and navigate to chat
        messageText = ""
        pendingAttachments = []
        isInputFocused = false
        selectedConversation = conversation
    }
    
    private func updateModelWithProvider(_ newModel: String, provider: APIProvider) {
        // Safety guard: prevent model switching during generation
        guard !isModelSwitchingDisabled else {
            Logger.ui.debug("HomeView: Model switch blocked - loading/generating in progress")
            return
        }
        
        // Unload local model when switching to API provider
        if provider != .local && GGUFService.shared.isModelLoaded {
            GGUFService.shared.unloadModel()
        }
        
        // Get the API key for the provider
        do {
            if let configs = try KeychainService.shared.loadProviderConfigurations() {
                if let existingConfig = configs.configuration(for: provider) {
                    let newConfig = APIConfiguration(
                        provider: provider,
                        apiKey: existingConfig.apiKey,
                        model: newModel
                    )
                    viewModel.apiConfiguration = newConfig
                    
                    // Save to keychain
                    var updatedConfigs = configs
                    updatedConfigs.setConfiguration(newConfig)
                    try KeychainService.shared.saveProviderConfigurations(updatedConfigs)
                }
            }
        } catch {
            Logger.config.error("Failed to update model selection: \(String(describing: error), privacy: .public)")
        }
    }
    
    private func selectLocalModel(_ model: LocalModel) {
        // Safety guard: prevent model switching during generation
        guard !isModelSwitchingDisabled else {
            Logger.ui.debug("HomeView: Local model switch blocked - loading/generating in progress")
            return
        }
        
        // Set the selected model in LocalModelManager
        localModelManager.selectedModelId = model.id
        
        // Create a local configuration
        let localConfig = APIConfiguration(
            provider: .local,
            apiKey: "", // Local models don't need an API key
            model: model.id
        )
        viewModel.apiConfiguration = localConfig
        
        // Save to keychain
        do {
            var configs = try KeychainService.shared.loadProviderConfigurations() ?? ProviderConfigurations()
            configs.setConfiguration(localConfig)
            try KeychainService.shared.saveProviderConfigurations(configs)
        } catch {
            Logger.config.error("Failed to save local model selection: \(String(describing: error), privacy: .public)")
        }
        
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
    
    private func isProviderConfigured(_ provider: APIProvider) -> Bool {
        ModelUtilities.isConfigured(provider, downloadedModels: localModelManager.downloadedModels)
    }
    
    private func modelDisplayName(for model: String) -> String {
        ModelUtilities.displayName(for: model, localModels: localModelManager.availableModels)
    }
}

#Preview {
    HomeView()
        .environmentObject(ConversationManager.shared)
        .environmentObject(LocalModelManager.shared)
        .environmentObject(GGUFService.shared)
        .environmentObject(ContextTracker.shared)
}
