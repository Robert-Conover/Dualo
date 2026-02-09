//
//  DualoApp.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI

@main
struct DualoApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(ConversationManager.shared)
                .environmentObject(LocalModelManager.shared)
                .environmentObject(GGUFService.shared)
                .environmentObject(ContextTracker.shared)
                .preferredColorScheme(nil)
                .task {
                    // Auto-load previously selected local model if applicable
                    await GGUFService.shared.autoLoadLastModel()
                }
        }
    }
}
