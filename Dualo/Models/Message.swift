//
//  Message.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import Foundation

// MARK: - Message Attachment

struct MessageAttachment: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let data: String        // Base64 encoded image data
    let mediaType: String   // "image/jpeg", "image/png", etc.
    let width: Int?
    let height: Int?

    init(id: UUID = UUID(), data: String, mediaType: String, width: Int? = nil, height: Int? = nil) {
        self.id = id
        self.data = data
        self.mediaType = mediaType
        self.width = width
        self.height = height
    }
}

// MARK: - Send Status

enum SendStatus: String, Codable, Equatable, Hashable {
    case sending
    case sent
    case failed
}

// MARK: - Message

struct Message: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let role: String
    var content: String
    let timestamp: Date
    var attachments: [MessageAttachment]
    var sendStatus: SendStatus

    init(role: String, content: String, attachments: [MessageAttachment] = [], sendStatus: SendStatus = .sent) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.attachments = attachments
        self.sendStatus = sendStatus
    }

    init(id: UUID, role: String, content: String, timestamp: Date, attachments: [MessageAttachment] = [], sendStatus: SendStatus = .sent) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.attachments = attachments
        self.sendStatus = sendStatus
    }

    // MARK: - Codable (Backward Compatible)

    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp, attachments, sendStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(String.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        // Backward compatibility: default to empty array if attachments don't exist
        attachments = (try? container.decode([MessageAttachment].self, forKey: .attachments)) ?? []
        // Backward compatibility: default to .sent for existing messages
        sendStatus = (try? container.decode(SendStatus.self, forKey: .sendStatus)) ?? .sent
    }

    // MARK: - Helper Properties

    var hasAttachments: Bool {
        !attachments.isEmpty
    }
    
    var isFailed: Bool {
        sendStatus == .failed
    }
    
    var isSending: Bool {
        sendStatus == .sending
    }

    enum Role {
        static let user = "user"
        static let assistant = "assistant"
    }
}