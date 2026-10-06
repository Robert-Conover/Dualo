//
//  Logger+Dualo.swift
//  Dualo
//
//  Shared os.Logger instances, one per subsystem area.
//  View in Console.app or Xcode by filtering on the app's subsystem and category.
//

import OSLog

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Dualo"

    /// Chat streaming and message state (ChatViewModel)
    static let chat = Logger(subsystem: subsystem, category: "Chat")
    /// Conversation persistence and migration (ConversationManager)
    static let conversations = Logger(subsystem: subsystem, category: "Conversations")
    /// On-device inference (GGUFService)
    static let inference = Logger(subsystem: subsystem, category: "Inference")
    /// Local model downloads, imports, and deletion (LocalModelManager)
    static let localModels = Logger(subsystem: subsystem, category: "LocalModels")
    /// Provider configuration and keychain access
    static let config = Logger(subsystem: subsystem, category: "Config")
    /// Context-window tracking (ContextTracker)
    static let context = Logger(subsystem: subsystem, category: "Context")
    /// View-level events
    static let ui = Logger(subsystem: subsystem, category: "UI")
}
