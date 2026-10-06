//
//  ServiceProtocols.swift
//  Dualo
//
//  Protocols for the services ChatViewModel depends on, so tests can inject fakes.
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
