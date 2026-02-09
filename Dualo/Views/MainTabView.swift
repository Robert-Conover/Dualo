//
//  MainTabView.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI

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
