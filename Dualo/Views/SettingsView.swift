//
//  SettingsView.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI

// MARK: - Settings Mode

enum SettingsMode: String, CaseIterable {
    case local = "On-Device"
    case cloud = "Cloud AI"
    
    var icon: String {
        switch self {
        case .cloud: return "cloud.fill"
        case .local: return "iphone"
        }
    }
    
    var description: String {
        switch self {
        case .cloud: return "Use Anthropic or OpenAI APIs"
        case .local: return "Run models privately on device"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject private var viewModel: ChatViewModel
    @ObservedObject private var localModelManager = LocalModelManager.shared
    @Environment(\.dismiss) private var dismiss
    
    // Mode toggle
    @State private var selectedMode: SettingsMode = .local
    
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
    
    // Animation
    @State private var animateHeader = false
    
    enum ConnectionTestResult {
        case success
        case failure(String)
    }
    
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
    
    private var apiKeyStatusText: String {
        return currentAPIKey.isEmpty ? "Not Set" : "Configured"
    }
    
    private var apiKeyStatusColor: Color {
        return currentAPIKey.isEmpty ? .red : .green
    }
    
    private var providerURL: URL? {
        let urlString = selectedProvider == .anthropic ? "https://console.anthropic.com" : "https://platform.openai.com"
        return URL(string: urlString)
    }
    
    init(viewModel: ChatViewModel? = nil) {
        self.viewModel = viewModel ?? ChatViewModel()
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
        SettingsModelSelectionView(
            availableModels: currentAvailableModels,
            selectedModel: modelSelectionBinding,
            onSelectionChange: handleModelSelectionChange
        )
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Mode Toggle
                    modeToggle
                        .padding(.top, 8)
                    
                    // Mode-specific content
                    if selectedMode == .cloud {
                        cloudAIContent
        } else {
                        onDeviceContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
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
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                loadCurrentConfiguration()
                determineInitialMode()
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    animateHeader = true
                }
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
    }
    
    // MARK: - Mode Toggle
    
    private var modeToggle: some View {
        VStack(spacing: 16) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: selectedMode == .cloud 
                                ? [.blue.opacity(0.3), .purple.opacity(0.2)]
                                : [.green.opacity(0.3), .mint.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .scaleEffect(animateHeader ? 1.05 : 0.95)
                
                Image(systemName: selectedMode.icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: selectedMode == .cloud 
                                ? [.blue, .purple]
                                : [.green, .mint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.pulse.wholeSymbol, options: .speed(0.5))
            }
            
            Text(selectedMode.description)
                .font(.subheadline)
                    .foregroundStyle(.secondary)
            
            // Toggle pills
            HStack(spacing: 0) {
                ForEach(SettingsMode.allCases, id: \.self) { mode in
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            selectedMode = mode
                        }
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 14, weight: .semibold))
                            Text(mode.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(selectedMode == mode ? .white : .secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
                        .background {
                            if selectedMode == mode {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: mode == .cloud 
                                                ? [.blue, .purple.opacity(0.8)]
                                                : [.green, .mint.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: mode == .cloud ? .blue.opacity(0.3) : .green.opacity(0.3), radius: 8, y: 4)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                Capsule()
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
            .padding(.vertical, 8)
        }
    
    // MARK: - Cloud AI Content
    
    private var cloudAIContent: some View {
        VStack(spacing: 20) {
            // Provider Cards
            providerCardsSection
            
            // Selected provider configuration
            if !currentAPIKey.isEmpty || selectedProvider == .anthropic || selectedProvider == .openai {
                selectedProviderConfig
            }
            
            // Links section
            linksCard
        }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }
    
    // MARK: - Provider Cards
    
    private var providerCardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Provider")
                .font(.headline)
                .foregroundStyle(.primary)
            
            HStack(spacing: 12) {
                providerCard(for: .anthropic)
                providerCard(for: .openai)
            }
        }
    }
    
    private func providerCard(for provider: APIProvider) -> some View {
        let isSelected = selectedProvider == provider
        let hasKey = !(apiKeys[provider] ?? "").isEmpty
        
        return Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedProvider = provider
            }
            handleProviderChange(provider)
        }) {
            VStack(spacing: 12) {
                // Icon
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
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: provider == .anthropic ? "brain" : "sparkles")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(provider == .anthropic ? .orange : .green)
                }
                
                // Name
                Text(provider.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                
                // Status badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(hasKey ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(hasKey ? "Ready" : "Setup")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(hasKey ? .green : .orange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(hasKey ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isSelected 
                                    ? (provider == .anthropic ? Color.orange : Color.green)
                                    : Color.clear,
                                lineWidth: 2
                            )
                    )
                    .shadow(color: isSelected ? (provider == .anthropic ? .orange.opacity(0.15) : .green.opacity(0.15)) : .clear, radius: 8, y: 4)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
    
    // MARK: - Selected Provider Configuration
    
    private var selectedProviderConfig: some View {
        VStack(spacing: 16) {
            // API Key Card
            VStack(alignment: .leading, spacing: 12) {
            Label {
                    Text("API Key")
                        .font(.headline)
                } icon: {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.orange)
                }
                
                HStack(spacing: 12) {
                    SecureField("Enter your \(selectedProvider.displayName) API key", text: apiKeyBinding)
                    .textContentType(.password)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .focused($isInputFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.tertiarySystemGroupedBackground))
                        )
                    .onChangeCompat(of: apiKeys[selectedProvider] ?? "") { newKey in
                        handleAPIKeyChange(newKey)
                    }
                }
                
                Label("Encrypted and stored securely in Keychain", systemImage: "lock.shield.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            
            // Model Selection Card
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text("Default Model")
                        .font(.headline)
                } icon: {
                    Image(systemName: "cpu")
                        .foregroundStyle(.purple)
                }
                
                NavigationLink(destination: modelSelectionView) {
                    HStack {
                        Text(currentModelDisplayText)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.tertiarySystemGroupedBackground))
                    )
            }
            .disabled(currentAPIKey.isEmpty)
                .opacity(currentAPIKey.isEmpty ? 0.5 : 1)
            
            if currentAPIKey.isEmpty {
                Label("Enter an API key to select models", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            
            // Test Connection Button
            testConnectionButton
        }
    }
    
    private var testConnectionButton: some View {
        Button(action: {
            testConnection()
        }) {
            HStack(spacing: 12) {
                if isTestingConnection {
                    ProgressView()
                        .scaleEffect(0.9)
                } else if let result = connectionTestResult {
                    switch result {
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failure:
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                } else {
                    Image(systemName: "wifi.circle")
                    .foregroundStyle(.blue)
            }
            
                Text(testConnectionButtonText)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .disabled(currentAPIKey.isEmpty || isTestingConnection)
        .opacity(currentAPIKey.isEmpty ? 0.5 : 1)
    }
    
    private var testConnectionButtonText: String {
        if isTestingConnection {
            return "Testing..."
        } else if let result = connectionTestResult {
            switch result {
            case .success:
                return "Connected!"
            case .failure(let error):
                return error
            }
        } else {
            return "Test Connection"
        }
    }
    
    // MARK: - Links Card
    
    private var linksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resources")
                .font(.headline)
                .foregroundStyle(.primary)
            
            if let url = providerURL {
                Link(destination: url) {
                HStack {
                        Label {
                            Text("Get \(selectedProvider.displayName) API Key")
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "link")
                                .foregroundStyle(.blue)
                        }
                    Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.tertiarySystemGroupedBackground))
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
    
    // MARK: - On-Device Content
    
    private var onDeviceContent: some View {
        VStack(spacing: 20) {
            // Storage overview card
            storageCard
            
            // Models list
            modelsListCard
            
            // Privacy info
            privacyInfoCard
        }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }
    
    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Storage", systemImage: "internaldrive")
                    .font(.headline)
                
                Spacer()
                
                Text("\(localModelManager.formattedStorageUsed) / \(localModelManager.formattedTotalStorage)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: storageBarWidth(in: geometry.size.width), height: 8)
                }
            }
            .frame(height: 8)
            
                    HStack {
                Text("\(localModelManager.downloadedModels.count) model\(localModelManager.downloadedModels.count == 1 ? "" : "s") downloaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                        Spacer()
                
                Text("\(localModelManager.formattedAvailableStorage) available")
                    .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
    
    private func storageBarWidth(in totalWidth: CGFloat) -> CGFloat {
        let used = localModelManager.calculateStorageUsed()
        let total = DeviceCapability.totalStorageBytes
        guard total > 0 else { return 0 }
        let percentage = CGFloat(used) / CGFloat(total)
        return min(totalWidth * percentage, totalWidth)
    }
    
    private var modelsListCard: some View {
        VStack(alignment: .leading, spacing: 12) {
                    HStack {
                Text("Available Models")
                    .font(.headline)
                
                        Spacer()
                
                NavigationLink(destination: LocalModelsView()) {
                    Text("Manage")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)
                }
            }
            
            // Quick model list
            ForEach(localModelManager.availableModels.prefix(3)) { model in
                modelQuickRow(model)
            }
            
            if localModelManager.availableModels.count > 3 {
                NavigationLink(destination: LocalModelsView()) {
                    HStack {
                        Text("See all \(localModelManager.availableModels.count) models")
                            .font(.subheadline)
                        .foregroundStyle(.blue)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
    
    private func modelQuickRow(_ model: LocalModel) -> some View {
        HStack(spacing: 12) {
            // Icon
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
            
            // Status
            modelStatusBadge(for: model)
        }
        .padding(.vertical, 8)
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
    
    private var privacyInfoCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 24))
                .foregroundStyle(.green)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("100% Private")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Models run entirely on your device. No data is sent to any server.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.green.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Helper Functions
    
    private func determineInitialMode() {
        // If user has local model selected, start in local mode
        if let config = viewModel.apiConfiguration, config.provider == .local {
            selectedMode = .local
        } else if localModelManager.selectedModel != nil && viewModel.apiConfiguration == nil {
            selectedMode = .local
        }
    }
    
    private func handleModelSelectionChange(_ newModel: String) {
        selectedModels[selectedProvider] = newModel
        autoSaveConfiguration()
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func handleAPIKeyChange(_ newKey: String) {
        debounceTask?.cancel()
        connectionTestResult = nil // Reset test result when key changes
        
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
        
        connectionTestResult = nil // Reset test result when provider changes
        
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
                
                // Reset after delay
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    connectionTestResult = nil
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

// MARK: - Settings Model Selection View

private struct SettingsModelSelectionView: View {
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

#Preview {
    SettingsView()
}
