//
//  ConversationManager.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import Foundation
import SwiftUI
import OSLog

/// Holds initial message data when navigating from HomeView to SimpleChatView
struct PendingChatData {
    let message: String
    let attachments: [ImageAttachment]
}

@MainActor
class ConversationManager: ObservableObject, ConversationManaging {
    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?
    @Published private(set) var isLoading = true
    @Published private(set) var storageError: StorageError?

    /// Storage errors that can occur during file operations
    enum StorageError: LocalizedError {
        case directoryCreationFailed(String)
        case saveFailed(UUID, String)
        case loadFailed(String)

        var errorDescription: String? {
            switch self {
            case .directoryCreationFailed(let details):
                return "Failed to create storage directory: \(details)"
            case .saveFailed(let id, let details):
                return "Failed to save conversation \(id.uuidString.prefix(8)): \(details)"
            case .loadFailed(let details):
                return "Failed to load conversations: \(details)"
            }
        }
    }
    
    /// Transient storage for initial message + attachments when starting a new chat from HomeView.
    /// SimpleChatView reads and clears this on appear.
    var pendingChatData: PendingChatData?
    
    // Legacy UserDefaults keys (for migration)
    private let legacyConversationsKey = AppConstants.Data.conversationsKey
    private let currentConversationKey = AppConstants.Data.currentConversationKey
    
