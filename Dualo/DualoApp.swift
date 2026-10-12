//
//  DualoApp.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI

@main
struct DualoApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        UITestSupport.prepareCloudConsent()
        #endif
    }

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
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { saveChatMemory() }
        }
    }

    /// Saves what a local model has read of the open chat, so it picks up from there if the
    /// system closes the app, with extra time to finish in the background
    private func saveChatMemory() {
        let backgroundTask = BackgroundTask()
        backgroundTask.identifier = UIApplication.shared.beginBackgroundTask(withName: "Save chat memory") {
            backgroundTask.end()
        }
        Task {
            await GGUFService.shared.saveChatMemory()
            backgroundTask.end()
        }
    }
}

/// Background time asked for, ended once when the work is done or the time runs out
@MainActor
private final class BackgroundTask {
    var identifier = UIBackgroundTaskIdentifier.invalid

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
