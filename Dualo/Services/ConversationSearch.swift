//
//  ConversationSearch.swift
//  Dualo
//
//  Finds chats whose title or messages contain a query, with a snippet of where it matched.
//

import Foundation

enum ConversationSearch {
    struct Result: Identifiable {
        let conversation: Conversation
        /// Text around the latest message that matched, or nil when only the title did
        let snippet: String?

        var id: UUID { conversation.id }
    }

    /// Case- and accent-insensitive, so "cafe" finds "Café"
    static let matchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    private static let snippetContextBefore = 40
    private static let snippetContextAfter = 80

    /// Matching chats in their original order. A blank query matches everything.
    static func search(_ conversations: [Conversation], for query: String) -> [Result] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return conversations.map { Result(conversation: $0, snippet: nil) }
        }

        return conversations.compactMap { conversation in
            // The most recent mention is usually the one people remember
            for message in conversation.messages.reversed() {
                if let snippet = snippet(in: searchableText(of: message), matching: query) {
                    return Result(conversation: conversation, snippet: snippet)
                }
            }
            if conversation.title.range(of: query, options: matchOptions) != nil {
                return Result(conversation: conversation, snippet: nil)
            }
            return nil
        }
    }

    /// The message as the reader saw it: reasoning in <think> blocks isn't searched.
    private static func searchableText(of message: Message) -> String {
        message.content.contains("<think>")
            ? GGUFService.stripThinkingBlocks(from: message.content)
            : message.content
    }

    /// A one-line excerpt around the first match, or nil if `text` doesn't contain `query`.
    static func snippet(in text: String, matching query: String) -> String? {
        guard let match = text.range(of: query, options: matchOptions) else { return nil }

        let start = text.index(match.lowerBound, offsetBy: -snippetContextBefore, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(match.upperBound, offsetBy: snippetContextAfter, limitedBy: text.endIndex) ?? text.endIndex

        let excerpt = text[start..<end]
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return (start > text.startIndex ? "…" : "") + excerpt + (end < text.endIndex ? "…" : "")
    }
}
