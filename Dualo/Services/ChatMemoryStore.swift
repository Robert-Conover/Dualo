//
//  ChatMemoryStore.swift
//  Dualo
//
//  Where GGUFService saves what a local model has read of a chat, so going back to the chat,
//  even after the app relaunches, picks up from there instead of reading all of it again.
//

import Foundation

/// Saved model memory for the few most recent chats, in Caches: the system may clear it,
/// which only costs the next message in those chats a full read.
struct ChatMemoryStore {
    static let shared = ChatMemoryStore(root: URL.cachesDirectory.appending(path: "ChatMemory"))

    let root: URL
    var maxChats = AppConstants.LocalModels.maxSavedChatMemories

    /// What a saved chat needs besides the model's state
    struct Info: Codable {
        /// Where the model's memory of the chat started, so the next message starts there too
        var lastForgottenMessageId: UUID?
    }

    /// Each model reads chats into its own state, so each has its own folder
    func directory(for conversationId: UUID, modelId: String) -> URL {
        root.appending(path: modelId).appending(path: conversationId.uuidString)
    }

    /// An empty folder for a chat's memory, replacing any saved before
    func prepareDirectory(for conversationId: UUID, modelId: String) -> URL? {
        let directory = directory(for: conversationId, modelId: modelId)
        try? FileManager.default.removeItem(at: directory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            return nil
        }
    }

    func info(for conversationId: UUID, modelId: String) -> Info? {
        let url = directory(for: conversationId, modelId: modelId).appending(path: "info.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Info.self, from: data)
    }

    /// Marks the memory saved in `directory` as complete. Chats without it aren't picked up.
    func finishSaving(_ info: Info, in directory: URL) {
        guard let data = try? JSONEncoder().encode(info) else { return }
        try? data.write(to: directory.appending(path: "info.json"), options: .atomic)
        prune()
    }

    func hasMemory(for conversationId: UUID, modelId: String) -> Bool {
        info(for: conversationId, modelId: modelId) != nil
    }

    /// Removes a chat's memory for every model, e.g. when the chat is deleted
    func remove(_ conversationId: UUID) {
        for modelDirectory in contents(of: root) {
            try? FileManager.default.removeItem(at: modelDirectory.appending(path: conversationId.uuidString))
        }
    }

    /// Keeps the `maxChats` most recently saved chats, across all models
    func prune() {
        let saved = contents(of: root).flatMap { contents(of: $0) }.map { directory in
            let date = (try? directory.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return (directory, date ?? .distantPast)
        }
        for (directory, _) in saved.sorted(by: { $0.1 > $1.1 }).dropFirst(maxChats) {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func contents(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles
        )) ?? []
    }
}
