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
        static let maxRetryAttempts = 3
        static let retryDelayBase: TimeInterval = 1.0 // Base for exponential backoff
        static let rateLimitDelay: TimeInterval = 1.0
    }
    
    // MARK: - API Configuration
    enum API {
        // Token limits
        static let defaultMaxTokens = 4096
        static let gpt5MaxTokens = 32768
        
        // Request parameters
        static let defaultTemperature = 0.7
        static let gpt5ReasoningEffort = "medium"
        
        // API Headers
        static let anthropicVersionHeader = "2023-06-01"
    }
    
    // MARK: - UI Configuration
    enum UI {
        // Streaming updates
        static let streamingUIUpdateInterval: TimeInterval = 0.05 // 50ms for smooth token-by-token rendering
        static let streamingProgressLogInterval = 50 // Log every N characters
        static let streamingPersistInterval = 100 // Persist every N characters
        
        // Animation durations
        static let defaultAnimationDuration: TimeInterval = 0.3
        static let scrollAnimationDuration: TimeInterval = 0.5
        static let springAnimationResponse: Double = 0.4
        static let springAnimationDamping: Double = 0.8
        
        // UI Thresholds
        static let scrollToBottomThreshold: CGFloat = 100
        static let previewMaxLength = 50
        static let titleWordLimit = 4
        
        // Input constraints
        static let messageLineLimit = 6
        static let inputCornerRadius: CGFloat = 22
        static let inputPadding: CGFloat = 16
        static let buttonSize: CGFloat = 44
    }
    
    // MARK: - Data Management
    enum Data {
        // UserDefaults keys
        static let conversationsKey = "SavedConversations"
        static let currentConversationKey = "CurrentConversationID"
        static let legacyMessagesKey = "SavedMessages"
        
        // Validation limits
        static let maxConversationTitleLength = 100
        static let maxMessageContentLength = 100000
        
        // Default values
        static let newChatTitle = "New Chat"
        static let importedChatTitle = "Imported Chat"
        static let noMessagesPreview = "No messages"
    }
    
    // MARK: - Security
    enum Security {
        // API Key validation patterns
        static let anthropicKeyPrefix = "sk-ant-"
        static let openaiKeyPrefix = "sk-"
        
        // Keychain configuration
        static let legacyKeychainService = "com.localllm.apikeys"
        static let configurationKey = "APIConfiguration"
        static let providerConfigurationsKey = "ProviderConfigurations"
    }
    
    // MARK: - Export
    enum Export {
        static let pdfMargin: Float = 50.0
        static let pdfFontSize: Float = 12.0
        static let pdfLineSpacing: Float = 1.2
        
        static let tempFileExtensions = ["pdf", "md", "txt"]
    }
    
    // MARK: - Local Models (GGUF)
    enum LocalModels {
        // Storage paths
        static let modelsDirectoryName = "Models"
        
        // UserDefaults keys
        static let downloadedModelsKey = "DownloadedLocalModels"
        static let selectedLocalModelKey = "SelectedLocalModel"
        
        // Hugging Face API
        static let huggingFaceBaseURL = "https://huggingface.co"
        static let huggingFaceAPIURL = "https://huggingface.co/api/models"
        
        // Download configuration
        static let downloadChunkSize = 1024 * 1024 // 1 MB chunks
        static let downloadTimeoutInterval: TimeInterval = 300 // 5 minutes
        
        // Model loading
        static let modelLoadTimeoutSeconds: TimeInterval = 120
        static let defaultMaxTokens = 2048
        static let defaultTemperature: Float = 0.7
        
        // Context window cap for mobile devices
        // Full context (32K+) would use too much RAM for the KV cache
        // 4096 tokens is a balance for mobile devices
        static let maxMobileContextTokens = 4096
    }
}

// MARK: - String Constants

enum StringConstants {
    enum Errors {
        static let configurationRequired = "Please configure your API settings first"
        static let networkError = "Network error occurred"
        static let streamingError = "Streaming error: "
        static let exportError = "Failed to export"
        static let fileWriteError = "Failed to save file"
        static let unexpectedError = "An unexpected error occurred: "
        
        // Local model errors
        static let modelNotDownloaded = "Please download a local model first"
        static let modelLoadFailed = "Failed to load the model"
        static let insufficientMemory = "Insufficient memory to run this model"
        static let downloadFailed = "Failed to download the model"
    }
    
    enum Messages {
        static let connectionSuccessTest = "Hello! Please respond with 'Connection successful' if you receive this."
        static let streamingCompleted = "Streaming completed"
        static let codeCopied = "Code copied!"
        
        // Local model messages
        static let modelDownloading = "Downloading model..."
        static let modelDownloadComplete = "Model downloaded successfully"
        static let modelLoading = "Loading model..."
        static let modelReady = "Model ready"
    }
    
    enum UI {
        static let welcomeTitle = "Welcome to Dualo"
        static let welcomeSubtitle = "Your dual AI companion"
        static let getStartedPrompt = "Type a message below to get started"
        static let messagePlaceholder = "Message"
        static let renameChatTitle = "Rename Chat"
        static let renameChatMessage = "Enter a new title for this chat"
        static let exportErrorTitle = "Export Error"
        static let optionsAccessibility = "Options"
        
        // Local models UI
        static let localModelsTitle = "Local Models"
        static let manageModels = "Manage Models"
        static let downloadButton = "Download"
        static let deleteButton = "Delete"
        static let recommendedBadge = "Recommended"
        static let storageUsed = "Storage Used"
        static let noModelsDownloaded = "No models downloaded"
    }
}

// MARK: - SystemImages Constants

enum SystemImages {
    // Navigation and UI
    static let ellipsisCircle = "ellipsis.circle"
    static let pencil = "pencil"
    static let cpu = "cpu"
    static let arrowUp = "arrow.up.circle.fill"
    static let arrowDown = "arrow.down"
    static let stopFill = "stop.fill"
    static let plus = "plus"
    static let checkmark = "checkmark"
    
    // Content types
    static let brainProfile = "brain.head.profile"
    static let sparkles = "sparkles"
    static let message = "message"
    static let lockShield = "lock.shield"
    
    // Export formats
    static let docRichtext = "doc.richtext"
    static let docText = "doc.text"
    static let docPlaintext = "doc.plaintext"
    
    // Actions
    static let copyIcon = "doc.on.doc"
    
    // Local models
    static let desktopComputer = "desktopcomputer"
    static let iphone = "iphone"
    static let cloudFill = "cloud.fill"
    static let squareAndArrowDown = "square.and.arrow.down"
    static let trash = "trash"
    static let internaldrive = "internaldrive"
    static let exclamationmarkTriangle = "exclamationmark.triangle"
    static let checkmarkCircleFill = "checkmark.circle.fill"
    static let xmarkCircleFill = "xmark.circle.fill"
    static let arrowDownCircle = "arrow.down.circle"
}