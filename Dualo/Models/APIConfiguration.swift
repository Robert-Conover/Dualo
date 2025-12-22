//
//  APIConfiguration.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import Foundation

enum APIProvider: String, Codable, CaseIterable {
    case anthropic = "Anthropic"
    case openai = "OpenAI"
    case local = "Local"
    
    var displayName: String {
        return self.rawValue
    }
    
    /// Whether this provider requires an API key (cloud providers)
    var isCloudProvider: Bool {
        self != .local
    }
    
    /// Whether this provider requires a network connection
    var requiresNetwork: Bool {
        self != .local
    }
    
    var availableModels: [String] {
        switch self {
        case .anthropic:
            return [
                "claude-3-opus-20240229",
                "claude-3-sonnet-20240229",
                "claude-3-haiku-20240307"
            ]
        case .openai:
            return [
                "gpt-4-turbo-preview",
                "gpt-4o",
                "gpt-5",
                "gpt-5-mini",
                "gpt-5-nano"
            ]
        case .local:
            // Local models are managed separately by LocalModelManager
            return []
        }
    }
    
    var defaultModel: String {
        switch self {
        case .anthropic:
            return "claude-3-sonnet-20240229"
        case .openai:
            return "gpt-4-turbo-preview"
        case .local:
            return "" // No default - user must download a model first
        }
    }
    
    /// Get context size (in tokens) for a specific model
    static func contextSize(for model: String, provider: APIProvider) -> Int {
        switch provider {
        case .anthropic:
            return anthropicContextSize(for: model)
        case .openai:
            return openaiContextSize(for: model)
        case .local:
            // Local models handled separately via LocalModel.contextSize
            return 0
        }
    }
    
    private static func anthropicContextSize(for model: String) -> Int {
        // Anthropic Claude models context sizes
        if model.contains("claude-3-opus") { return 200_000 }
        if model.contains("claude-3-sonnet") { return 200_000 }
        if model.contains("claude-3-haiku") { return 200_000 }
        if model.contains("claude-3-5") { return 200_000 }
        if model.contains("claude-2") { return 100_000 }
        return 200_000 // Default for newer Claude models
    }
    
    private static func openaiContextSize(for model: String) -> Int {
        // OpenAI models context sizes
        if model.contains("gpt-4-turbo") { return 128_000 }
        if model.contains("gpt-4o") { return 128_000 }
        if model.contains("gpt-5") { return 128_000 }
        if model.contains("gpt-4-32k") { return 32_768 }
        if model.contains("gpt-4") { return 8_192 }
        if model.contains("gpt-3.5-turbo-16k") { return 16_384 }
        if model.contains("gpt-3.5") { return 4_096 }
        if model.contains("o1") { return 128_000 }
        return 128_000 // Default for newer models
    }
}

struct APIConfiguration: Codable {
    var provider: APIProvider
    var apiKey: String
    var model: String
    
    init(provider: APIProvider = .anthropic, apiKey: String = "", model: String? = nil) {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model ?? provider.defaultModel
    }
}

struct ProviderConfigurations: Codable {
    var anthropic: APIConfiguration?
    var openai: APIConfiguration?
    var local: APIConfiguration?
    var selectedProvider: APIProvider
    
    init(selectedProvider: APIProvider = .anthropic) {
        self.selectedProvider = selectedProvider
        self.anthropic = nil
        self.openai = nil
        self.local = nil
    }
    
    func currentConfiguration() -> APIConfiguration? {
        switch selectedProvider {
        case .anthropic:
            return anthropic
        case .openai:
            return openai
        case .local:
            return local
        }
    }
    
    mutating func setConfiguration(_ config: APIConfiguration) {
        switch config.provider {
        case .anthropic:
            anthropic = config
        case .openai:
            openai = config
        case .local:
            local = config
        }
        selectedProvider = config.provider
    }
    
    /// Get the configuration for a specific provider (regardless of which is currently selected)
    func configuration(for provider: APIProvider) -> APIConfiguration? {
        switch provider {
        case .anthropic:
            return anthropic
        case .openai:
            return openai
        case .local:
            return local
        }
    }
}