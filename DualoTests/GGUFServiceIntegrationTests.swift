//
//  GGUFServiceIntegrationTests.swift
//  DualoTests
//
//  Runs a real local model through GGUFService. Skipped unless Qwen3.5 0.8B is in the
//  app's Documents/Models folder; to run them, copy Qwen3.5-0.8B-Q4_K_M.gguf from
//  unsloth/Qwen3.5-0.8B-GGUF there (on a simulator, via `xcrun simctl get_app_container`)
//  and test with `-parallel-testing-enabled NO` so the tests run on that simulator.
//

import Foundation
import Testing
@testable import Dualo

@MainActor
private enum TestModel {
    static let id = "qwen3.5-0.8b-q4"

    static var isDownloaded: Bool {
        LocalModelManager.shared.availableModels.contains { $0.id == id && $0.downloadState.isDownloaded }
    }

    static func load() async throws {
        let service = GGUFService.shared
        if service.loadedModelId != id {
            try await service.loadModel(modelId: id)
        }
    }
}

@MainActor
@Suite(.serialized, .timeLimit(.minutes(3)), .enabled("Needs Qwen3.5 0.8B in Documents/Models") { await TestModel.isDownloaded })
struct GGUFServiceIntegrationTests {

    private let service = GGUFService.shared

    init() async throws {
        try await TestModel.load()
        // Instructions left in the app's settings (say, by an interrupted UI test) change
        // every reply. They're cleared here and set only by the test that needs them.
        UserDefaults.standard.removeObject(forKey: CustomInstructions.key)
        // Sampled replies vary from run to run; the most likely reply doesn't
        service.useGreedySampling()
    }

    /// The reply with any <think> block removed, as it would be stored in history.
    private func answer(_ reply: String) -> String {
        GGUFService.stripThinkingBlocks(from: reply)
    }

    private func reply(to message: String, history: [Message] = [], in conversation: UUID) async throws -> String {
        var text = ""
        for try await chunk in service.streamMessage(message, history: history, conversationId: conversation) {
            text += chunk
        }
        print("[GGUF test] \(message.prefix(80)) -> \(text.count) chars: \(text.prefix(400))")
        return text
    }

    /// Sends `message` in `chat` with its history, like the app, and adds the turn to it.
    private func send(_ message: String, in chat: inout TestChat) async throws -> String {
        let reply = try await reply(to: message, history: chat.messages, in: chat.id)
        chat.messages.append(Message(role: Message.Role.user, content: message))
        chat.messages.append(Message(role: Message.Role.assistant, content: reply))
        return reply
    }

    /// A chat about something else, long enough to fill a good share of the model's context.
    private func fillerMessages(exchanges: Int) -> [Message] {
        let note = String(repeating: "The tide came in slowly over the grey stones near the old pier. ", count: 12)
        return (1...exchanges).flatMap { day in
            [Message(role: Message.Role.user, content: "Diary entry for day \(day): \(note) Just say OK."),
             Message(role: Message.Role.assistant, content: "OK.")]
        }
    }

    @Test func answersAQuestion() async throws {
        let reply = try await reply(to: "What is 2+2? Reply with just the number.", in: UUID())

        #expect(answer(reply).contains("4"), "Reply: \(reply)")
        if reply.contains("<think>") {
            #expect(reply.contains("</think>"), "Thinking block never closed: \(reply)")
        }
        #expect(!reply.contains("<|im_end|>") && !reply.contains("<|im_start|>"), "Template tokens leaked: \(reply)")
        #expect(!service.isGenerating)
    }

    @Test func remembersEarlierTurnsInTheSameChat() async throws {
        var chat = TestChat()
        _ = try await send("My favorite color is teal. Just say OK.", in: &chat)
        let reply = try await send("What is my favorite color? Answer in one word.", in: &chat)

        #expect(answer(reply).lowercased().contains("teal"), "Reply: \(reply)")
    }

    @Test func switchingChatsLoadsThatChatsHistory() async throws {
        _ = try await reply(to: "Say hi.", in: UUID())

        let history = [
            Message(role: Message.Role.user, content: "My name is Zorblax. Just say OK."),
            Message(role: Message.Role.assistant, content: "OK.")
        ]
        let reply = try await reply(to: "What is my name? Answer in one word.", history: history, in: UUID())

        #expect(answer(reply).contains("Zorblax"), "Reply: \(reply)")
    }

    @Test func forgetsTurnsTheAppRemoved() async throws {
        var chat = TestChat()
        _ = try await send("My name is Zorblax. Just say OK.", in: &chat)

        // The app dropped that exchange (an edited message or regenerated reply)
        chat.messages.removeAll()
        let reply = try await send("What is my name? Answer in one word.", in: &chat)

        #expect(!answer(reply).contains("Zorblax"), "Reply: \(reply)")
    }

