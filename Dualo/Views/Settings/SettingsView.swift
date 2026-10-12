//
//  SettingsView.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI
import OSLog

// MARK: - Settings View

/// The Settings sheet: custom instructions, on-device models, the OpenAI API key and
/// permission to send chats to OpenAI, the privacy policy, and the app's version.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var localModelManager: LocalModelManager
    
    // Cloud API state
    @State private var openAIAPIKey = ""
    @State private var saveError: String?
    @State private var debounceTask: Task<Void, Never>?
    @State private var isTestingConnection = false
    @State private var connectionTestResult: ConnectionTestResult?
    @State private var apiKeyValidationError: String?
    @AppStorage(CustomInstructions.key) private var customInstructions = ""
    @AppStorage(AppConstants.LocalModels.showGenerationStatsKey) private var showGenerationStats = true
    @AppStorage(CloudConsent.key) private var allowsSendingToOpenAI = false

    // App version from bundle
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: - Personalization Section
                Section {
                    NavigationLink(destination: CustomInstructionsView()) {
                        SettingsRow(
                            icon: "text.quote",
                            title: "Custom Instructions",
                            color: .orange,
                            subtitle: customInstructions.isEmpty ? "Off" : customInstructions,
                            subtitleLineLimit: 1,
                            showChevron: false
                        )
                    }
                    .accessibilityIdentifier("customInstructionsRow")
                } header: {
                    Text("Personalization")
                }

                // MARK: - On-Device Models Section
                onDeviceSection
                
                // MARK: - Cloud AI Section
                cloudAISection
                
                // MARK: - About Section
                Section("About") {
                    NavigationLink(destination: PrivacyPolicyView()) {
                        SettingsRow(
                            icon: "hand.raised.fill",
                            title: "Privacy Policy",
                            color: .blue,
                            showChevron: false
                        )
                    }
                    .accessibilityIdentifier("privacyPolicyRow")

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
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) {
                        dismiss()
                    }
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
            NavigationLink(destination: LocalModelsView()) {
                SettingsRow(
                    icon: "iphone",
                    title: "Local Models",
                    color: .green,
                    subtitle: downloadedModelsSummary,
                    showChevron: false
                )
            }
            .accessibilityIdentifier("localModelsRow")

            Toggle(isOn: $showGenerationStats) {
                SettingsRow(
                    icon: "speedometer",
                    title: "Generation Stats",
                    color: .blue,
                    subtitle: "Tokens, speed and context use",
                    showChevron: false
                )
            }
            .accessibilityIdentifier("generationStatsToggle")
        } header: {
            Text("On-Device Models")
        } footer: {
            Label("100% private. Models run entirely on your device.", systemImage: "lock.shield.fill")
        }
    }

    private var downloadedModelsSummary: String {
        switch localModelManager.downloadedModels.count {
        case 0: return "Download a model to chat offline"
        case 1: return "1 model downloaded"
        case let count: return "\(count) models downloaded"
        }
    }
    
    // MARK: - Cloud AI Section
    
    private var cloudAISection: some View {
        Section {
            // API Key input
            APIKeyInputView(
                provider: .openai,
                apiKey: $openAIAPIKey,
                validationError: apiKeyValidationError,
                onKeyChange: handleAPIKeyChange
            )
            
            // Test Connection
            TestConnectionButtonView(
                isAPIKeyEmpty: trimmedAPIKey.isEmpty,
                isTestingConnection: isTestingConnection,
                connectionTestResult: connectionTestResult,
                onTest: testConnection,
                onDismissResult: {
                    withAnimation {
                        connectionTestResult = nil
                    }
                    HapticFeedback.light()
                }
            )
            
            Toggle(isOn: $allowsSendingToOpenAI) {
                SettingsRow(
                    icon: "paperplane",
                    title: "Send Chats to OpenAI",
                    color: .purple,
                    subtitle: allowsSendingToOpenAI ? "Allowed for chats on OpenAI models" : "Asks before the first message",
                    showChevron: false
                )
            }
            .accessibilityIdentifier("cloudConsentToggle")

            // Resources link
            APIKeyLinkRow()
        } header: {
            Text("Cloud AI")
        } footer: {
            Label("Encrypted and stored securely in Keychain.", systemImage: "lock.fill")
        }
    }
    
    // MARK: - Cloud API Helpers (from CloudAPISettingsView)
    
    private func handleAPIKeyChange(_ newKey: String) {
        debounceTask?.cancel()
        connectionTestResult = nil
        
        // Flag a wrong prefix right away, but hold the length check until typing
        // pauses so a key being typed isn't called "too short" on every keystroke.
        apiKeyValidationError = APIKeyValidator.validationError(for: newKey, checkLength: false)

        debounceTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 500_000_000)

                if !Task.isCancelled {
                    withAnimation {
                        apiKeyValidationError = APIKeyValidator.validationError(for: openAIAPIKey)
                    }
                    saveAPIKey()
                }
            } catch {
                // Task was cancelled
            }
        }
    }
    
    private func loadAPIKeys() {
        do {
            if let configs = try KeychainService.shared.loadProviderConfigurations() {
                if let openaiConfig = configs.openai {
                    openAIAPIKey = openaiConfig.apiKey
                }
            }
        } catch {
            Logger.config.error("Failed to load API keys: \(String(describing: error), privacy: .public)")
        }
    }
    
    private func saveAPIKey() {
        let apiKey = trimmedAPIKey

        guard APIKeyValidator.validationError(for: apiKey) == nil else { return }
        
        do {
            var configs = try KeychainService.shared.loadProviderConfigurations() ?? ProviderConfigurations()
            
            let existingConfig = configs.openai
            let model = existingConfig?.model ?? APIProvider.openai.defaultModel
            
            let config = APIConfiguration(
                provider: .openai,
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
            HapticFeedback.error()
        }
    }
    
    private var trimmedAPIKey: String {
        APIKeyValidator.normalized(openAIAPIKey)
    }

    private func testConnection() {
        isTestingConnection = true
        connectionTestResult = nil
        
        HapticFeedback.medium()
        
        Task {
            do {
                // Listing models verifies the key without spending tokens on a completion.
                _ = try await APIService.shared.fetchAvailableModels(for: .openai, apiKey: trimmedAPIKey)
                
                await MainActor.run {
                    isTestingConnection = false
                    connectionTestResult = .success
                    HapticFeedback.success()
                }
            } catch {
                Logger.config.error("Connection test failed: \(String(describing: error), privacy: .public)")
                await MainActor.run {
                    isTestingConnection = false
                    connectionTestResult = .failure(connectionFailureMessage(for: error))
                    HapticFeedback.error()
                }
            }
        }
    }
    
    private func connectionFailureMessage(for error: Error) -> String {
        if let networkError = error as? NetworkError {
            switch networkError {
            case .invalidAPIKey:
                return "Invalid API key"
            case .quotaExceeded:
                return "Out of credits. Check your OpenAI billing."
            case .rateLimitExceeded:
                return "Rate limited. Try again shortly."
            case .networkUnavailable:
                return "No internet connection"
            case .serverError:
                return "OpenAI returned an error. Try again later."
            default:
                return "Connection failed"
            }
        }
        
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "No internet connection"
            case .timedOut:
                return "Request timed out"
            default:
                break
            }
        }
        
        return "Connection failed"
    }
}

#Preview {
    SettingsView()
        .environmentObject(LocalModelManager.shared)
}
