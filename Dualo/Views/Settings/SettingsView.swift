//
//  SettingsView.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI
import OSLog

// MARK: - Settings View

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
    
    // App version from bundle
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
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
        } header: {
            Text("On-Device Models")
        } footer: {
            Label("100% private. Models run entirely on your device.", systemImage: "lock.shield.fill")
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
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: colors.map { $0.opacity(0.2) },
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 28, height: 28)
            
            Text(letter)
                .font(.system(size: 13, weight: .bold, design: .rounded))
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
        apiKeyValidationError = validateAPIKeyFormat(newKey, checkLength: false)

        debounceTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 500_000_000)

                if !Task.isCancelled {
                    withAnimation {
                        apiKeyValidationError = validateAPIKeyFormat(openAIAPIKey)
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
        // Pasted keys often carry a trailing newline or space; never store those.
        let apiKey = trimmedAPIKey
        
        guard apiKey.isEmpty || validateAPIKeyFormat(apiKey) == nil else { return }
        
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
        openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Single source of truth for key format: the inline error and the save guard both use it.
    private func validateAPIKeyFormat(_ apiKey: String, checkLength: Bool = true) -> String? {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedKey.isEmpty {
            return nil
        }

        if !trimmedKey.hasPrefix(AppConstants.Security.openaiKeyPrefix) {
            return "OpenAI API keys must start with '\(AppConstants.Security.openaiKeyPrefix)'"
        }
        
        if checkLength && trimmedKey.count < AppConstants.Security.openaiKeyMinLength {
            return "This key looks too short. Check that it was copied in full."
        }
        
        return nil
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
