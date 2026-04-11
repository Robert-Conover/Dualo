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
    
    private var currentAPIKey: String {
        openAIAPIKey
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
            // API Key input
            APIKeyInputView(
                provider: .openai,
                apiKey: $openAIAPIKey,
                validationError: apiKeyValidationError,
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
            ResourcesCardView()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        } header: {
            Text("Cloud AI")
        }
    }
    
    // MARK: - Cloud API Helpers (from CloudAPISettingsView)
    
    private func handleAPIKeyChange(_ newKey: String) {
        debounceTask?.cancel()
        connectionTestResult = nil
        
        apiKeyValidationError = validateAPIKeyFormat(newKey)
        
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
    
    private func loadAPIKeys() {
        do {
            if let configs = try KeychainService.shared.loadProviderConfigurations() {
                if let openaiConfig = configs.openai {
                    openAIAPIKey = openaiConfig.apiKey
                }
            }
        } catch {
            print("Failed to load API keys: \(error)")
        }
    }
    
    private func saveAPIKey() {
        let apiKey = openAIAPIKey
        
        guard apiKey.isEmpty || isAPIKeyValid(apiKey) else { return }
        
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
        }
    }
    
    private func isAPIKeyValid(_ apiKey: String) -> Bool {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedKey.isEmpty else { return false }

        return trimmedKey.hasPrefix(AppConstants.Security.openaiKeyPrefix) && trimmedKey.count > 20
    }
    
    private func validateAPIKeyFormat(_ apiKey: String) -> String? {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedKey.isEmpty {
            return nil
        }

        if !trimmedKey.hasPrefix(AppConstants.Security.openaiKeyPrefix) {
            return "OpenAI API keys must start with '\(AppConstants.Security.openaiKeyPrefix)'"
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
                    provider: .openai,
                    apiKey: openAIAPIKey,
                    model: APIProvider.openai.defaultModel
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
