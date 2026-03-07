//
//  CloudAISettingsView.swift
//  Dualo
//
//  Created by Robert Conover on 3/7/26.
//

import SwiftUI

// MARK: - Cloud AI Settings View

struct CloudAISettingsView: View {
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
        List {
            // MARK: - Provider Section
            Section {
                ForEach([APIProvider.anthropic, .openai], id: \.self) { provider in
                    providerRow(provider)
                }
            }

            // MARK: - API Key Section
            Section {
                APIKeyInputView(
                    provider: selectedProvider,
                    apiKey: apiKeyBinding,
                    validationError: apiKeyValidationErrors[selectedProvider],
                    onKeyChange: handleAPIKeyChange
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

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
            }

            // MARK: - Resources Section
            Section {
                ResourcesCardView(provider: selectedProvider)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Cloud AI")
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

    // MARK: - Provider Row

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

    // MARK: - Cloud API Helpers

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
    NavigationStack {
        CloudAISettingsView()
    }
}
