//
//  Constants.swift
//  Dualo
//
//  Created by Robert Conover on 8/13/25.
//

import Foundation

// MARK: - Application Constants

enum AppConstants {

    // MARK: - Network
    enum Network {
        static let defaultTimeoutInterval: TimeInterval = 120  // Increased for image uploads
        static let resourceTimeoutInterval: TimeInterval = 180 // Increased for image uploads
    }

    // MARK: - API Configuration
    enum API {
        // Token limits
        static let reasoningModelMaxTokens = 32768

        // Request parameters
        static let defaultTemperature = 0.7
        static let reasoningModelEffort = "medium"
    }

    // MARK: - UI Configuration
    enum UI {
        // Streaming updates
        static let streamingUIUpdateInterval: TimeInterval = 0.05 // 50ms for smooth token-by-token rendering
        static let streamingPersistInterval: TimeInterval = 0.5 // Save partial replies at most every 500ms...
        static let streamingPersistCharThreshold = 100 // ...or every 100 new characters
        static let streamingProgressLogInterval = 50 // Log every N characters

        // Animation
        static let springAnimationResponse: Double = 0.4
        static let springAnimationDamping: Double = 0.8

        // UI Thresholds
        static let previewMaxLength = 50
        static let titleWordLimit = 4
    }

    // MARK: - Data Management
    enum Data {
        // UserDefaults keys
        static let conversationsKey = "SavedConversations"
        static let currentConversationKey = "CurrentConversationID"
        static let legacyMessagesKey = "SavedMessages"

        // Default values
        static let newChatTitle = "New Chat"
        static let importedChatTitle = "Imported Chat"
        static let noMessagesPreview = "No messages"
    }

    // MARK: - Security
    enum Security {
        // API Key validation patterns
        static let openaiKeyPrefix = "sk-"
        static let openaiKeyMinLength = 21

        // Keychain configuration
        static let legacyKeychainService = "com.localllm.apikeys"
        static let configurationKey = "APIConfiguration"
        static let providerConfigurationsKey = "ProviderConfigurations"
    }

    // MARK: - Local Models (GGUF)
    enum LocalModels {
        // Storage paths
        static let modelsDirectoryName = "Models"

        // UserDefaults keys
        static let downloadedModelsKey = "DownloadedLocalModels"
        static let selectedLocalModelKey = "SelectedLocalModel"
        /// Whether chats on a local model show the generation stats above the composer
        static let showGenerationStatsKey = "ShowGenerationStats"

        // Model loading
        static let defaultTemperature: Float = 0.7

        // Context window cap for mobile devices
        // Full context (32K+) would use too much RAM for the KV cache
        // 4096 tokens is a balance for mobile devices
        static let maxMobileContextTokens = 4096

        /// Chats whose model memory is kept on disk (up to about 80 MB each for Qwen3.5 0.8B)
        static let maxSavedChatMemories = 3

        // Chat titles the model writes after a chat's first reply
        static let maxTitleTokens = 24
        static let maxTitleWords = 8
        /// How much of the first message the model reads to name the chat
        static let titleMessageCharacterLimit = 1000
    }
}

// MARK: - String Constants

enum StringConstants {
    enum Errors {
        static let configurationRequired = "Please configure your API settings first"
        static let networkError = "Network error occurred"

        // Local model errors
        static let modelLoadFailed = "Failed to load the model"
        static let downloadFailed = "Failed to download the model"
    }

    enum Messages {
        // Local model messages
        static let modelReady = "Model ready"
    }

    enum UI {
        // Local models UI
        static let localModelsTitle = "Local Models"
        static let downloadButton = "Download"
        static let recommendedBadge = "Recommended"
        static let noModelsDownloaded = "No models downloaded"
    }
}

// MARK: - SystemImages Constants

enum SystemImages {
    // Navigation and UI
    static let pencil = "pencil"
    static let cpu = "cpu"
    static let plus = "plus"
    static let checkmark = "checkmark"

    // Content types
    static let brainProfile = "brain.head.profile"
    static let sparkles = "sparkles"
    static let message = "message"

    // Actions
    static let copyIcon = "doc.on.doc"

    // Local models
    static let iphone = "iphone"
    static let cloudFill = "cloud.fill"
    static let trash = "trash"
}
