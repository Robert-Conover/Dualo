//
//  ChatViewModelTests.swift
//  DualoTests
//
//  Drives ChatViewModel's send/stream/stop/retry flow against fake services.
//

import Foundation
import UIKit
import Testing
@testable import Dualo

// MARK: - Fakes

@MainActor
private final class FakeAPIService: APIServiceProtocol {
    private(set) var requests: [(text: String, history: [Message], attachments: [MessageAttachment])] = []
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?

    func yield(_ chunk: String) { continuation?.yield(chunk) }
    func finish(throwing error: Error? = nil) { continuation?.finish(throwing: error) }

    func sendMessage(_ message: String, history: [Message], config: APIConfiguration, attachments: [MessageAttachment], conversationId: UUID?) async throws -> String {
        ""
    }

    func streamMessage(_ message: String, history: [Message], config: APIConfiguration, attachments: [MessageAttachment], conversationId: UUID?) -> AsyncThrowingStream<String, Error> {
        requests.append((message, history, attachments))
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        self.continuation = continuation
        return stream
    }

    func fetchAvailableModels(for provider: APIProvider, apiKey: String) async throws -> [String] { [] }

    func stopStreaming() { continuation?.finish() }
}

@MainActor
private final class FakeConversationManager: ConversationManaging {
    var conversations: [Conversation]
    var currentConversation: Conversation?
    var isLoading = false
    var pendingChatData: PendingChatData?

    init(_ conversation: Conversation) {
        conversations = [conversation]
    }

    func createNewConversation() -> Conversation { Conversation(provider: .openai, model: "gpt-6.1-sol") }
    func selectConversation(_ conversation: Conversation) { currentConversation = conversation }
    func updateConversation(_ conversation: Conversation, moveToTop: Bool) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        }
    }
    func deleteConversation(_ conversation: Conversation) {}
    func clearAllConversations() {}
}

@MainActor
private final class FakeContextTracker: ContextTracking {
    var estimatedTokens = 0
    var contextLimit = 128_000
    var currentProvider: APIProvider = .openai
    var currentModel = ""
    var usageInfo: ContextUsageInfo {
        ContextUsageInfo(estimatedTokens: estimatedTokens, contextLimit: contextLimit, provider: currentProvider, modelName: currentModel)
    }
    var usagePercentage: Double { 0 }
    var isNearLimit: Bool { false }
    var isAtLimit: Bool { false }
    private(set) var lastMessages: [Message] = []

    func configure(model: String, provider: APIProvider, localModelManager: LocalModelManager?) {}
    func updateFromMessages(_ messages: [Message]) { lastMessages = messages }
    func addStreamingTokens(_ count: Int) {}
    func reset() {}
    func estimateTokens(for text: String) -> Int { text.count / 4 }
}

// MARK: - Tests

@MainActor
struct ChatViewModelTests {
    private let api = FakeAPIService()
    private let manager: FakeConversationManager
    private let tracker = FakeContextTracker()
    private let viewModel: ChatViewModel

    init() {
        let existing = [
            Message(role: Message.Role.user, content: "Earlier question"),
            Message(role: Message.Role.assistant, content: "Earlier answer")
        ]
        let conversation = Conversation(title: "Test", messages: existing, provider: .openai, model: "gpt-6.1-sol")
        manager = FakeConversationManager(conversation)
        viewModel = ChatViewModel(apiService: api, conversationManager: manager, contextTracker: tracker)
        viewModel.loadConversation(conversation)
        viewModel.apiConfiguration = APIConfiguration(provider: .openai, apiKey: "sk-test", model: "gpt-6.1-sol")
    }

