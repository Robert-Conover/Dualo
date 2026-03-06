//
//  SettingsView.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var localModelManager: LocalModelManager
    
    // Cloud API state (absorbed from CloudAPISettingsView)
    @State private var selectedProvider: APIProvider = .anthropic
    @State private var apiKeys: [APIProvider: String] = [:]
    @State private var saveError: String?
    @State private var debounceTask: Task<Void, Never>?
    @State private var isTestingConnection = false
    @State private var connectionTestResult: ConnectionTestResult?
    @State private var apiKeyValidationErrors: [APIProvider: String] = [:]
    
    // App version from bundle
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
    
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
        NavigationStack {
            List {
                // MARK: - On-Device Models Section
                onDeviceSection
                
                // MARK: - Cloud AI Section
                cloudAISection
                
                // MARK: - About Section
                Section("About") {
                    SettingsInfoRow(
                        icon: "info.circle",
                        title: "Version",
                        value: appVersion,
                        color: .gray
                    )
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                loadAPIKeys()
            }
            .alert("Error", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK") {
                    let errorFeedback = UINotificationFeedbackGenerator()
                    errorFeedback.notificationOccurred(.error)
                    saveError = nil
                }
            } message: {
                Text(saveError ?? "")
            }
        }
    }
    
    // MARK: - On-Device Models Section
    
    private var onDeviceSection: some View {
        Section {
            // Quick model list (up to 3)
            ForEach(localModelManager.availableModels.prefix(3)) { model in
                modelQuickRow(model)
            }
            
            // "Manage" / "See all" navigation link
            NavigationLink(destination: LocalModelsView()) {
                SettingsRowGradient(
                    icon: "iphone",
                    title: localModelManager.availableModels.count > 3
                        ? "See all \(localModelManager.availableModels.count) models"
                        : "Manage models",
                    gradientColors: [.green, .mint],
                    subtitle: "Download & manage on-device models",
                    showChevron: false
                )
            }
            
            // Privacy info row
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("100% Private")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Models run entirely on your device")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(
                Color.green.opacity(0.06)
            )
        } header: {
            Text("On-Device Models")
        }
    }
    
    private func modelQuickRow(_ model: LocalModel) -> some View {
        HStack(spacing: 12) {
            // Model icon
            modelIcon(for: model)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(localModelManager.getModelSizeString(model))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Status badge
            modelStatusBadge(for: model)
        }
        .padding(.vertical, 4)
    }
    
    private func modelIcon(for model: LocalModel) -> some View {
        let (letter, colors) = iconConfig(for: model)
        
        return ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: colors.map { $0.opacity(0.2) },
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 36, height: 36)
            
            Text(letter)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
    
    private func iconConfig(for model: LocalModel) -> (String, [Color]) {
        let name = model.displayName.lowercased()
        
        if name.contains("qwen") {
            return ("Q", [.purple, .blue])
        } else if name.contains("gemma") {
            return ("G", [.blue, .cyan])
        } else if name.contains("llama") {
            return ("L", [.orange, .red])
        } else if name.contains("mistral") {
            return ("M", [.indigo, .purple])
        } else {
            return ("AI", [.blue, .green])
        }
    }
    
    @ViewBuilder
    private func modelStatusBadge(for model: LocalModel) -> some View {
        switch model.downloadState {
        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .downloading(let progress):
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("\(Int(progress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
        case .notDownloaded:
            Text("Available")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
    
    // MARK: - Cloud AI Section
    
    private var cloudAISection: some View {
        Section {
            // Provider picker rows
            ForEach([APIProvider.anthropic, .openai], id: \.self) { provider in
                providerRow(provider)
            }
            
            // API Key input
            APIKeyInputView(
                provider: selectedProvider,
                apiKey: apiKeyBinding,
                validationError: apiKeyValidationErrors[selectedProvider],
                onKeyChange: handleAPIKeyChange
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            
            // Test Connection
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
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
            
            // Resources link
            ResourcesCardView(provider: selectedProvider)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        } header: {
            Text("Cloud AI")
        }
    }
    
    private func providerRow(_ provider: APIProvider) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedProvider = provider
            }
            handleProviderChange(provider)
        } label: {
            HStack(spacing: 12) {
                // Provider icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: provider == .anthropic
                                    ? [.orange.opacity(0.2), .pink.opacity(0.15)]
                                    : [.green.opacity(0.2), .mint.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: provider == .anthropic ? "brain" : "sparkles")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(provider == .anthropic ? .orange : .green)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.body)
                        .foregroundStyle(.primary)
                    
                    // Status badge
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isAPIKeyValid(apiKeys[provider] ?? "", for: provider) ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(isAPIKeyValid(apiKeys[provider] ?? "", for: provider) ? "Ready" : "Setup needed")
                            .font(.caption2)
                            .foregroundStyle(isAPIKeyValid(apiKeys[provider] ?? "", for: provider) ? .green : .orange)
                    }
                }
                
                Spacer()
                
                if selectedProvider == provider {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.blue)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Cloud API Helpers (from CloudAPISettingsView)
    
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
        
        guard apiKey.isEmpty || isAPIKeyValid(apiKey, for: selectedProvider) else { return }
        
        do {
            var configs = try KeychainService.shared.loadProviderConfigurations() ?? ProviderConfigurations()
            
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

#Preview {
    SettingsView()
        .environmentObject(LocalModelManager.shared)
}
