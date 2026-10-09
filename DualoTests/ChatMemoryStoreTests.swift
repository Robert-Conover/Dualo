//
//  ChatMemoryStoreTests.swift
//  DualoTests
//
//  Which chats keep their saved model memory. GGUFServiceIntegrationTests checks that a
//  real model picks a chat up from it.
//

import Foundation
import Testing
@testable import Dualo

struct ChatMemoryStoreTests {

    private let store: ChatMemoryStore = {
        var store = ChatMemoryStore(root: URL.temporaryDirectory.appending(path: "ChatMemoryStoreTests-\(UUID())"))
        store.maxChats = 3
        return store
    }()

    /// Saves an empty memory for `conversationId`, as if it were saved `age` seconds ago
    @discardableResult
    private func save(_ conversationId: UUID, modelId: String = "model", age: TimeInterval = 0,
                      lastForgottenMessageId: UUID? = nil) throws -> URL {
        let directory = try #require(store.prepareDirectory(for: conversationId, modelId: modelId))
        store.finishSaving(.init(lastForgottenMessageId: lastForgottenMessageId), in: directory)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -age)], ofItemAtPath: directory.path)
        return directory
    }

    @Test func remembersWhereTheChatStarted() throws {
        let chat = UUID(), forgotten = UUID()
        try save(chat, lastForgottenMessageId: forgotten)

        #expect(store.info(for: chat, modelId: "model")?.lastForgottenMessageId == forgotten)
        #expect(store.hasMemory(for: chat, modelId: "model"))
        #expect(!store.hasMemory(for: chat, modelId: "other model"))
    }

    @Test func memoryNotFinishedSavingIsntPickedUp() throws {
        let chat = UUID()
        _ = try #require(store.prepareDirectory(for: chat, modelId: "model"))

        #expect(!store.hasMemory(for: chat, modelId: "model"))
    }

    @Test func keepsOnlyTheMostRecentlySavedChats() throws {
        let chats = (0..<4).map { _ in UUID() }
        try save(chats[0], age: 400)
        try save(chats[1], modelId: "other model", age: 300)
        try save(chats[2], age: 200)
        try save(chats[3], age: 100)
        store.prune()

        #expect(!store.hasMemory(for: chats[0], modelId: "model"))
        #expect(store.hasMemory(for: chats[1], modelId: "other model"))
        #expect(store.hasMemory(for: chats[2], modelId: "model"))
        #expect(store.hasMemory(for: chats[3], modelId: "model"))
    }

    @Test func deletedChatLosesItsMemoryForEveryModel() throws {
        let chat = UUID(), other = UUID()
        try save(chat)
        try save(chat, modelId: "other model")
        try save(other)

        store.remove(chat)

        #expect(!store.hasMemory(for: chat, modelId: "model"))
        #expect(!store.hasMemory(for: chat, modelId: "other model"))
        #expect(store.hasMemory(for: other, modelId: "model"))
    }
}
