//
//  ModelUtilities.swift
//  Dualo
//
//  Shared utilities for model display and provider configuration.
//

import Foundation

/// Shared utilities for working with AI models and providers
enum ModelUtilities {
    
    // MARK: - Model Display Names
    
    /// Returns a user-friendly display name for a model identifier
    /// - Parameters:
    ///   - model: The model identifier (e.g., "claude-3-sonnet-20240229")
    ///   - localModels: Available local models to check against
    /// - Returns: A formatted display name (e.g., "Claude 3 Sonnet")
    static func displayName(for model: String, localModels: [LocalModel] = []) -> String {
        // Check if it's a local model first
        if let localModel = localModels.first(where: { $0.id == model }) {
            return localModel.displayName
        }
        
        // Map cloud model identifiers to friendly names
        switch model {
        case let m where m.contains("claude-3-opus"):
            return "Claude 3 Opus"
        case let m where m.contains("claude-3-sonnet"):
            return "Claude 3 Sonnet"
        case let m where m.contains("claude-3-haiku"):
            return "Claude 3 Haiku"
        case "gpt-4-turbo-preview":
            return "GPT-4 Turbo"
        case "gpt-4o":
            return "GPT-4o"
        case "gpt-5":
            return "GPT-5"
        case "gpt-5-mini":
            return "GPT-5 Mini"
        case "gpt-5-nano":
            return "GPT-5 Nano"
        default:
            return model
        }
    }
    
    // MARK: - Provider Icons
    
    /// Returns the SF Symbol name for a provider's icon
    /// - Parameter provider: The API provider
    /// - Returns: SF Symbol name string
    static func icon(for provider: APIProvider) -> String {
        switch provider {
        case .anthropic, .openai:
            return SystemImages.cloudFill
        case .local:
            return SystemImages.iphone
        }
    }
    
    // MARK: - Provider Configuration
    
    /// Checks if a provider has been configured with valid credentials
    /// - Parameters:
    ///   - provider: The API provider to check
    ///   - downloadedModels: List of downloaded local models (for local provider check)
    /// - Returns: True if the provider is ready to use
    static func isConfigured(_ provider: APIProvider, downloadedModels: [LocalModel] = []) -> Bool {
        // Local provider is configured if there are downloaded models
        if provider == .local {
            return !downloadedModels.isEmpty && DeviceCapability.supportsLocalLLM
        }
        
        // Cloud providers need API keys
        do {
            if let configs = try KeychainService.shared.loadProviderConfigurations() {
                let providerConfig: APIConfiguration?
                switch provider {
                case .anthropic:
                    providerConfig = configs.anthropic
                case .openai:
                    providerConfig = configs.openai
                case .local:
                    return !downloadedModels.isEmpty
                }
                return providerConfig?.apiKey.isEmpty == false
            }
        } catch {
            print("Failed to check provider configuration: \(error)")
        }
        return false
    }
}

