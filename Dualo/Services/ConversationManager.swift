//
//  ConversationManager.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import Foundation
import SwiftUI

/// Holds initial message data when navigating from HomeView to SimpleChatView
struct PendingChatData {
    let message: String
    let attachments: [ImageAttachment]
}

@MainActor
class ConversationManager: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?
    @Published private(set) var isLoading = true
    
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
        try? fileManager.createDirectory(at: conversationsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
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
                    #if DEBUG
                    if conv.updatedAt > diskVersion.updatedAt {
                        print("ConversationManager: Merge - kept in-memory version of \(conv.id) (newer)")
                    }
                    #endif
                } else {
                    mergedConversations.append(diskVersion)
                    #if DEBUG
                    print("ConversationManager: Merge - used disk version of \(conv.id) (newer)")
                    #endif
                }
            } else {
                // Only in memory (e.g., created while loading)
                mergedConversations.append(conv)
                #if DEBUG
                print("ConversationManager: Merge - kept new in-memory conversation \(conv.id)")
                #endif
            }
        }
        
        // Add any disk conversations not in memory
        for (id, diskConv) in diskConversations where !processedIds.contains(id) {
            mergedConversations.append(diskConv)
        }
        
        // Sort by updatedAt descending
        conversations = mergedConversations.sorted { $0.updatedAt > $1.updatedAt }
        
        #if DEBUG
        print("ConversationManager: Merge complete - \(conversations.count) conversations")
        #endif
    }
    
    /// Synchronous migration helper - runs on background queue
    private static func performMigrationSync(legacyKey: String, directory: URL) -> [Conversation] {
        guard let data = UserDefaults.standard.data(forKey: legacyKey) else {
            return []
        }
        
        print("ConversationManager: Migrating conversations from UserDefaults to file storage...")
        
        let decoder = JSONDecoder()
        guard let legacyConversations = try? decoder.decode([Conversation].self, from: data) else {
            return []
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        for conversation in legacyConversations {
            let fileURL = directory.appendingPathComponent("\(conversation.id.uuidString).json")
            if let encodedData = try? encoder.encode(conversation) {
                try? encodedData.write(to: fileURL, options: .atomic)
            }
        }
        
        // Remove from UserDefaults after successful migration
        DispatchQueue.main.async {
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }
        
        print("ConversationManager: Successfully migrated \(legacyConversations.count) conversations to file storage")
        return legacyConversations
    }
    
    /// Synchronous load helper - runs on background queue
    private static func loadConversationsSync(directory: URL) -> [Conversation] {
        var loadedConversations: [Conversation] = []
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            let jsonFiles = files.filter { $0.pathExtension == "json" }
            
            let decoder = JSONDecoder()
            for fileURL in jsonFiles {
                if let data = try? Data(contentsOf: fileURL),
                   let conversation = try? decoder.decode(Conversation.self, from: data) {
                    loadedConversations.append(conversation)
                }
            }
        } catch {
            print("ConversationManager: Error loading conversations: \(error)")
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
        print("ConversationManager: selecting conversation \(conversation.id) with \(conversation.messages.count) messages")
        currentConversation = conversation
        saveCurrentConversationID()
    }
    
    func updateConversation(_ conversation: Conversation, moveToTop: Bool = false) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            #if DEBUG
            let oldConversation = conversations[index]
            let reason = determineUpdateReason(old: oldConversation, new: conversation)
            print("ConversationManager: updating conversation \(conversation.id) - reason: \(reason)")
            if moveToTop && index != 0 {
                print("ConversationManager: moving conversation to top (was at index \(index))")
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
    
    #if DEBUG
    private func determineUpdateReason(old: Conversation, new: Conversation) -> String {
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
    
    // MARK: - Async File Operations
    
    private func saveConversationAsync(_ conversation: Conversation) {
        let directory = conversationsDirectory
        let conversationCopy = conversation
        
        fileQueue.async {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let fileURL = directory.appendingPathComponent("\(conversationCopy.id.uuidString).json")
            
            do {
                let data = try encoder.encode(conversationCopy)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                print("ConversationManager: Error saving conversation \(conversationCopy.id): \(error)")
            }
        }
    }
    
    private func deleteConversationFileAsync(_ conversationId: UUID) {
        let directory = conversationsDirectory
        
        fileQueue.async {
            let fileURL = directory.appendingPathComponent("\(conversationId.uuidString).json")
            try? FileManager.default.removeItem(at: fileURL)
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
