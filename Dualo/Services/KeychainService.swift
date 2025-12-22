//
//  KeychainService.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import Foundation
import Security

class KeychainService {
    static let shared = KeychainService()
    
    // Use bundle identifier for better security isolation
    private let service: String
    private let configKey = AppConstants.Security.configurationKey
    private let providerConfigsKey = AppConstants.Security.providerConfigurationsKey
    
    private init() {
        // Get the bundle identifier, fallback to legacy service ID for migration
        self.service = Bundle.main.bundleIdentifier ?? AppConstants.Security.legacyKeychainService
        
        #if DEBUG
        print("KeychainService: Using service identifier: \(service)")
        #endif
    }
    
    func saveAPIConfiguration(_ config: APIConfiguration) throws {
        // Validate API key before storage
        try validateAPIKey(config.apiKey, for: config.provider)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: configKey,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status != errSecSuccess {
            throw KeychainError.unableToSave
        }
    }
    
    func loadAPIConfiguration() throws -> APIConfiguration? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: configKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        if status != errSecSuccess {
            throw KeychainError.unableToLoad
        }
        
        guard let data = result as? Data else {
            throw KeychainError.dataCorrupted
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(APIConfiguration.self, from: data)
    }
    
    func deleteAPIConfiguration() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: configKey
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unableToDelete
        }
    }
    
    func saveProviderConfigurations(_ configs: ProviderConfigurations) throws {
        // Validate all non-nil API keys before storage
        if let anthropicConfig = configs.anthropic {
            try validateAPIKey(anthropicConfig.apiKey, for: anthropicConfig.provider)
        }
        if let openaiConfig = configs.openai {
            try validateAPIKey(openaiConfig.apiKey, for: openaiConfig.provider)
        }
        // Local config doesn't need API key validation
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(configs)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerConfigsKey,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status != errSecSuccess {
            throw KeychainError.unableToSave
        }
    }
    
    func loadProviderConfigurations() throws -> ProviderConfigurations? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerConfigsKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        if status != errSecSuccess {
            throw KeychainError.unableToLoad
        }
        
        guard let data = result as? Data else {
            throw KeychainError.dataCorrupted
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(ProviderConfigurations.self, from: data)
    }
    
    // MARK: - Private Helper Methods
    
    private func validateAPIKey(_ apiKey: String, for provider: APIProvider) throws {
        // Allow empty API keys (for clearing fields or switching providers)
        guard !apiKey.isEmpty else {
            return // Empty keys are valid for saving (user might be clearing the field)
        }
        
        // Only validate format if the key looks complete enough
        // This allows partial typing without validation errors
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Basic format validation for common API key patterns
        switch provider {
        case .anthropic:
            // Only validate if it looks like it might be a complete Anthropic key
            if trimmedKey.count > 10 { // Allow partial typing
                guard trimmedKey.hasPrefix(AppConstants.Security.anthropicKeyPrefix) else {
                    throw KeychainError.invalidAPIKey
                }
            }
        case .openai:
            // Only validate if it looks like it might be a complete OpenAI key  
            if trimmedKey.count > 5 { // Allow partial typing
                guard trimmedKey.hasPrefix(AppConstants.Security.openaiKeyPrefix) else {
                    throw KeychainError.invalidAPIKey
                }
            }
        case .local:
            // Local models don't require API key validation
            break
        }
    }
}

enum KeychainError: LocalizedError {
    case unableToSave
    case unableToLoad
    case unableToDelete
    case dataCorrupted
    case invalidAPIKey
    
    var errorDescription: String? {
        switch self {
        case .unableToSave:
            return "Unable to save to Keychain"
        case .unableToLoad:
            return "Unable to load from Keychain"
        case .unableToDelete:
            return "Unable to delete from Keychain"
        case .dataCorrupted:
            return "Keychain data is corrupted"
        case .invalidAPIKey:
            return "Invalid API key format"
        }
    }
}