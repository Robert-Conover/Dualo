//
//  CustomInstructions.swift
//  Dualo
//
//  Instructions the user sets once in Settings and every chat follows,
//  cloud and on-device alike.
//

import Foundation

enum CustomInstructions {
    /// UserDefaults key, shared with the `@AppStorage` in `CustomInstructionsView`
    static let key = "CustomInstructions"

    /// Long enough for a paragraph or two. On-device models have a 4K-token context,
    /// and the instructions take up part of it in every chat.
    static let maxLength = 1500

    /// The saved instructions, trimmed. Empty when none are set.
    static var current: String {
        normalized(UserDefaults.standard.string(forKey: key) ?? "")
    }

    static func normalized(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
    }
}
