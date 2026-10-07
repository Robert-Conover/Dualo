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
        print("[GGUF test] \(message) -> \(text.count) chars: \(text.prefix(400))")
        return text
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
        let chat = UUID()
        _ = try await reply(to: "My favorite color is teal. Just say OK.", in: chat)
        let reply = try await reply(to: "What is my favorite color? Answer in one word.", in: chat)

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
        let reply = try await reply(to: "Say the word banana.", in: UUID())
        #expect(answer(reply).lowercased().contains("banana"), "Reply: \(reply)")
        #expect(Date().timeIntervalSince(start) < 30, "The stopped story seems to have kept generating")
        #expect(!service.isGenerating)
    }
}
