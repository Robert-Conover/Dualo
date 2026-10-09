//
//  ChatViewModelTests.swift
//  DualoTests
//
//  Drives ChatViewModel's send/stream/stop/retry/edit/regenerate flow against fake services.
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

    /// The title the "model" writes, and what happens while it does
    var title: String?
    var whileNaming: () -> Void = {}
    private(set) var titleRequests: [String] = []

    func suggestTitle(forChatStartingWith message: String, config: APIConfiguration) async -> String? {
        titleRequests.append(message)
        await Task.yield()
        whileNaming()
        return title
    }
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

    // MARK: - Editing and regenerating

    /// Sends `text` and streams `reply` back to completion.
    private func exchange(_ text: String, reply: String) async {
        await send { await viewModel.sendMessage(text) }
        api.yield(reply)
        api.finish()
        await waitUntil { !viewModel.isStreaming }
    }

    @Test func editingResendsTheLastMessageInPlaceOfTheOriginal() async throws {
        await exchange("Hi", reply: "Hello")
        let original = try #require(newMessages.first)

        #expect(viewModel.beginEditing(original.id) == "Hi")
        #expect(viewModel.editingMessageId == original.id)
        await exchange("Hey", reply: "Hello again")

        #expect(api.requests.last?.text == "Hey")
        #expect(api.requests.last?.history.map(\.content) == ["Earlier question", "Earlier answer"])
        #expect(newMessages.map(\.content) == ["Hey", "Hello again"])
        #expect(newMessages.first?.sendStatus == .sent)
        #expect(viewModel.editingMessageId == nil)
    }

    @Test func onlyTheLastUserMessageCanBeEdited() async {
        await exchange("Hi", reply: "Hello")

        #expect(viewModel.beginEditing(viewModel.messages[0].id) == nil)
        #expect(viewModel.editingMessageId == nil)
    }

    @Test func cancelledEditSendsANewMessage() async throws {
        await exchange("Hi", reply: "Hello")
        _ = viewModel.beginEditing(try #require(newMessages.first?.id))
        viewModel.cancelEditing()
        await exchange("Hey", reply: "Hello again")

        #expect(newMessages.map(\.content) == ["Hi", "Hello", "Hey", "Hello again"])
    }

    @Test func regeneratingReplacesTheLastReply() async throws {
        let replyId = try #require(viewModel.regenerableMessageId)
        #expect(replyId == viewModel.messages[1].id)

        await send { await viewModel.regenerateReply(replyId) }
        api.yield("A fresh answer")
        api.finish()
        await waitUntil { !viewModel.isStreaming }

        #expect(api.requests.last?.text == "Earlier question")
        #expect(api.requests.last?.history.isEmpty == true)
        #expect(viewModel.messages.map(\.content) == ["Earlier question", "A fresh answer"])
        #expect(viewModel.messages.first?.sendStatus == .sent)
        #expect(tracker.lastMessages.last?.content == "A fresh answer")
    }

    @Test func failedRegenerationCanBeRetried() async throws {
        let replyId = try #require(viewModel.regenerableMessageId)
        await send { await viewModel.regenerateReply(replyId) }
        api.finish(throwing: NetworkError.networkUnavailable)
        await waitUntil { !viewModel.isStreaming }

        #expect(viewModel.messages.map(\.content) == ["Earlier question"])
        #expect(viewModel.messages.first?.sendStatus == .failed)
    }

    @Test func nothingCanBeEditedOrRegeneratedWhileAReplyStreams() async {
        await send { await viewModel.sendMessage("Hi") }

        #expect(viewModel.editableMessageId == nil)
        #expect(viewModel.regenerableMessageId == nil)
        #expect(viewModel.beginEditing(newMessages[0].id) == nil)
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

    @Test func editedMessageKeepsItsImages() async throws {
        viewModel.pendingAttachments = [testImage]
        await exchange("What is this?", reply: "A red square")
        _ = viewModel.beginEditing(try #require(newMessages.first?.id))
        await exchange("What colour is this?", reply: "Red")

        #expect(api.requests.last?.attachments.count == 1)
        #expect(newMessages.map(\.content) == ["What colour is this?", "Red"])
        #expect(newMessages.first?.attachments.count == 1)
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

// MARK: - Chats named by the model

@MainActor
struct ChatNamingTests {
    private let api = FakeAPIService()
    private let manager: FakeConversationManager
    private let viewModel: ChatViewModel

    init() {
        let conversation = Conversation(provider: .local, model: "Qwen3.5-0.8B-Q4_K_M")
        manager = FakeConversationManager(conversation)
        viewModel = ChatViewModel(apiService: api, conversationManager: manager, contextTracker: FakeContextTracker())
        viewModel.loadConversation(conversation)
        viewModel.apiConfiguration = APIConfiguration(provider: .local, apiKey: "", model: "Qwen3.5-0.8B-Q4_K_M")
        api.title = "Trip to Japan"
    }

    private var title: String? { manager.conversations.first?.title }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 where !condition() {
            await Task.yield()
        }
    }

    /// Sends `text`, has the model reply, and gives it a chance to name the chat
    private func exchange(_ text: String) async {
        let requestCount = api.requests.count
        await viewModel.sendMessage(text)
        await waitUntil { api.requests.count > requestCount }
        api.yield("Sure")
        api.finish()
        await waitUntil { !viewModel.isStreaming }
        for _ in 0..<20 { await Task.yield() }
    }

    @Test func localModelNamesTheChatAfterItsFirstReply() async {
        await exchange("Plan a week in Japan for me please")

        #expect(api.titleRequests == ["Plan a week in Japan for me please"])
        #expect(title == "Trip to Japan")
    }

    @Test func cloudChatKeepsTheTitleFromItsFirstWords() async {
        viewModel.apiConfiguration = APIConfiguration(provider: .openai, apiKey: "sk-test", model: "gpt-6.1-sol")
        await exchange("Plan a week in Japan for me please")

        #expect(api.titleRequests.isEmpty)
        #expect(title == "Plan a week in")
    }

    @Test func chatRenamedWhileTheModelNamesItKeepsTheNewName() async {
        api.whileNaming = { [manager] in
            manager.conversations[0].title = "Japan"
        }
        await exchange("Plan a week in Japan for me please")

        #expect(title == "Japan")
    }

    @Test func modelIsAskedToNameAChatOnce() async {
        api.title = nil
        await exchange("Plan a week in Japan for me please")
        await exchange("Make it two weeks")

        #expect(api.titleRequests.count == 1)
        #expect(title == "Plan a week in")
    }

    @Test func stoppedReplyDoesntNameTheChat() async {
        let requestCount = api.requests.count
        await viewModel.sendMessage("Plan a week in Japan for me please")
        await waitUntil { api.requests.count > requestCount }
        api.yield("Sure")
        await waitUntil { viewModel.messages.first?.sendStatus == .sent }
        viewModel.stopStreaming()
        for _ in 0..<20 { await Task.yield() }

        #expect(api.titleRequests.isEmpty)
    }
}

// MARK: - Conversation titles

struct ConversationTruncationTests {
    @Test func removingTheFirstMessageLetsTheNextOneNameTheChat() {
        var conversation = Conversation(provider: .openai, model: "gpt-6.1-sol")
        conversation.addMessage(Message(role: Message.Role.user, content: "Plan a trip"))
        conversation.addMessage(Message(role: Message.Role.assistant, content: "Sure"))

        conversation.removeMessages(from: 0)
        conversation.addMessage(Message(role: Message.Role.user, content: "Fix my code"))

        #expect(conversation.title == "Fix my code")
        #expect(conversation.messages.map(\.content) == ["Fix my code"])
    }

    @Test func aRenamedChatKeepsItsTitle() {
        var conversation = Conversation(provider: .openai, model: "gpt-6.1-sol")
        conversation.addMessage(Message(role: Message.Role.user, content: "Plan a trip"))
        conversation.title = "Japan"

        conversation.removeMessages(from: 0)

        #expect(conversation.title == "Japan")
    }

    @Test func onlyTitlesTheAppMadeCanBeReplaced() {
        var conversation = Conversation(provider: .local, model: "Qwen3.5-0.8B-Q4_K_M")
        #expect(conversation.hasPlaceholderTitle)
        conversation.addMessage(Message(role: Message.Role.user, content: "Plan a week in Japan"))
        #expect(conversation.hasPlaceholderTitle)

        conversation.title = "Trip to Japan"
        #expect(!conversation.hasPlaceholderTitle)
    }

    @Test func removingLaterMessagesKeepsTheTitle() {
        var conversation = Conversation(provider: .openai, model: "gpt-6.1-sol")
        conversation.addMessage(Message(role: Message.Role.user, content: "Plan a trip"))
        conversation.addMessage(Message(role: Message.Role.assistant, content: "Sure"))

        conversation.removeMessages(from: 1)

        #expect(conversation.title == "Plan a trip")
        #expect(conversation.messages.map(\.content) == ["Plan a trip"])
    }
}