    @Test func longChatForgetsItsOldestMessages() async throws {
        var chat = TestChat()
        chat.messages = [
            Message(role: Message.Role.user, content: "My name is Zorblax. Just say OK."),
            Message(role: Message.Role.assistant, content: "OK.")
        ] + fillerMessages(exchanges: 30)

        let reply = try await send("What is my name? Answer in one word.", in: &chat)

        #expect(!answer(reply).contains("Zorblax"), "Reply: \(reply)")
        let memory = try #require(service.memory)
        #expect(memory.conversationId == chat.id)
        #expect(memory.forgetsMessages)
        #expect(memory.usedTokens <= memory.availableTokens)
        // The name and its reply are gone, along with the oldest diary entries
        let forgotten = try #require(chat.messages.firstIndex { $0.id == memory.lastForgottenMessageId })
        #expect(forgotten >= 1 && forgotten < chat.messages.count - 4)
    }

    @Test func longChatRemembersItsNewestMessages() async throws {
        var chat = TestChat()
        chat.messages = fillerMessages(exchanges: 30) + [
            Message(role: Message.Role.user, content: "My name is Zorblax. Just say OK."),
            Message(role: Message.Role.assistant, content: "OK.")
        ]

        let reply = try await send("What is my name? Answer in one word.", in: &chat)

        #expect(answer(reply).contains("Zorblax"), "Reply: \(reply)")
        #expect(service.memory?.forgetsMessages == true)
    }

