//
//  OpenAIMessageFormatter.swift
//  Dualo
//
//  Created by Robert Conover on 12/22/25.
//

import Foundation

/// Formats messages for the OpenAI Chat Completions API.
///
/// OpenAI's format requires:
/// - Text placed before images in content arrays
/// - Image blocks with type "image_url" and nested "image_url" object
/// - Images encoded as data URIs: "data:<media_type>;base64,<data>"
/// - Simple text messages can be strings or content arrays
///
/// Example format:
/// ```json
/// {
///   "role": "user",
///   "content": [
///     {
///       "type": "text",
///       "text": "What's in this image?"
///     },
///     {
///       "type": "image_url",
///       "image_url": {
///         "url": "data:image/jpeg;base64,<base64-data>"
///       }
///     }
///   ]
/// }
/// ```
struct OpenAIMessageFormatter: MessageFormatter {

    func formatMessages(
        currentMessage: String,
        history: [Message],
        attachments: [MessageAttachment]
    ) -> [[String: Any]] {
        var messages: [[String: Any]] = []

        // Format history messages
        for msg in history {
            if msg.hasAttachments {
                var content: [[String: Any]] = []

                // Text first for OpenAI
                if !msg.content.isEmpty {
                    content.append([
                        "type": "text",
                        "text": msg.content
                    ])
                }

                // Add image blocks after text
                for attachment in msg.attachments {
                    content.append([
                        "type": "image_url",
                        "image_url": [
                            "url": "data:\(attachment.mediaType);base64,\(attachment.data)"
                        ]
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

        // Format current message
        if !attachments.isEmpty {
            var content: [[String: Any]] = []

            // Text first for OpenAI
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

            // Add image blocks after text
            for attachment in attachments {
                content.append([
                    "type": "image_url",
                    "image_url": [
                        "url": "data:\(attachment.mediaType);base64,\(attachment.data)"
                    ]
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
