//
//  ModelMemory.swift
//  Dualo
//
//  Decides how much of a chat a local model can see. Its context holds a fixed number
//  of tokens, so a long chat keeps its newest messages and the oldest drop out.
//

import Foundation

/// What a local model remembers of a chat.
struct ModelMemory: Equatable {
    let conversationId: UUID
    /// The newest message that no longer fits, or nil when the whole chat does
    let lastForgottenMessageId: UUID?
    /// Tokens the remembered messages and the prompt around them take up
    let usedTokens: Int
    /// Tokens they can take up in all, once room is set aside for the reply
    let availableTokens: Int

    var forgetsMessages: Bool { lastForgottenMessageId != nil }
}

enum ModelMemoryBudget {
    /// Template tokens around each message (role markers, end of turn)
    static let tokensPerMessage = 8
    /// The template's start of the reply, with its empty thinking block
    static let replyPreambleTokens = 16
    /// The smallest room for a reply worth starting
    static let minimumReplyTokens = 256

    /// Room set aside for the reply, so it doesn't run out of space partway through
    static func replyReserve(contextSize: Int) -> Int {
        contextSize / 4
    }

    /// How many of the newest messages fit in `budget` tokens, given each one's size.
    /// What's kept starts with a user message, so a reply never shows up without its question.
    static func rememberedCount(sizes: [Int], isUserMessage: [Bool], budget: Int) -> Int {
        var count = 0
        var used = 0
        for size in sizes.reversed() {
            guard used + size <= budget else { break }
            used += size
            count += 1
        }
        while count > 0 && !isUserMessage[sizes.count - count] {
            count -= 1
        }
        return count
    }

    /// Share of `budget` that's kept when older messages have to go
    static let keptShareWhenForgetting = 0.75

    /// Like `rememberedCount`, for a chat whose oldest `forgottenCount` messages are already
    /// forgotten: the rest stay while they fit. When they don't, older ones go in one step that
    /// leaves room for the next few messages, because each change to where the chat starts makes
    /// the model read all of it again.
    static func rememberedCount(sizes: [Int], isUserMessage: [Bool], budget: Int, forgottenCount: Int) -> Int {
        let rest = sizes.count - forgottenCount
        if rest >= 0, sizes.suffix(rest).reduce(0, +) <= budget, rest == 0 || isUserMessage[forgottenCount] {
            return rest
        }
        let keptBudget = Int(Double(budget) * keptShareWhenForgetting)
        let count = rememberedCount(sizes: sizes, isUserMessage: isUserMessage, budget: keptBudget)
        // Unless that leaves nothing, when the newest messages could still fit in the whole budget
        return count > 0 ? count : rememberedCount(sizes: sizes, isUserMessage: isUserMessage, budget: budget)
    }
}
