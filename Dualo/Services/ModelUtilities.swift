//
//  ModelUtilities.swift
//  Dualo
//
//  Shared utilities for model display and provider configuration.
//

import Foundation
import OSLog

/// Shared utilities for working with AI models and providers
enum ModelUtilities {
    
    // MARK: - Model Display Names
    
    /// Returns a user-friendly display name for a model identifier
    /// - Parameters:
    ///   - model: The model identifier (e.g., "gpt-6.1-sol")
    ///   - localModels: Available local models to check against
    /// - Returns: A formatted display name (e.g., "Claude 3 Sonnet")
    static func displayName(for model: String, localModels: [LocalModel] = []) -> String {
        // Check if it's a local model first
        if let localModel = localModels.first(where: { $0.id == model }) {
            return localModel.displayName
        }
        
        // Map cloud model identifiers to friendly names
        switch model {
        case "gpt-6-astra":
            return "GPT-6 Astra"
        case "gpt-6.1-sol":
            return "GPT-6.1 Sol"
        case "gpt-6-luna":
            return "GPT-6 Luna"
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
            Logger.config.error("Failed to check provider configuration: \(String(describing: error), privacy: .public)")
        }
        return false
    }
}
