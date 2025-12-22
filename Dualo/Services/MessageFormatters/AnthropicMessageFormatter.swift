//
//  AnthropicMessageFormatter.swift
//  Dualo
//
//  Created by Robert Conover on 12/22/25.
//

import Foundation

/// Formats messages for the Anthropic Messages API.
///
/// Anthropic's format requires:
/// - Images placed before text in content arrays
/// - Image blocks with type "image" and nested "source" object
/// - Source contains type "base64", media_type, and data fields
/// - Simple text messages can be strings or content arrays
///
/// Example format:
/// ```json
/// {
///   "role": "user",
///   "content": [
///     {
///       "type": "image",
///       "source": {
///         "type": "base64",
///         "media_type": "image/jpeg",
///         "data": "<base64-data>"
///       }
///     },
///     {
///       "type": "text",
///       "text": "What's in this image?"
///     }
///   ]
/// }
/// ```
struct AnthropicMessageFormatter: MessageFormatter {

    func formatMessages(
        currentMessage: String,
        history: [Message],
        attachments: [MessageAttachment]
    ) -> [[String: Any]] {
        var messages: [[String: Any]] = []

        // Format history messages (may include attachments)
        for msg in history {
            if msg.hasAttachments {
                var content: [[String: Any]] = []

                // Add image blocks first for Anthropic
                for attachment in msg.attachments {
                    content.append([
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": attachment.mediaType,
                            "data": attachment.data
                        ]
                    ])
                }

                // Add text content after images
                if !msg.content.isEmpty {
                    content.append([
                        "type": "text",
                        "text": msg.content
                    ])
                }

                messages.append([
                    "role": msg.role,
                    "content": content
                ])
            } else {
                // Simple text message
                messages.append([
                    "role": msg.role,
                    "content": msg.content
                ])
            }
        }

        // Format current message with any new attachments
        if !attachments.isEmpty {
            var content: [[String: Any]] = []

            // Add image blocks first
            for attachment in attachments {
                content.append([
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": attachment.mediaType,
                        "data": attachment.data
                    ]
                ])
            }

            // Add text content after images
            if !currentMessage.isEmpty {
                content.append([
                    "type": "text",
                    "text": currentMessage
                ])
            } else {
                // Default prompt when only image is provided
                content.append([
                    "type": "text",
                    "text": "What's in this image?"
                ])
            }

            messages.append([
                "role": "user",
                "content": content
            ])
        } else {
            // Simple text message
            messages.append([
                "role": "user",
                "content": currentMessage
            ])
        }

        return messages
    }
}