    @Test func messageTooLongForTheModelIsAnError() async throws {
        let message = String(repeating: "The tide came in slowly over the grey stones. ", count: 500)

        await #expect(throws: GGUFServiceError.self) {
            _ = try await reply(to: message, in: UUID())
        }
        #expect(!service.isGenerating)
    }

    @Test func shortChatForgetsNothing() async throws {
        let chat = UUID()
        let messages = [
            Message(role: Message.Role.user, content: "Hi"),
            Message(role: Message.Role.assistant, content: "Hello!")
        ]

        await service.refreshMemory(of: messages, conversationId: chat)

        let memory = try #require(service.memory)
        #expect(memory.conversationId == chat)
        #expect(!memory.forgetsMessages)
        #expect(memory.usedTokens > 0 && memory.usedTokens < memory.availableTokens / 4)
    }

    /// Tokens the model had to read for the last message; the rest came from its cache
    private func lastReadTokenCount() async throws -> Int {
        await (try #require(service.llm)).core.lastReadTokenCount
    }

    @Test func nextMessageReadsOnlyWhatsNew() async throws {
        var chat = TestChat()
        chat.messages = fillerMessages(exchanges: 3)
        _ = try await send("My name is Zorblax. Just say OK.", in: &chat)
        #expect(try await lastReadTokenCount() > 400)

        let reply = try await send("What is my name? Answer in one word.", in: &chat)

        // The last reply and the new message, not the diary entries before them
        #expect(try await lastReadTokenCount() < 100)
        #expect(answer(reply).contains("Zorblax"), "Reply: \(reply)")
    }

    @Test func fullChatKeepsWhereItStartsForTheNextMessages() async throws {
        var chat = TestChat()
        chat.messages = fillerMessages(exchanges: 30)
        _ = try await send("My name is Zorblax. Just say OK.", in: &chat)
        let firstForgotten = try #require(service.memory?.lastForgottenMessageId)

        _ = try await send("What is my name? Answer in one word.", in: &chat)

        #expect(service.memory?.lastForgottenMessageId == firstForgotten)
        #expect(try await lastReadTokenCount() < 100)
    }

    @Test func regeneratingOrEditingReadsOnlyTheLastMessage() async throws {
        var chat = TestChat()
        chat.messages = fillerMessages(exchanges: 3)
        _ = try await send("My name is Zorblax. Just say OK.", in: &chat)
        let earlier = Array(chat.messages.dropLast(2))

        _ = try await reply(to: "My name is Zorblax. Just say OK.", history: earlier, in: chat.id)
        #expect(try await lastReadTokenCount() < 20)

        let edited = try await reply(to: "My name is Quillon. What is my name? Answer in one word.", history: earlier, in: chat.id)
        #expect(try await lastReadTokenCount() < 40)
        #expect(answer(edited).contains("Quillon"), "Reply: \(edited)")
    }

    @Test func replyFromTheCacheMatchesOneReadFromScratch() async throws {
        var chat = TestChat()
        _ = try await send("My name is Zorblax. Just say OK.", in: &chat)
        _ = try await send("My favorite color is teal. Just say OK.", in: &chat)
        let question = "What are my name and favorite color?"

        let fromCache = try await reply(to: question, history: chat.messages, in: chat.id)
        let readFromCache = try await lastReadTokenCount()
        service.clearConversationContext()
        let fromScratch = try await reply(to: question, history: chat.messages, in: chat.id)
        let readFromScratch = try await lastReadTokenCount()

        #expect(fromCache == fromScratch)
        // Only the last reply and the question, not the first exchange too
        #expect(readFromCache < readFromScratch / 2, "Read \(readFromCache) of \(readFromScratch) tokens")
    }

    @Test func switchingBackToAChatReadsOnlyWhatsNew() async throws {
        var chat = TestChat()
        chat.messages = fillerMessages(exchanges: 3)
        _ = try await send("My name is Zorblax. Just say OK.", in: &chat)
        _ = try await reply(to: "Say hi.", in: UUID())
        let question = "What is my name? Answer in one word."

        let fromSaved = try await reply(to: question, history: chat.messages, in: chat.id)
        let readFromSaved = try await lastReadTokenCount()
        service.clearConversationContext()
        let fromScratch = try await reply(to: question, history: chat.messages, in: chat.id)

        #expect(readFromSaved < 100, "Read \(readFromSaved) tokens")
        #expect(fromSaved == fromScratch)
        #expect(answer(fromSaved).contains("Zorblax"), "Reply: \(fromSaved)")
    }

    @Test func chatPicksUpWhereItLeftOffAfterTheAppRelaunches() async throws {
        var chat = TestChat()
        chat.messages = fillerMessages(exchanges: 3)
        _ = try await send("My name is Zorblax. Just say OK.", in: &chat)

        // Like the app going to the background, then being closed and opened again
        await service.saveChatMemory()
        service.unloadModel()
        try await TestModel.load()
        service.useGreedySampling()
        let reply = try await send("What is my name? Answer in one word.", in: &chat)

        #expect(try await lastReadTokenCount() < 100)
        #expect(answer(reply).contains("Zorblax"), "Reply: \(reply)")
    }

    @Test func fullChatKeepsWhereItStartsAfterSwitchingBack() async throws {
        var chat = TestChat()
        chat.messages = fillerMessages(exchanges: 30)
        _ = try await send("My name is Zorblax. Just say OK.", in: &chat)
        let firstForgotten = try #require(service.memory?.lastForgottenMessageId)
        _ = try await reply(to: "Say hi.", in: UUID())

        // Opening the chat again shows the divider where it was
        await service.refreshMemory(of: chat.messages, conversationId: chat.id)
        #expect(service.memory?.lastForgottenMessageId == firstForgotten)
        _ = try await send("What is my name? Answer in one word.", in: &chat)

        #expect(service.memory?.lastForgottenMessageId == firstForgotten)
        #expect(try await lastReadTokenCount() < 100)
    }

    @Test(arguments: [
        ("Can you help me plan a week in Japan?", ["Japan"]),
        ("How do I reverse a string in Python?", ["Python"]),
        ("Write me a short poem about the ocean.", ["Ocean"]),
        ("What's the difference between a virus and bacteria?", ["Virus", "Bacteria"]),
        ("Tell me a joke about cats.", ["Cat"]),
    ])
    func modelNamesAChat(message: String, topics: [String]) async throws {
        let title = try #require(await service.suggestTitle(forChatStartingWith: message))
        print("[GGUF test] Title for \(message) -> \(title)")

        #expect(topics.contains { title.localizedCaseInsensitiveContains($0) }, "Title: \(title)")
    }

    @Test func namingAChatDoesntMakeItsNextMessageReadMore() async throws {
        func readForSecondMessage(naming: Bool) async throws -> Int {
            var chat = TestChat()
            _ = try await send("My name is Zorblax. Just say OK.", in: &chat)
            if naming {
                _ = try #require(await service.suggestTitle(forChatStartingWith: chat.messages[0].content))
            }
            let reply = try await send("What is my name? Answer in one word.", in: &chat)
            #expect(answer(reply).contains("Zorblax"), "Reply: \(reply)")
            return try await lastReadTokenCount()
        }

        let named = try await readForSecondMessage(naming: true)
        let unnamed = try await readForSecondMessage(naming: false)

        #expect(named == unnamed, "Read \(named) tokens after naming, \(unnamed) without")
    }

    @Test func instructionsChangedMidChatApplyToTheNextReply() async throws {
        var chat = TestChat()
        _ = try await send("Say hi.", in: &chat)

        UserDefaults.standard.set("Your name is Zorblax.", forKey: CustomInstructions.key)
        defer { UserDefaults.standard.removeObject(forKey: CustomInstructions.key) }
        let reply = try await send("What is your name? Answer in one word.", in: &chat)

        #expect(answer(reply).contains("Zorblax"), "Reply: \(reply)")
    }

    @Test func stoppingMidReplyFreesTheModelForTheNextMessage() async throws {
        var chunks = 0
        for try await _ in service.streamMessage("Write a very long story about a dragon.", history: [], conversationId: UUID()) {
            chunks += 1
            if chunks == 20 { break } // Like tapping Stop
        }
        #expect(chunks == 20)

        // Each reply waits for the previous one to wind down, so this only comes back
        // quickly if the story really stopped (finishing it takes minutes here)
        let start = Date()
        let reply = try await reply(to: "What is 2+2? Reply with just the number.", in: UUID())
        #expect(answer(reply).contains("4"), "Reply: \(reply)")
        #expect(Date().timeIntervalSince(start) < 30, "The stopped story seems to have kept generating")
        #expect(!service.isGenerating)
    }
}

/// A chat's id and messages, kept the way the app keeps them.
private struct TestChat {
    let id = UUID()
    var messages: [Message] = []
}
