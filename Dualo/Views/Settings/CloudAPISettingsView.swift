//
//  CloudAPISettingsView.swift
//  Dualo
//
//  Cloud API provider API key configuration view.
//

import SwiftUI

struct CloudAPISettingsView: View {
    // State for which provider's config we're viewing/editing
    @State private var selectedProvider: APIProvider = .anthropic
    @State private var apiKeys: [APIProvider: String] = [:]
    @State private var saveError: String?
    @State private var debounceTask: Task<Void, Never>?
    @State private var isTestingConnection = false
    @State private var connectionTestResult: ConnectionTestResult?
    @State private var apiKeyValidationErrors: [APIProvider: String] = [:]
    
    private var currentAPIKey: String {
        apiKeys[selectedProvider] ?? ""
    }
    
    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { self.apiKeys[self.selectedProvider] ?? "" },
            set: { self.apiKeys[self.selectedProvider] = $0 }
        )
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Provider Cards
                providerCardsSection
                
                // API Key configuration
                apiKeyConfigSection
                
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
            loadAPIKeys()
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
                    hasKey: isAPIKeyValid(apiKeys[.anthropic] ?? "", for: .anthropic),
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
                    hasKey: isAPIKeyValid(apiKeys[.openai] ?? "", for: .openai),
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
    
    // MARK: - API Key Configuration
    
    private var apiKeyConfigSection: some View {
        VStack(spacing: 16) {
            // API Key Card
            APIKeyInputView(
                provider: selectedProvider,
                apiKey: apiKeyBinding,
                validationError: apiKeyValidationErrors[selectedProvider],
                onKeyChange: handleAPIKeyChange
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
                    saveAPIKey()
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
        
        // Validate the new provider's API key for display purposes
        let newKey = apiKeys[newProvider] ?? ""
        if let error = validateAPIKeyFormat(newKey, for: newProvider) {
            apiKeyValidationErrors[newProvider] = error
        } else {
            apiKeyValidationErrors[newProvider] = nil
        }
    }
    
    private func loadAPIKeys() {
        do {
            if let configs = try KeychainService.shared.loadProviderConfigurations() {
                if let anthropicConfig = configs.anthropic {
                    apiKeys[.anthropic] = anthropicConfig.apiKey
                }
                
                if let openaiConfig = configs.openai {
                    apiKeys[.openai] = openaiConfig.apiKey
                }
            }
        } catch {
            print("Failed to load API keys: \(error)")
        }
    }
    
    private func saveAPIKey() {
        let apiKey = apiKeys[selectedProvider] ?? ""
        
        // Only save if the key is empty (clearing) or valid
        guard apiKey.isEmpty || isAPIKeyValid(apiKey, for: selectedProvider) else { return }
        
        do {
            var configs = try KeychainService.shared.loadProviderConfigurations() ?? ProviderConfigurations()
            
            // Get existing config for this provider or create new one with default model
            let existingConfig = selectedProvider == .anthropic ? configs.anthropic : configs.openai
            let model = existingConfig?.model ?? selectedProvider.defaultModel
            
            let config = APIConfiguration(
                provider: selectedProvider,
                apiKey: apiKey,
                model: model
            )
            
            configs.setConfiguration(config)
            try KeychainService.shared.saveProviderConfigurations(configs)
            
            if saveError != nil {
                saveError = nil
            }
        } catch {
            saveError = "Failed to save API key: \(error.localizedDescription)"
        }
    }
    
    /// Checks if an API key is valid (has correct prefix and sufficient length)
    private func isAPIKeyValid(_ apiKey: String, for provider: APIProvider) -> Bool {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedKey.isEmpty else { return false }
        
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
                    model: selectedProvider.defaultModel
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

// MARK: - Preview

#Preview {
    NavigationStack {
        CloudAPISettingsView()
    }
}
