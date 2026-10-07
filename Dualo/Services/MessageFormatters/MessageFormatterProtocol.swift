//
//  MessageFormatterProtocol.swift
//  Dualo
//
//  Created by Robert Conover on 12/22/25.
//

import Foundation

/// Protocol defining the interface for formatting messages for different AI providers.
///
/// Message formatters handle the provider-specific serialization of message history,
/// attachments, and current messages into the JSON format expected by each API.
protocol MessageFormatter {
    /// Formats messages into provider-specific JSON structure.
    ///
    /// - Parameters:
    ///   - currentMessage: The current user message to send
    ///   - history: Array of previous messages in the conversation
    ///   - attachments: Array of image attachments for the current message
    ///   - instructions: The user's custom instructions, or empty for none
    /// - Returns: Array of message dictionaries formatted for the provider's API
    func formatMessages(
        currentMessage: String,
        history: [Message],
        attachments: [MessageAttachment],
        instructions: String
    ) -> [[String: Any]]
}
