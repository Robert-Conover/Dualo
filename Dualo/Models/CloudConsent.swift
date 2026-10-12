//
//  CloudConsent.swift
//  Dualo
//
//  Whether the user has agreed to send chats to OpenAI. Apple asks apps to get
//  permission before sharing personal data with a third-party AI service, so the
//  first message to a cloud model waits for it (see ChatViewModel).
//

import Foundation

enum CloudConsent {
    /// UserDefaults key, shared with the toggle in Settings
    static var key: String {
        #if DEBUG
        // Stubbed UI-test launches keep an answer of their own and leave the real one alone
        if UITestSupport.isStubbingAPI { return "CloudAIConsentGranted.uitest" }
        #endif
        return "CloudAIConsentGranted"
    }

    static func isGranted(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    static func grant(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key)
    }
}
