//
//  ServiceProtocols.swift
//  Dualo
//
//  Protocol definitions for all services to enable dependency injection and testing.
//

import Foundation

// MARK: - Conversation Managing Protocol

/// Protocol for conversation persistence and management
@MainActor
protocol ConversationManaging: AnyObject {
    var conversations: [Conversation] { get }
    var currentConversation: Conversation? { get set }
    var isLoading: Bool { get }
    var pendingChatData: PendingChatData? { get set }

    func createNewConversation() -> Conversation
    func selectConversation(_ conversation: Conversation)
    func updateConversation(_ conversation: Conversation, moveToTop: Bool)
    func deleteConversation(_ conversation: Conversation)
    func clearAllConversations()
}

// MARK: - Keychain Servicing Protocol

/// Protocol for secure credential storage
protocol KeychainServicing {
    func saveAPIConfiguration(_ config: APIConfiguration) throws
    func loadAPIConfiguration() throws -> APIConfiguration?
    func deleteAPIConfiguration() throws
    func saveProviderConfigurations(_ configs: ProviderConfigurations) throws
    func loadProviderConfigurations() throws -> ProviderConfigurations?
}

// MARK: - GGUF Servicing Protocol

/// Protocol for local LLM inference
@MainActor
protocol GGUFServicing: AnyObject {
    var isModelLoaded: Bool { get }
    var isLoading: Bool { get }
    var isGenerating: Bool { get }
    var loadedModelId: String? { get }
    var errorMessage: String? { get }
    var lastGenerationStats: GenerationStats? { get }
    var currentTokenCount: Int { get }

    func loadModel(modelId: String) async throws
    func unloadModel()
    func streamMessage(_ message: String, history: [Message], conversationId: UUID) -> AsyncThrowingStream<String, Error>
    func sendMessage(_ message: String, history: [Message], conversationId: UUID) async throws -> String
    func stopGeneration()
    func clearConversationContext()
    func autoLoadLastModel() async
}

// MARK: - Local Model Managing Protocol

/// Protocol for local model download and storage management
@MainActor
protocol LocalModelManaging: AnyObject {
    var availableModels: [LocalModel] { get }
    var downloadedModels: [LocalModel] { get }
    var downloadProgress: [String: Double] { get }
    var isDownloading: Bool { get }
    var currentDownloadingModelId: String? { get }
    var errorMessage: String? { get }
    var selectedModelId: String? { get set }
    var selectedModel: LocalModel? { get }
    var formattedStorageUsed: String { get }
    var formattedAvailableStorage: String { get }

    func getModelLocalPath(_ modelId: String) -> URL?
    func downloadModel(_ model: LocalModel) async throws
    func cancelDownload(_ modelId: String)
    func deleteModel(_ model: LocalModel) throws
    func importModel(from sourceURL: URL) throws -> LocalModel
    func calculateStorageUsed() -> Int64
    func getModelSizeString(_ model: LocalModel) -> String
}

// MARK: - Context Tracking Protocol

/// Protocol for tracking context window usage
@MainActor
protocol ContextTracking: AnyObject {
    var estimatedTokens: Int { get }
    var contextLimit: Int { get }
    var currentProvider: APIProvider { get }
    var currentModel: String { get }
    var usageInfo: ContextUsageInfo { get }
    var usagePercentage: Double { get }
    var isNearLimit: Bool { get }
    var isAtLimit: Bool { get }

    func configure(model: String, provider: APIProvider, localModelManager: LocalModelManager?)
    func updateFromMessages(_ messages: [Message])
    func addStreamingTokens(_ count: Int)
    func reset()
    func estimateTokens(for text: String) -> Int
}
