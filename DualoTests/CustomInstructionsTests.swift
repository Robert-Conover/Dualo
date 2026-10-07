//
//  CustomInstructionsTests.swift
//  DualoTests
//
//  Covers how custom instructions reach cloud requests and local system prompts.
//

import Foundation
import Testing
@testable import Dualo

struct CustomInstructionsTests {

    private let formatter = OpenAIMessageFormatter()
    private let history = [
        Message(role: Message.Role.user, content: "Hi"),
        Message(role: Message.Role.assistant, content: "Hello!")
    ]

    @Test func cloudRequestsStartWithTheInstructions() {
        let messages = formatter.formatMessages(currentMessage: "What's new?", history: history, attachments: [], instructions: "Be brief.")

        #expect(messages.count == 4)
        #expect(messages.first?["role"] as? String == "developer")
        #expect(messages.first?["content"] as? String == "Be brief.")
        #expect(messages.last?["content"] as? String == "What's new?")
    }

    @Test func cloudRequestsWithoutInstructionsHaveNoDeveloperMessage() {
        let messages = formatter.formatMessages(currentMessage: "What's new?", history: history, attachments: [], instructions: "")

        #expect(messages.count == 3)
        #expect(!messages.contains { $0["role"] as? String == "developer" })
    }

    @Test func localSystemPromptAddsTheInstructions() {
        let base = GGUFService.systemPrompt(with: "")
        let withInstructions = GGUFService.systemPrompt(with: "Be brief.")

        #expect(base == "You are a helpful assistant.")
        #expect(withInstructions.hasPrefix(base))
        #expect(withInstructions.hasSuffix("Be brief."))
    }

    @Test func savedTextIsTrimmedAndCapped() {
        #expect(CustomInstructions.normalized("  \n Be brief. \n") == "Be brief.")
        #expect(CustomInstructions.normalized(" \n ").isEmpty)
        #expect(CustomInstructions.normalized(String(repeating: "a", count: 5000)).count == CustomInstructions.maxLength)
    }
}
