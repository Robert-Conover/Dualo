//
//  ConversationSearchTests.swift
//  DualoTests
//
//  Covers searching chats from the conversations sheet.
//

import Foundation
import Testing
@testable import Dualo

struct ConversationSearchTests {

    private func chat(_ title: String, _ messages: [String]) -> Conversation {
        let messages = messages.enumerated().map { index, text in
            Message(role: index.isMultiple(of: 2) ? Message.Role.user : Message.Role.assistant, content: text)
        }
        return Conversation(title: title, messages: messages, provider: .openai, model: "gpt-6.1-sol")
    }

    private let recipes = [
        "Ideas for dinner",
        "Try a risotto with mushrooms and thyme.",
        "What about dessert?",
        "A lemon tart is light and easy."
    ]

    @Test func blankQueryReturnsEveryChatWithoutSnippets() {
        let chats = [chat("A", ["Hi"]), chat("B", ["Hello"])]
        let results = ConversationSearch.search(chats, for: "  ")

        #expect(results.map(\.conversation.id) == chats.map(\.id))
        #expect(results.allSatisfy { $0.snippet == nil })
    }

    @Test func findsWordsAnywhereInTheChatNotJustTheLastMessage() {
        let results = ConversationSearch.search([chat("Dinner", recipes)], for: "risotto")

        #expect(results.count == 1)
        #expect(results.first?.snippet == "Try a risotto with mushrooms and thyme.")
    }

    @Test func snippetComesFromTheLatestMatchingMessage() {
        let chat = chat("Notes", ["Teal is nice.", "OK.", "Actually I prefer teal and gold.", "Noted."])
        let snippet = ConversationSearch.search([chat], for: "teal").first?.snippet

        #expect(snippet == "Actually I prefer teal and gold.")
    }

    @Test func matchingIgnoresCaseAndAccents() {
        let chats = [chat("Trip", ["Where's a good café in Paris?"])]

        #expect(ConversationSearch.search(chats, for: "CAFE").count == 1)
    }

    @Test func titleOnlyMatchHasNoSnippet() {
        let results = ConversationSearch.search([chat("Dinner plans", recipes)], for: "plans")

        #expect(results.count == 1)
        #expect(results.first?.snippet == nil)
    }

    @Test func chatsWithoutAMatchAreLeftOutAndOrderIsKept() {
        let chats = [chat("One", ["lemon"]), chat("Two", ["lime"]), chat("Three", ["Lemonade"])]
        let titles = ConversationSearch.search(chats, for: "lemon").map(\.conversation.title)

        #expect(titles == ["One", "Three"])
    }

    @Test func reasoningInThinkBlocksIsNotSearched() {
        let chats = [chat("Q", ["Hi", "<think>The user greets me, reply warmly</think>Hello there!"])]

        #expect(ConversationSearch.search(chats, for: "warmly").isEmpty)
        #expect(ConversationSearch.search(chats, for: "hello there").count == 1)
    }

    @Test func longMessagesAreTrimmedAroundTheMatchOnOneLine() throws {
        let text = String(repeating: "filler ", count: 30) + "needle\n\nin the\nhaystack " + String(repeating: "more ", count: 40)
        let snippet = try #require(ConversationSearch.snippet(in: text, matching: "needle"))

        #expect(snippet.hasPrefix("…") && snippet.hasSuffix("…"))
        #expect(snippet.contains("needle in the haystack"))
        #expect(!snippet.contains("\n"))
        #expect(snippet.count < 140)
    }
}
