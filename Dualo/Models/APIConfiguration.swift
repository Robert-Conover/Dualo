//
//  APIConfiguration.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import Foundation

enum APIProvider: String, Codable, CaseIterable {
    case openai = "OpenAI"
    case local = "Local"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case APIProvider.local.rawValue:
            self = .local
        case "Anthropic", APIProvider.openai.rawValue:
            // Anthropic support was removed, so migrate old configs to OpenAI.
            self = .openai
        default:
            self = .openai
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var displayName: String {
        rawValue
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
        case .openai:
            return [
                "gpt-5.2",
                "gpt-5-mini",
                "gpt-5-nano",
                "o3",
                "o4-mini",
                "gpt-4.1"
            ]
        case .local:
            // Local models are managed separately by LocalModelManager
            return []
        }
    }

    var defaultModel: String {
        switch self {
        case .openai:
            return "gpt-5.2"
        case .local:
            return "" // No default - user must download a model first
        }
    }

    static func sanitizedModel(_ model: String?, for provider: APIProvider) -> String {
        switch provider {
        case .openai:
            guard let model, !model.isEmpty else {
                return provider.defaultModel
            }

            if provider.availableModels.contains(model) || model.hasPrefix("gpt-5") || model.hasPrefix("o") || model.hasPrefix("gpt-4.1") {
                return model
            }

            return provider.defaultModel
        case .local:
            return model ?? provider.defaultModel
        }
    }

    /// Get context size (in tokens) for a specific model
    static func contextSize(for model: String, provider: APIProvider) -> Int {
        switch provider {
        case .openai:
            return openAIContextSize(for: model)
        case .local:
            // Local models handled separately via LocalModel.contextSize
            return 0
        }
    }

    private static func openAIContextSize(for model: String) -> Int {
        if model.hasPrefix("gpt-4.1") { return 1_000_000 }
        if model.hasPrefix("o3") || model.hasPrefix("o4") { return 200_000 }
        if model.hasPrefix("gpt-5") { return 400_000 }
        return 200_000
    }
}

struct APIConfiguration: Codable {
    var provider: APIProvider
    var apiKey: String
    var model: String

    init(provider: APIProvider = .openai, apiKey: String = "", model: String? = nil) {
        self.provider = provider
        self.apiKey = apiKey
        self.model = APIProvider.sanitizedModel(model, for: provider)
    }

    private enum CodingKeys: String, CodingKey {
        case provider, apiKey, model
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let provider = try container.decodeIfPresent(APIProvider.self, forKey: .provider) ?? .openai
        let apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        let model = try container.decodeIfPresent(String.self, forKey: .model)

        self.init(provider: provider, apiKey: apiKey, model: model)
    }
}

struct ProviderConfigurations: Codable {
    var openai: APIConfiguration?
    var local: APIConfiguration?
    var selectedProvider: APIProvider

    init(selectedProvider: APIProvider = .openai) {
        self.selectedProvider = selectedProvider
        self.openai = nil
        self.local = nil
    }

    func currentConfiguration() -> APIConfiguration? {
        switch selectedProvider {
        case .openai:
            return openai
        case .local:
            return local
        }
    }

    mutating func setConfiguration(_ config: APIConfiguration) {
        switch config.provider {
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
        case .openai:
            return openai
        case .local:
            return local
        }
    }
}
