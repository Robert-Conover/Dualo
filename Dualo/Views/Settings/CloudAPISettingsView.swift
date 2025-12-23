//
//  CloudAPISettingsView.swift
//  Dualo
//
//  Cloud API provider configuration view.
//

import SwiftUI

struct CloudAPISettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    
    // Cloud AI state
    @State private var selectedProvider: APIProvider = .anthropic
    @State private var apiKeys: [APIProvider: String] = [:]
    @State private var selectedModels: [APIProvider: String] = [:]
    @State private var showingSaveConfirmation = false
    @State private var saveError: String?
    @State private var debounceTask: Task<Void, Never>?
    @State private var providerConfigs = ProviderConfigurations()
    @State private var isTestingConnection = false
    @State private var connectionTestResult: ConnectionTestResult?
    @FocusState private var isInputFocused: Bool
    @State private var apiKeyValidationErrors: [APIProvider: String] = [:]
    
    private var currentAPIKey: String {
        get { apiKeys[selectedProvider] ?? "" }
        set { apiKeys[selectedProvider] = newValue }
    }
    
    private var currentSelectedModel: String {
        get { selectedModels[selectedProvider] ?? selectedProvider.defaultModel }
        set { selectedModels[selectedProvider] = newValue }
    }
    
    private var currentModelDisplayText: String {
        let model = selectedModels[selectedProvider] ?? ""
        return model.isEmpty ? "Select Model" : model
    }
    
    private var currentAvailableModels: [String] {
        return selectedProvider.availableModels
    }
    
    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { self.apiKeys[self.selectedProvider] ?? "" },
            set: { self.apiKeys[self.selectedProvider] = $0 }
        )
    }
    
    private var modelSelectionBinding: Binding<String> {
        Binding(
            get: { self.selectedModels[self.selectedProvider] ?? self.selectedProvider.defaultModel },
            set: { self.selectedModels[self.selectedProvider] = $0 }
        )
    }
    
    private var modelSelectionView: some View {
        CloudModelSelectionView(
            availableModels: currentAvailableModels,
            selectedModel: modelSelectionBinding,
            onSelectionChange: handleModelSelectionChange
        )
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Provider Cards
                providerCardsSection
                
                // Selected provider configuration
                if !currentAPIKey.isEmpty || selectedProvider == .anthropic || selectedProvider == .openai {
                    selectedProviderConfig
                }
                
                // Links section
                ResourcesCardView(provider: selectedProvider)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Cloud API")
        .navigationBarTitleDisplayMode(.large)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            loadCurrentConfiguration()
        }
        .alert("Configuration Saved", isPresented: $showingSaveConfirmation) {
            Button("OK") {
                let successFeedback = UINotificationFeedbackGenerator()
                successFeedback.notificationOccurred(.success)
            }
        } message: {
            Text("Your API configuration has been saved successfully.")
        }
        .alert("Error", isPresented: .constant(saveError != nil)) {
            Button("OK") {
                let errorFeedback = UINotificationFeedbackGenerator()
                errorFeedback.notificationOccurred(.error)
                saveError = nil
            }
        } message: {
            Text(saveError ?? "")
        }
    }
    
    // MARK: - Provider Cards
    
    private var providerCardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Provider")
                .font(.headline)
                .foregroundStyle(.primary)
            
            HStack(spacing: 12) {
                ProviderCardView(
                    provider: .anthropic,
                    isSelected: selectedProvider == .anthropic,
                    hasKey: !(apiKeys[.anthropic] ?? "").isEmpty,
                    onSelect: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedProvider = .anthropic
                        }
                        handleProviderChange(.anthropic)
                    }
                )
                
                ProviderCardView(
                    provider: .openai,
                    isSelected: selectedProvider == .openai,
                    hasKey: !(apiKeys[.openai] ?? "").isEmpty,
                    onSelect: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedProvider = .openai
                        }
                        handleProviderChange(.openai)
                    }
                )
            }
        }
    }
    
    // MARK: - Selected Provider Configuration
    
    private var selectedProviderConfig: some View {
        VStack(spacing: 16) {
            // API Key Card
            APIKeyInputView(
                provider: selectedProvider,
                apiKey: apiKeyBinding,
                validationError: apiKeyValidationErrors[selectedProvider],
                onKeyChange: handleAPIKeyChange
            )
            
            // Model Selection Card
            ModelSelectionCardView(
                currentModel: currentModelDisplayText,
                isAPIKeyEmpty: currentAPIKey.isEmpty,
                modelSelectionView: AnyView(modelSelectionView)
            )
            
            // Test Connection Button
            TestConnectionButtonView(
                isAPIKeyEmpty: currentAPIKey.isEmpty,
                isTestingConnection: isTestingConnection,
                connectionTestResult: connectionTestResult,
                onTest: testConnection,
                onDismissResult: {
                    withAnimation {
                        connectionTestResult = nil
                    }
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                }
            )
        }
    }
    
    // MARK: - Helper Functions
    
    private func handleModelSelectionChange(_ newModel: String) {
        selectedModels[selectedProvider] = newModel
        autoSaveConfiguration()
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func handleAPIKeyChange(_ newKey: String) {
        debounceTask?.cancel()
        connectionTestResult = nil
        
        if let error = validateAPIKeyFormat(newKey, for: selectedProvider) {
            apiKeyValidationErrors[selectedProvider] = error
        } else {
            apiKeyValidationErrors[selectedProvider] = nil
        }
        
        debounceTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
                
                if !Task.isCancelled {
                    autoSaveConfiguration()
                }
            } catch {
                // Task was cancelled
            }
        }
    }
    
    private func handleProviderChange(_ newProvider: APIProvider) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        connectionTestResult = nil
        
        let newKey = apiKeys[newProvider] ?? ""
        if let error = validateAPIKeyFormat(newKey, for: newProvider) {
            apiKeyValidationErrors[newProvider] = error
        } else {
            apiKeyValidationErrors[newProvider] = nil
        }
        
        if selectedModels[newProvider] == nil {
            selectedModels[newProvider] = newProvider.defaultModel
        }
        
        autoSaveConfiguration()
    }
    
    private func loadCurrentConfiguration() {
        do {
            if let configs = try KeychainService.shared.loadProviderConfigurations() {
                providerConfigs = configs
                selectedProvider = configs.selectedProvider
                
                if let anthropicConfig = configs.anthropic {
                    apiKeys[.anthropic] = anthropicConfig.apiKey
                    selectedModels[.anthropic] = anthropicConfig.model
                }
                
                if let openaiConfig = configs.openai {
                    apiKeys[.openai] = openaiConfig.apiKey
                    selectedModels[.openai] = openaiConfig.model
                }
                
                if let currentConfig = configs.currentConfiguration() {
                    viewModel.apiConfiguration = currentConfig
                }
            } else if let legacyConfig = viewModel.apiConfiguration {
                selectedProvider = legacyConfig.provider
                apiKeys[legacyConfig.provider] = legacyConfig.apiKey
                selectedModels[legacyConfig.provider] = legacyConfig.model
                
                providerConfigs.selectedProvider = legacyConfig.provider
                providerConfigs.setConfiguration(legacyConfig)
                
                try KeychainService.shared.saveProviderConfigurations(providerConfigs)
            }
            
            for provider in APIProvider.allCases {
                if selectedModels[provider] == nil {
                    selectedModels[provider] = provider.defaultModel
                }
            }
        } catch {
            print("Failed to load configurations: \(error)")
            for provider in APIProvider.allCases {
                selectedModels[provider] = provider.defaultModel
            }
        }
    }
    
    private func autoSaveConfiguration() {
        let apiKey = apiKeys[selectedProvider] ?? ""
        let config = APIConfiguration(
            provider: selectedProvider,
            apiKey: apiKey,
            model: selectedModels[selectedProvider] ?? selectedProvider.defaultModel
        )
        
        let shouldSave = apiKey.isEmpty || isAPIKeyReasonablyComplete(apiKey, for: selectedProvider)
        
        if shouldSave {
            do {
                providerConfigs.setConfiguration(config)
                try KeychainService.shared.saveProviderConfigurations(providerConfigs)
                viewModel.apiConfiguration = config
                if saveError != nil {
                    saveError = nil
                }
            } catch {
                saveError = "Failed to auto-save configuration: \(error.localizedDescription)"
            }
        }
    }
    
    private func isAPIKeyReasonablyComplete(_ apiKey: String, for provider: APIProvider) -> Bool {
        if provider == .local {
            return true
        }
        
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch provider {
        case .anthropic:
            return trimmedKey.hasPrefix(AppConstants.Security.anthropicKeyPrefix) && trimmedKey.count > 20
        case .openai:
            return trimmedKey.hasPrefix(AppConstants.Security.openaiKeyPrefix) && trimmedKey.count > 20
        case .local:
            return true
        }
    }
    
    private func validateAPIKeyFormat(_ apiKey: String, for provider: APIProvider) -> String? {
        if provider == .local {
            return nil
        }
        
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedKey.isEmpty {
            return nil
        }
        
        switch provider {
        case .anthropic:
            if !trimmedKey.hasPrefix(AppConstants.Security.anthropicKeyPrefix) {
                return "Anthropic API keys must start with '\(AppConstants.Security.anthropicKeyPrefix)'"
            }
        case .openai:
            if !trimmedKey.hasPrefix(AppConstants.Security.openaiKeyPrefix) {
                return "OpenAI API keys must start with '\(AppConstants.Security.openaiKeyPrefix)'"
            }
        case .local:
            return nil
        }
        
        return nil
    }
    
    private func testConnection() {
        isTestingConnection = true
        connectionTestResult = nil
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        Task {
            do {
                let config = APIConfiguration(
                    provider: selectedProvider,
                    apiKey: apiKeys[selectedProvider] ?? "",
                    model: selectedModels[selectedProvider] ?? selectedProvider.defaultModel
                )
                
                let _ = try await APIService.shared.sendMessage(
                    "Hello! Please respond with 'Connection successful' if you receive this.",
                    history: [],
                    config: config
                )
                
                await MainActor.run {
                    isTestingConnection = false
                    connectionTestResult = .success
                    
                    let successFeedback = UINotificationFeedbackGenerator()
                    successFeedback.notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    isTestingConnection = false
                    connectionTestResult = .failure("Failed")
                    
                    let errorFeedback = UINotificationFeedbackGenerator()
                    errorFeedback.notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - Cloud Model Selection View

private struct CloudModelSelectionView: View {
    let availableModels: [String]
    @Binding var selectedModel: String
    let onSelectionChange: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            ForEach(availableModels, id: \.self) { model in
                Button(action: {
                    selectedModel = model
                    onSelectionChange(model)
                    dismiss()
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model)
                                .font(.body)
                                .foregroundStyle(.primary)
                            
                            Text(modelDescription(for: model))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        if selectedModel == model {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Select Model")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func modelDescription(for model: String) -> String {
        switch model {
        case let model where model.contains("claude-3-opus"):
            return "Most capable model, best for complex tasks"
        case let model where model.contains("claude-3-sonnet"):
            return "Good balance of capability and speed"
        case let model where model.contains("claude-3-haiku"):
            return "Fastest and most economical"
        case let model where model.contains("gpt-4-turbo"):
            return "Latest GPT-4 with improved performance"
        case "gpt-4o":
            return "Advanced multimodal capabilities"
        case "gpt-5":
            return "Smartest model with built-in thinking"
        case "gpt-5-mini":
            return "Fast GPT-5 for most tasks"
        case "gpt-5-nano":
            return "Ultra-fast lightweight GPT-5"
        case let model where model.contains("o1"):
            return "Advanced reasoning model"
        default:
            return "AI language model"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CloudAPISettingsView(viewModel: ChatViewModel())
    }
}

