//
//  ModelMemoryTests.swift
//  DualoTests
//
//  Which of a chat's messages fit in a local model's context. GGUFServiceIntegrationTests
//  checks the same with a real model and tokenizer.
//

import Foundation
import Testing
@testable import Dualo

struct ModelMemoryBudgetTests {

    @Test func keepsEverythingThatFits() {
        let count = ModelMemoryBudget.rememberedCount(
            sizes: [10, 10, 10, 10], isUserMessage: [true, false, true, false], budget: 40
        )
        #expect(count == 4)
    }

    @Test func dropsTheOldestMessagesFirst() {
        let count = ModelMemoryBudget.rememberedCount(
            sizes: [10, 10, 10, 10], isUserMessage: [true, false, true, false], budget: 25
        )
        #expect(count == 2)
    }

    @Test func neverKeepsAReplyWithoutItsQuestion() {
        // Three messages fit, but the oldest of them is a reply whose question didn't
        let count = ModelMemoryBudget.rememberedCount(
            sizes: [10, 10, 10, 10], isUserMessage: [true, false, true, false], budget: 35
        )
        #expect(count == 2)
    }

    @Test func stopsAtTheFirstMessageThatDoesntFit() {
        // A small old message would fit in the space left, but skipping a message in the
        // middle would leave the model reading a chat with a hole in it
        let count = ModelMemoryBudget.rememberedCount(
            sizes: [5, 5, 10, 100, 10, 10, 10, 10],
            isUserMessage: [true, false, true, false, true, false, true, false],
            budget: 50
        )
        // The newest 40 tokens fit and the 100-token reply doesn't, so the older ones are left out too
        #expect(count == 4)
    }

    @Test func keepsNothingWhenTheBudgetIsUsedUp() {
        #expect(ModelMemoryBudget.rememberedCount(sizes: [10, 10], isUserMessage: [true, false], budget: 0) == 0)
        #expect(ModelMemoryBudget.rememberedCount(sizes: [10, 10], isUserMessage: [true, false], budget: -50) == 0)
        #expect(ModelMemoryBudget.rememberedCount(sizes: [], isUserMessage: [], budget: 100) == 0)
    }
}

struct MemoryEntriesTests {

    @Test func keepsEachMessagesIdAndLeavesOutReasoning() {
        let question = Message(role: Message.Role.user, content: "What is 2+2?")
        let reply = Message(role: Message.Role.assistant, content: "<think>Easy.</think>\n\n4")

        let entries = GGUFService.memoryEntries(from: [question, reply])

        #expect(entries.map(\.id) == [question.id, reply.id])
        #expect(entries.map(\.chat.content) == ["What is 2+2?", "4"])
    }

    @Test func skipsMessagesWithNothingLeftToRead() {
        let messages = [
            Message(role: Message.Role.user, content: "Hi"),
            Message(role: Message.Role.assistant, content: "<think>Only thinking, stopped here"),
            Message(role: Message.Role.user, content: "Hello?")
        ]

        let entries = GGUFService.memoryEntries(from: messages)

        #expect(entries.map(\.id) == [messages[0].id, messages[2].id])
    }
}
