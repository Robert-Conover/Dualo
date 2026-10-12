//
//  MainTabView.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI

/// The app's root: shows Home, clearing any open chat so a new one starts from scratch.
struct MainTabView: View {
    @EnvironmentObject var conversationManager: ConversationManager

    var body: some View {
        HomeView()
            .onAppear {
                conversationManager.currentConversation = nil
            }
    }
}

#Preview {
    MainTabView()
        .environmentObject(ConversationManager.shared)
        .environmentObject(LocalModelManager.shared)
        .environmentObject(GGUFService.shared)
        .environmentObject(ContextTracker.shared)
}
