//
//  Conversation.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import Foundation
import OSLog

struct Conversation: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var title: String
    var messages: [Message]
    let createdAt: Date
    var updatedAt: Date
    var provider: APIProvider
    var model: String
    
    // Custom initializer for decoding to handle migration from old format
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        messages = try container.decode([Message].self, forKey: .messages)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        
        // Handle migration - if provider and model don't exist, use defaults
        if let existingProvider = try? container.decode(APIProvider.self, forKey: .provider),
           let existingModel = try? container.decode(String.self, forKey: .model) {
            provider = existingProvider
            model = APIProvider.sanitizedModel(existingModel, for: existingProvider)
        } else {
            // Migration: use current defaults for existing conversations
            let (defaultProvider, defaultModel) = Self.getCurrentDefaults()
            provider = defaultProvider
            model = defaultModel
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, title, messages, createdAt, updatedAt, provider, model
    }
    
    init(title: String = AppConstants.Data.newChatTitle, messages: [Message] = [], provider: APIProvider? = nil, model: String? = nil) {
        self.id = UUID()
        self.title = title
        self.messages = messages
        self.createdAt = Date()
        self.updatedAt = Date()
        
        // Use provided values or fall back to current default configuration
        if let provider = provider, let model = model {
            self.provider = provider
            self.model = model
        } else {
            let (defaultProvider, defaultModel) = Self.getCurrentDefaults()
            self.provider = defaultProvider
            self.model = defaultModel
        }
    }
    
    private static func getCurrentDefaults() -> (APIProvider, String) {
        do {
            if let configs = try KeychainService.shared.loadProviderConfigurations(),
               let currentConfig = configs.currentConfiguration() {
                return (currentConfig.provider, currentConfig.model)
            }
        } catch {
            Logger.config.error("Failed to load current configuration: \(String(describing: error), privacy: .public)")
        }
        
        // Fallback to default values
        let defaultProvider = APIProvider.openai
        return (defaultProvider, defaultProvider.defaultModel)
    }
    
    mutating func addMessage(_ message: Message) {
        messages.append(message)
        updatedAt = Date()
        
        // Auto-generate title from first user message if still default title
        if title == AppConstants.Data.newChatTitle, let firstUserMessage = messages.first(where: { $0.role == Message.Role.user }) {
            title = generateTitle(from: firstUserMessage.content)
        }
    }
    
    mutating func removeMessage(id: UUID) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages.remove(at: index)
            updatedAt = Date()
        }
    }
    
    /// Removes the message at `index` and every message after it. A title made from a
    /// removed message goes too, so the next message names the chat again.
    mutating func removeMessages(from index: Int) {
        guard messages.indices.contains(index) else { return }
        if let firstUserIndex = messages.firstIndex(where: { $0.role == Message.Role.user }),
           firstUserIndex >= index,
           title == generateTitle(from: messages[firstUserIndex].content) {
            title = AppConstants.Data.newChatTitle
        }
        messages.removeSubrange(index...)
        updatedAt = Date()
    }

    /// Whether the title is still one the app gave it (not one the user or the model wrote),
    /// so the model can name the chat
    var hasPlaceholderTitle: Bool {
        guard let firstUserMessage = messages.first(where: { $0.role == Message.Role.user }) else {
            return title == AppConstants.Data.newChatTitle
        }
        return title == AppConstants.Data.newChatTitle || title == generateTitle(from: firstUserMessage.content)
    }

    var lastMessage: Message? {
        messages.last
    }
    
    var preview: String {
        guard let lastMessage = lastMessage else { return AppConstants.Data.noMessagesPreview }
        let content = lastMessage.content
        return content.count > AppConstants.UI.previewMaxLength ? String(content.prefix(AppConstants.UI.previewMaxLength)) + "..." : content
    }
    
    private func generateTitle(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.components(separatedBy: .whitespacesAndNewlines).prefix(AppConstants.UI.titleWordLimit)
        return words.joined(separator: " ")
    }
}