    /// Lets the streaming task run until `condition` holds.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 where !condition() {
            await Task.yield()
        }
        #expect(condition(), "Timed out waiting for streaming state")
    }

    /// Sends (or retries) and waits for the request to reach the fake API, so chunks
    /// the test yields afterwards land in the live stream.
    private func send(_ action: () async -> Void) async {
        let requestCount = api.requests.count
        await action()
        await waitUntil { api.requests.count > requestCount }
    }

    private var newMessages: [Message] { Array(viewModel.messages.dropFirst(2)) }

    @Test func streamedReplyFillsPlaceholderAndMarksUserMessageSent() async {
        await send { await viewModel.sendMessage("Hi") }
        #expect(newMessages.map(\.sendStatus) == [.sending, .sent])

        api.yield("Hel")
        api.yield("lo")
        api.finish()
        await waitUntil { !viewModel.isStreaming }

        #expect(newMessages.map(\.content) == ["Hi", "Hello"])
        #expect(newMessages.first?.sendStatus == .sent)
        #expect(viewModel.streamingMessageContent.isEmpty)
        #expect(tracker.lastMessages.last?.content == "Hello")
    }

    @Test func historyIsTheConversationBeforeTheNewMessage() async {
        await send { await viewModel.sendMessage("Hi") }

        #expect(api.requests.count == 1)
        #expect(api.requests.first?.text == "Hi")
        #expect(api.requests.first?.history.map(\.content) == ["Earlier question", "Earlier answer"])
    }

    @Test func streamErrorRemovesPlaceholderAndMarksUserMessageFailed() async {
        await send { await viewModel.sendMessage("Hi") }
        api.finish(throwing: NetworkError.invalidAPIKey)
        await waitUntil { !viewModel.isStreaming }

        #expect(newMessages.map(\.content) == ["Hi"])
        #expect(newMessages.first?.sendStatus == .failed)
        #expect(viewModel.showError)
    }

    @Test func stoppingBeforeAnyTokenCancelsAndRemovesPlaceholder() async {
        await viewModel.sendMessage("Hi")
        viewModel.stopStreaming()

        #expect(!viewModel.isStreaming)
        #expect(newMessages.map(\.content) == ["Hi"])
        #expect(newMessages.first?.sendStatus == .cancelled)
    }

    @Test func stoppingAfterTokensKeepsPartialReply() async {
        await send { await viewModel.sendMessage("Hi") }
        api.yield("Partial")
        await waitUntil { !viewModel.streamingMessageContent.isEmpty }
        viewModel.stopStreaming()

        #expect(newMessages.map(\.content) == ["Hi", "Partial"])
        #expect(newMessages.first?.sendStatus == .sent)
    }

    @Test func retryingFailedMessageStreamsAFreshReply() async throws {
        await send { await viewModel.sendMessage("Hi") }
        api.finish(throwing: NetworkError.invalidAPIKey)
        await waitUntil { !viewModel.isStreaming }
        let failedId = try #require(newMessages.first?.id)

        await send { await viewModel.retryMessage(failedId) }
        api.yield("Retried")
        api.finish()
        await waitUntil { !viewModel.isStreaming }

        #expect(api.requests.last?.text == "Hi")
        #expect(api.requests.last?.history.map(\.content) == ["Earlier question", "Earlier answer"])
        #expect(newMessages.map(\.content) == ["Hi", "Retried"])
        #expect(newMessages.first?.sendStatus == .sent)
        // Retries used to skip this; they now share the send path's completion.
        #expect(tracker.lastMessages.last?.content == "Retried")
    }

    @Test func retryIgnoresMessagesThatHaventFailed() async {
        let sentId = viewModel.messages[0].id
        await viewModel.retryMessage(sentId)
        #expect(api.requests.isEmpty)
    }

    @Test func missingAPIKeyShowsConfigurationErrorWithoutSending() async {
        viewModel.apiConfiguration = APIConfiguration(provider: .openai, apiKey: "", model: "gpt-6.1-sol")
        await viewModel.sendMessage("Hi")

        #expect(viewModel.showError)
        #expect(viewModel.errorMessage == StringConstants.Errors.configurationRequired)
        #expect(newMessages.isEmpty)
        #expect(api.requests.isEmpty)
    }

    // MARK: - Image attachments

    private var testImage: ImageAttachment {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        return ImageAttachment(image: image)
    }

    @Test func cloudModelSendsImages() async {
        viewModel.pendingAttachments = [testImage]
        await send { await viewModel.sendMessage("What is this?") }

        #expect(api.requests.last?.attachments.count == 1)
        #expect(newMessages.first?.attachments.count == 1)
    }

    @Test func localModelDropsImagesInsteadOfSendingThem() async {
        viewModel.apiConfiguration = APIConfiguration(provider: .local, apiKey: "", model: "Qwen3.5-0.8B-Q4_K_M")
        viewModel.pendingAttachments = [testImage]
        await send { await viewModel.sendMessage("What is this?") }

        #expect(api.requests.last?.attachments.isEmpty == true)
        #expect(newMessages.first?.attachments.isEmpty == true)
        #expect(viewModel.pendingAttachments.isEmpty)
    }

    @Test func localModelIgnoresImageOnlyMessage() async {
        viewModel.apiConfiguration = APIConfiguration(provider: .local, apiKey: "", model: "Qwen3.5-0.8B-Q4_K_M")
        viewModel.pendingAttachments = [testImage]
        await viewModel.sendMessage("")

        #expect(api.requests.isEmpty)
        #expect(newMessages.isEmpty)
        #expect(viewModel.pendingAttachments.isEmpty)
    }
}
