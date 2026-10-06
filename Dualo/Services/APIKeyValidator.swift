//
//  APIKeyValidator.swift
//  Dualo
//

import Foundation

/// Format checks for OpenAI API keys. Single source of truth for both the inline
/// error in Settings and the guard that decides whether a key gets saved.
enum APIKeyValidator {

    /// Pasted keys often carry a trailing newline or space; never store those.
    static func normalized(_ apiKey: String) -> String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns a user-facing message describing what's wrong with the key, or `nil` if it looks valid.
    /// An empty key is valid (it clears the stored key).
    /// - Parameter checkLength: Pass `false` while the user is still typing so a partial key
    ///   isn't flagged as too short on every keystroke.
    static func validationError(for apiKey: String, checkLength: Bool = true) -> String? {
        let key = normalized(apiKey)

        if key.isEmpty {
            return nil
        }

        if !key.hasPrefix(AppConstants.Security.openaiKeyPrefix) {
            return "OpenAI API keys must start with '\(AppConstants.Security.openaiKeyPrefix)'"
        }

        if checkLength && key.count < AppConstants.Security.openaiKeyMinLength {
            return "This key looks too short. Check that it was copied in full."
        }

        return nil
    }
}
