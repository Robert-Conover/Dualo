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
    ///   - model: The model identifier (e.g., "gpt-5.2")
    ///   - localModels: Available local models to check against
    /// - Returns: A formatted display name (e.g., "Claude 3 Sonnet")
    static func displayName(for model: String, localModels: [LocalModel] = []) -> String {
        // Check if it's a local model first
        if let localModel = localModels.first(where: { $0.id == model }) {
            return localModel.displayName
        }
        
        // Map cloud model identifiers to friendly names
        switch model {
        case "gpt-5.2":
            return "GPT-5.2"
        case "gpt-5":
            return "GPT-5"
        case "gpt-5-mini":
            return "GPT-5 Mini"
        case "gpt-5-nano":
            return "GPT-5 Nano"
        case "o3":
            return "o3"
        case "o4-mini":
            return "o4-mini"
        case "gpt-4.1":
            return "GPT-4.1"
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
        case .openai:
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
                switch provider {
                case .openai:
                    return configs.openai?.apiKey.isEmpty == false
                case .local:
                    return !downloadedModels.isEmpty
                }
            }
        } catch {
            print("Failed to check provider configuration: \(error)")
        }
        return false
    }
}
