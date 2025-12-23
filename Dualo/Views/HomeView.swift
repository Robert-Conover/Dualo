//
//  HomeView.swift
//  Dualo
//
//  Created by Robert Conover on 12/7/25.
//

import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = ChatViewModel()
    @ObservedObject private var conversationManager = ConversationManager.shared
    @ObservedObject private var localModelManager = LocalModelManager.shared
    @ObservedObject private var ggufService = GGUFService.shared
    
    @State private var messageText = ""
    @State private var showConversations = false
    @State private var showSettings = false
    @State private var selectedConversation: Conversation?
    @State private var pendingAttachments: [ImageAttachment] = []
    @State private var showAttachmentOptions = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var capturedImage: ImageAttachment?
    @State private var animateGradient = false
    @State private var showModelLoadError = false
    @State private var modelLoadErrorMessage = ""
    
    @FocusState private var isInputFocused: Bool
    
    // MARK: - Prompt Suggestions
    private let promptSuggestions = [
        ("💡", "Explain a concept"),
        ("✍️", "Help me write"),
        ("🐛", "Debug my code"),
        ("🎯", "Plan a project")
    ]
    
    private var currentModelName: String {
        if let config = viewModel.apiConfiguration {
            return modelDisplayName(for: config.model)
        }
        return "Select Model"
    }
    
    private var currentProviderIcon: String {
        if let config = viewModel.apiConfiguration {
            return ModelUtilities.icon(for: config.provider)
        }
        return "cpu"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Welcome content
                welcomeContent
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                inputBar
                    .keyboardResponsive()
            }
            // Deterministic keyboard handling: ignore SwiftUI’s keyboard safe area and drive the composer
            // position ourselves via `keyboardResponsive()`.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .background {
                // Animated gradient background (background ignores safe areas, content does not)
                LinearGradient(
                    colors: animateGradient ?
                        [Color.theme.gradientStart.opacity(0.7), Color.theme.gradientEnd.opacity(0.5), Color.theme.gradientDark] :
                        [Color.theme.gradientEnd.opacity(0.6), Color.theme.gradientStart.opacity(0.4), Color.theme.gradientDark],
                    startPoint: animateGradient ? .topLeading : .topTrailing,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                    animateGradient = true
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    settingsButton
                    conversationsButton
                }
                
                ToolbarItem(placement: .principal) {
                    modelSelector
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    newChatButton
                }
            }
            .gesture(
                DragGesture()
                    .onEnded { gesture in
                        if gesture.translation.width > 100 {
                            // Swipe right to open conversations
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            showConversations = true
                        }
                    }
            )
            .navigationDestination(item: $selectedConversation) { conversation in
                SimpleChatView(conversation: conversation)
            }
            .sheet(isPresented: $showConversations) {
                ConversationsSheetView(
                    selectedConversation: $selectedConversation,
                    isPresented: $showConversations
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.theme.sheetBackground)
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
    
    // MARK: - Top Navigation Bar
    
    private var settingsButton: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            showSettings = true
        }) {
            Image(systemName: "gearshape")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 20, height: 20)
                .padding(10)
                .glassEffect(in: .circle)
                .accessibilityLabel("Settings")
        }
        .buttonStyle(.plain)
    }
    
    private var conversationsButton: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            showConversations = true
        }) {
            Image(systemName: "bubble.left")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 20, height: 20)
                .padding(10)
                .glassEffect(in: .circle)
                .accessibilityLabel("Conversations")
        }
        .buttonStyle(.plain)
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
            ForEach([APIProvider.anthropic, APIProvider.openai], id: \.self) { provider in
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
                    .font(.system(size: 12, weight: .medium))
                
                Text(currentModelName)
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
        .disabled(isModelSwitchingDisabled || (viewModel.apiConfiguration == nil && localModelManager.downloadedModels.isEmpty))
        .opacity((isModelSwitchingDisabled || (viewModel.apiConfiguration == nil && localModelManager.downloadedModels.isEmpty)) ? 0.5 : 1)
    }
    
    // MARK: - New Chat Button with Glass Effect (matched sizing to toolbar)
    
    @ViewBuilder
    private var newChatButton: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            
            let newConversation = conversationManager.createNewConversation()
            selectedConversation = newConversation
        }) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 20, height: 20)
                .padding(10)
                .glassEffect(in: .circle)
                .accessibilityLabel("New chat")
        }
        .buttonStyle(.plain)
        .disabled(true)
        .opacity(0.5)
        .accessibilityHint("Disabled on Home because you are already starting a new chat")
    }
    
    // MARK: - Welcome Content
    
    private var welcomeContent: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text("Welcome to Dualo")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text("Cloud & local AI, unified")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                // Loading indicator for local model
                if ggufService.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.7)))
                            .scaleEffect(0.8)
                        
                        Text("Loading model...")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            
            Spacer()
            
            // Prompt suggestions
            promptSuggestionsView
            
            // Feature hints (optional, subtle)
            VStack(spacing: 8) {
                Text("Swipe right for conversations")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            isInputFocused = false
        }
    }
    
    // MARK: - Prompt Suggestions
    
    private var promptSuggestionsView: some View {
        VStack(spacing: 12) {
            Text("Try asking")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.5))
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(promptSuggestions, id: \.1) { emoji, text in
                    Button(action: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        messageText = text
                        isInputFocused = true
                    }) {
                        HStack(spacing: 8) {
                            Text(emoji)
                                .font(.system(size: 16))
                            Text(text)
                                .font(.subheadline)
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(.white.opacity(0.12), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
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
                    // + button for attachments
                    Button(action: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        showAttachmentOptions = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    
                    TextField("Ask anything", text: $messageText, axis: .vertical)
                        .font(.body)
                        .lineLimit(1...6)
                        .textFieldStyle(.plain)
                        .tint(.accentColor)
                        .focused($isInputFocused)
                        .onSubmit {
                            if canSendMessage {
                                sendMessage()
                            }
                        }
                    
                    // Send button with bounce animation
                    Button(action: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                        sendMessage()
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(canSendMessage ? .blue : .secondary.opacity(0.5))
                            .scaleEffect(canSendMessage ? 1.0 : 0.8)
                            .rotationEffect(.degrees(canSendMessage ? 0 : -90))
                    }
                    .disabled(!canSendMessage)
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
            print("HomeView: Model switch blocked - loading/generating in progress")
            return
        }
        
        // Unload local model when switching to API provider
        if provider != .local && GGUFService.shared.isModelLoaded {
            GGUFService.shared.unloadModel()
        }
        
        // Get the API key for the provider
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
                    
                    // Save to keychain
                    var updatedConfigs = configs
                    updatedConfigs.setConfiguration(newConfig)
                    try KeychainService.shared.saveProviderConfigurations(updatedConfigs)
                }
            }
        } catch {
            print("Failed to update model selection: \(error)")
        }
    }
    
    private func selectLocalModel(_ model: LocalModel) {
        // Safety guard: prevent model switching during generation
        guard !isModelSwitchingDisabled else {
            print("HomeView: Local model switch blocked - loading/generating in progress")
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
            print("Failed to save local model selection: \(error)")
        }
        
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
    
    private func modelDisplayName(for model: String) -> String {
        ModelUtilities.displayName(for: model, localModels: localModelManager.availableModels)
    }
}

#Preview {
    HomeView()
}