    // File-based storage
    private let fileManager = FileManager.default
    private var conversationsDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("Conversations", isDirectory: true)
    }
    private var attachmentsDirectory: URL {
        conversationsDirectory.appendingPathComponent("Attachments", isDirectory: true)
    }
    
    // Serial queue for file operations to prevent race conditions
    private let fileQueue = DispatchQueue(label: "com.dualo.conversationManager.fileIO", qos: .userInitiated)
    
    static let shared = ConversationManager()
    
    private init() {
        ensureDirectoriesExist()
        // Start async loading - don't block init
        Task { [weak self] in
            await self?.loadInitialData()
        }
    }
    
    private func ensureDirectoriesExist() {
        do {
            try fileManager.createDirectory(at: conversationsDirectory, withIntermediateDirectories: true)
        } catch {
            Logger.conversations.fault("Failed to create conversations directory: \(error.localizedDescription, privacy: .public)")
            storageError = .directoryCreationFailed(error.localizedDescription)
        }

        do {
            try fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        } catch {
            Logger.conversations.fault("Failed to create attachments directory: \(error.localizedDescription, privacy: .public)")
            storageError = .directoryCreationFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Async Loading
    
    private func loadInitialData() async {
        let directory = conversationsDirectory
        let legacyKey = legacyConversationsKey
        
        // Perform all IO on background thread
        let (migrated, loaded) = await withCheckedContinuation { continuation in
            fileQueue.async {
                let migratedConversations = Self.performMigrationSync(legacyKey: legacyKey, directory: directory)
                let loadedConversations = Self.loadConversationsSync(directory: directory)
                continuation.resume(returning: (migratedConversations, loadedConversations))
            }
        }
        
        // Combine migrated + loaded from disk, removing duplicates
        var diskConversations: [UUID: Conversation] = [:]
        for conv in migrated {
            diskConversations[conv.id] = conv
        }
        for conv in loaded where diskConversations[conv.id] == nil {
            diskConversations[conv.id] = conv
        }
        
        // MERGE into existing in-memory conversations (instead of overwriting)
        // This prevents a race where conversations created/updated while loading get lost
        mergeLoadedConversations(diskConversations)
        
        // Only restore current conversation if none is selected yet
        if currentConversation == nil {
            restoreCurrentConversation()
        }
        
        await migrateOldMessagesAsync()
        isLoading = false
    }
    
    /// Merge disk-loaded conversations into in-memory conversations.
    /// Strategy: prefer in-memory on conflict if it has a newer/equal updatedAt, otherwise use disk version.
    /// Keep any in-memory conversations that don't exist on disk.
    private func mergeLoadedConversations(_ diskConversations: [UUID: Conversation]) {
        // Index current in-memory conversations
        var inMemoryById: [UUID: Conversation] = [:]
        for conv in conversations {
            inMemoryById[conv.id] = conv
        }
        
        // Build merged result
        var mergedConversations: [Conversation] = []
        var processedIds = Set<UUID>()
        
        // First, process all in-memory conversations
        for conv in conversations {
            processedIds.insert(conv.id)
            
            if let diskVersion = diskConversations[conv.id] {
                // Both exist: prefer newer (in-memory wins on tie)
                if conv.updatedAt >= diskVersion.updatedAt {
                    mergedConversations.append(conv)
                    if conv.updatedAt > diskVersion.updatedAt {
                        Logger.conversations.debug("Merge - kept in-memory version of \(conv.id, privacy: .public) (newer)")
                    }
                } else {
                    mergedConversations.append(diskVersion)
                    Logger.conversations.debug("Merge - used disk version of \(conv.id, privacy: .public) (newer)")
                }
            } else {
                // Only in memory (e.g., created while loading)
                mergedConversations.append(conv)
                Logger.conversations.debug("Merge - kept new in-memory conversation \(conv.id, privacy: .public)")
            }
        }
        
        // Add any disk conversations not in memory
        for (id, diskConv) in diskConversations where !processedIds.contains(id) {
            mergedConversations.append(diskConv)
        }
        
        // Sort by updatedAt descending
        conversations = mergedConversations.sorted { $0.updatedAt > $1.updatedAt }
        
        Logger.conversations.debug("Merge complete - \(self.conversations.count) conversations")
    }
    
    /// Synchronous migration helper - runs on background queue
    nonisolated private static func performMigrationSync(legacyKey: String, directory: URL) -> [Conversation] {
        guard let data = UserDefaults.standard.data(forKey: legacyKey) else {
            return []
        }
        
        Logger.conversations.info("Migrating conversations from UserDefaults to file storage...")
        
        let decoder = JSONDecoder()
        guard let legacyConversations = try? decoder.decode([Conversation].self, from: data) else {
            return []
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        var migrationErrors: [String] = []
        for conversation in legacyConversations {
            let fileURL = directory.appendingPathComponent("\(conversation.id.uuidString).json")
            do {
                let encodedData = try encoder.encode(conversation)
                try encodedData.write(to: fileURL, options: .atomic)
            } catch {
                migrationErrors.append("Conversation \(conversation.id.uuidString.prefix(8)): \(error.localizedDescription)")
            }
        }

        if !migrationErrors.isEmpty {
            for migrationError in migrationErrors {
                Logger.conversations.error("Migration error: \(migrationError, privacy: .public)")
            }
        }

        // Only remove from UserDefaults if all migrations succeeded
        if migrationErrors.isEmpty {
            UserDefaults.standard.removeObject(forKey: legacyKey)
            Logger.conversations.info("Successfully migrated \(legacyConversations.count) conversations to file storage")
        } else {
            Logger.conversations.warning("Keeping UserDefaults -- \(migrationErrors.count) migration errors")
        }
        return legacyConversations
    }
    
    /// Synchronous load helper - runs on background queue
    nonisolated private static func loadConversationsSync(directory: URL) -> [Conversation] {
        var loadedConversations: [Conversation] = []

        do {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            let jsonFiles = files.filter { $0.pathExtension == "json" }

            let decoder = JSONDecoder()
            for fileURL in jsonFiles {
                do {
                    let data = try Data(contentsOf: fileURL)
                    let conversation = try decoder.decode(Conversation.self, from: data)
                    loadedConversations.append(conversation)
                } catch {
                    Logger.conversations.error("Failed to load \(fileURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    // Continue loading other files - don't let one corrupt file break everything
                }
            }
        } catch {
            Logger.conversations.error("Error reading conversations directory: \(error.localizedDescription, privacy: .public)")
        }

        return loadedConversations
    }
    
    private func restoreCurrentConversation() {
        if let currentID = UserDefaults.standard.object(forKey: currentConversationKey) as? String,
           let uuid = UUID(uuidString: currentID) {
            currentConversation = conversations.first { $0.id == uuid }
        }
    }
    
    private func migrateOldMessagesAsync() async {
        let oldMessagesKey = AppConstants.Data.legacyMessagesKey
        
        guard let data = UserDefaults.standard.data(forKey: oldMessagesKey) else { return }
        
        let decoder = JSONDecoder()
        guard let oldMessages = try? decoder.decode([Message].self, from: data),
              !oldMessages.isEmpty,
              conversations.isEmpty else { return }
        
        var migratedConversation = Conversation(title: AppConstants.Data.importedChatTitle)
        migratedConversation.messages = oldMessages
        conversations.append(migratedConversation)
        currentConversation = migratedConversation
        
        saveConversationAsync(migratedConversation)
        saveCurrentConversationID()
        
        UserDefaults.standard.removeObject(forKey: oldMessagesKey)
    }
    
    // MARK: - Public API
    
    func createNewConversation() -> Conversation {
        let conversation = Conversation()
        conversations.insert(conversation, at: 0)
        currentConversation = conversation
        saveConversationAsync(conversation)
        saveCurrentConversationID()
        return conversation
    }
    
    func selectConversation(_ conversation: Conversation) {
        Logger.conversations.debug("Selecting conversation \(conversation.id, privacy: .public) with \(conversation.messages.count) messages")
        currentConversation = conversation
        saveCurrentConversationID()
    }
    
    func updateConversation(_ conversation: Conversation, moveToTop: Bool = false) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            #if DEBUG
            let oldConversation = conversations[index]
            let reason = determineUpdateReason(old: oldConversation, new: conversation)
            Logger.conversations.debug("Updating conversation \(conversation.id, privacy: .public) - reason: \(reason, privacy: .public)")
            if moveToTop && index != 0 {
                Logger.conversations.debug("Moving conversation to top (was at index \(index))")
            }
            #endif
            
            conversations[index] = conversation
            
            if moveToTop && index != 0 {
                conversations.remove(at: index)
                conversations.insert(conversation, at: 0)
            }
            
            if currentConversation?.id == conversation.id {
                currentConversation = conversation
            }
            
            saveConversationAsync(conversation)
        }
    }
    
    /// Pinning doesn't change activity dates or recency, so unpinning restores the chat's place.
    func togglePin(for conversationId: UUID) {
        guard var conversation = conversations.first(where: { $0.id == conversationId }) else { return }
        conversation.isPinned.toggle()
        updateConversation(conversation, moveToTop: false)
    }

    #if DEBUG
    private func determineUpdateReason(old: Conversation, new: Conversation) -> String {
        if old.isPinned != new.isPinned {
            return "pin changed"
        }
        if old.messages.count != new.messages.count {
            return "message count changed (\(old.messages.count) → \(new.messages.count))"
        }
        if old.title != new.title {
            return "title changed ('\(old.title)' → '\(new.title)')"
        }
        if old.model != new.model || old.provider != new.provider {
            return "model/provider changed"
        }
        if old.messages != new.messages {
            return "message content changed"
        }
        return "timestamp update only"
    }
    #endif
    
    func deleteConversation(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        
        if currentConversation?.id == conversation.id {
            currentConversation = conversations.first
            saveCurrentConversationID()
        }
        
        deleteConversationFileAsync(conversation.id)
    }
    
    func clearAllConversations() {
        let conversationIds = conversations.map { $0.id }
        conversations = []
        currentConversation = nil

        for id in conversationIds {
            deleteConversationFileAsync(id)
        }

        saveCurrentConversationID()
    }

    /// Clear the current storage error (call after displaying to user)
    func clearStorageError() {
        storageError = nil
    }
    
    // MARK: - Async File Operations
    
    private func saveConversationAsync(_ conversation: Conversation) {
        let directory = conversationsDirectory
        let conversationCopy = conversation

        fileQueue.async { [weak self] in
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let fileURL = directory.appendingPathComponent("\(conversationCopy.id.uuidString).json")

            do {
                let data = try encoder.encode(conversationCopy)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                Logger.conversations.error("Error saving conversation \(conversationCopy.id.uuidString.prefix(8), privacy: .public): \(error.localizedDescription, privacy: .public)")
                // Report save failure to UI on main thread
                Task { @MainActor in
                    self?.storageError = .saveFailed(conversationCopy.id, error.localizedDescription)
                }
            }
        }
    }
    
    private func deleteConversationFileAsync(_ conversationId: UUID) {
        let directory = conversationsDirectory

        fileQueue.async {
            ChatMemoryStore.shared.remove(conversationId)
            let fileURL = directory.appendingPathComponent("\(conversationId.uuidString).json")
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch let error as NSError {
                // Ignore "file not found" errors (already deleted or never saved)
                if error.domain != NSCocoaErrorDomain || error.code != NSFileNoSuchFileError {
                    Logger.conversations.error("Failed to delete \(conversationId.uuidString.prefix(8), privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
    
    private func saveCurrentConversationID() {
        if let currentID = currentConversation?.id.uuidString {
            UserDefaults.standard.set(currentID, forKey: currentConversationKey)
        } else {
            UserDefaults.standard.removeObject(forKey: currentConversationKey)
        }
    }
}
