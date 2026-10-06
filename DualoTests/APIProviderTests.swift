//
//  APIProviderTests.swift
//  DualoTests
//
//  Covers moving saved chats and settings off retired OpenAI models.
//

import Foundation
import Testing
@testable import Dualo

struct APIProviderTests {

    @Test(arguments: APIProvider.openai.availableModels)
    func currentModelsAreKept(_ model: String) {
        #expect(APIProvider.sanitizedModel(model, for: .openai) == model)
    }

    @Test(arguments: [
        ("o4-mini", "gpt-6-luna"),
        ("gpt-5-mini", "gpt-6-luna"),
        ("gpt-5-nano", "gpt-6-luna"),
        ("o3", "gpt-6.1-sol"),
        ("gpt-5.2", "gpt-6.1-sol"),
        ("gpt-4.1", "gpt-6.1-sol")
    ])
    func retiredModelsMoveToClosestCurrentModel(_ old: String, _ replacement: String) {
        #expect(APIProvider.sanitizedModel(old, for: .openai) == replacement)
    }

    @Test func missingModelUsesDefault() {
        #expect(APIProvider.sanitizedModel(nil, for: .openai) == "gpt-6.1-sol")
        #expect(APIProvider.sanitizedModel("", for: .openai) == "gpt-6.1-sol")
    }

    @Test func savedConversationOnRetiredModelLoadsOnReplacement() throws {
        let saved = Conversation(title: "Old chat", provider: .openai, model: "o4-mini")
        let data = try JSONEncoder().encode(saved)
        let loaded = try JSONDecoder().decode(Conversation.self, from: data)
        #expect(loaded.model == "gpt-6-luna")
    }

    @Test func localModelsAreLeftAlone() {
        #expect(APIProvider.sanitizedModel("qwen3-0.6b-q4", for: .local) == "qwen3-0.6b-q4")
    }

    @Test func gpt6ContextLimit() {
        #expect(APIProvider.contextSize(for: "gpt-6.1-sol", provider: .openai) == 922_000)
    }
}
