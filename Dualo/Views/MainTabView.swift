//
//  MainTabView.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI

struct MainTabView: View {
    @ObservedObject private var conversationManager = ConversationManager.shared

    var body: some View {
        HomeView()
            .onAppear {
                conversationManager.currentConversation = nil
            }
    }
}

#Preview {
    MainTabView()
}
