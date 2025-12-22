//
//  DependencyContainer.swift
//  Dualo
//
//  Centralized dependency container for dependency injection and testing.
//

import Foundation

/// Centralized container for managing service dependencies.
/// Enables dependency injection for testing while providing convenient defaults for production.
@MainActor
final class DependencyContainer: ObservableObject {
    /// Shared singleton instance for production use
    static let shared = DependencyContainer()

    // MARK: - Service Dependencies

    /// API service for cloud provider communication
    private(set) var apiService: APIServiceProtocol

    /// Conversation persistence manager
    private(set) var conversationManager: ConversationManaging

    /// Keychain service for secure credential storage
    private(set) var keychainService: KeychainServicing

    /// GGUF service for local model inference
    private(set) var ggufService: GGUFServicing

    /// Local model download and storage manager
    private(set) var localModelManager: LocalModelManaging

    /// Context window usage tracker
    private(set) var contextTracker: ContextTracking

    // MARK: - Initialization

    /// Initialize with default production dependencies
    private init() {
        self.apiService = APIService.shared
        self.conversationManager = ConversationManager.shared
        self.keychainService = KeychainService.shared
        self.ggufService = GGUFService.shared
        self.localModelManager = LocalModelManager.shared
        self.contextTracker = ContextTracker.shared
    }

    /// Initialize with custom dependencies (for testing)
    /// - Parameters:
    ///   - apiService: Custom API service implementation
    ///   - conversationManager: Custom conversation manager implementation
    ///   - keychainService: Custom keychain service implementation
    ///   - ggufService: Custom GGUF service implementation
    ///   - localModelManager: Custom local model manager implementation
    ///   - contextTracker: Custom context tracker implementation
    init(
        apiService: APIServiceProtocol,
        conversationManager: ConversationManaging,
        keychainService: KeychainServicing,
        ggufService: GGUFServicing,
        localModelManager: LocalModelManaging,
        contextTracker: ContextTracking
    ) {
        self.apiService = apiService
        self.conversationManager = conversationManager
        self.keychainService = keychainService
        self.ggufService = ggufService
        self.localModelManager = localModelManager
        self.contextTracker = contextTracker
    }

    // MARK: - Dependency Registration (for testing)

    /// Register a custom API service (useful for mocking in tests)
    func register(apiService: APIServiceProtocol) {
        self.apiService = apiService
    }

    /// Register a custom conversation manager (useful for mocking in tests)
    func register(conversationManager: ConversationManaging) {
        self.conversationManager = conversationManager
    }

    /// Register a custom keychain service (useful for mocking in tests)
    func register(keychainService: KeychainServicing) {
        self.keychainService = keychainService
    }

    /// Register a custom GGUF service (useful for mocking in tests)
    func register(ggufService: GGUFServicing) {
        self.ggufService = ggufService
    }

    /// Register a custom local model manager (useful for mocking in tests)
    func register(localModelManager: LocalModelManaging) {
        self.localModelManager = localModelManager
    }

    /// Register a custom context tracker (useful for mocking in tests)
    func register(contextTracker: ContextTracking) {
        self.contextTracker = contextTracker
    }

    // MARK: - Factory Methods

    /// Create a new ChatViewModel with injected dependencies
    /// - Returns: ChatViewModel configured with current container dependencies
    func makeChatViewModel() -> ChatViewModel {
        // For production, use the default init which uses singletons
        // For testing, use the custom init with injected dependencies
        ChatViewModel(
            apiService: apiService,
            conversationManager: conversationManager,
            contextTracker: contextTracker
        )
    }

    /// Create a new ChatViewModel with default production dependencies
    /// - Returns: ChatViewModel configured with production singletons
    func makeDefaultChatViewModel() -> ChatViewModel {
        ChatViewModel()
    }
}
