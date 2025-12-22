//
//  ConversationsSheetView.swift
//  Dualo
//
//  Created by Robert Conover on 12/7/25.
//

import SwiftUI

struct ConversationsSheetView: View {
    @ObservedObject private var conversationManager = ConversationManager.shared
    @Binding var selectedConversation: Conversation?
    @Binding var isPresented: Bool
    
    @State private var searchText = ""
    @State private var showingDeleteAlert = false
    @State private var conversationToDelete: Conversation?
    @State private var showingRenameAlert = false
    @State private var conversationToRename: Conversation?
    @State private var renameText = ""
    
    private var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return conversationManager.conversations
        }
        return conversationManager.conversations.filter { conversation in
            conversation.title.localizedCaseInsensitiveContains(searchText) ||
            conversation.preview.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                headerView
                
                if conversationManager.isLoading {
                    loadingView
                } else if conversationManager.conversations.isEmpty {
                    emptyStateView
                } else {
                    // Conversations list
                    conversationsList
                }
                
                // Search bar at bottom
                searchBar
            }
            .background(Color.theme.sheetBackground)
            .navigationBarHidden(true)
        }
        .alert("Delete Conversation", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let conversation = conversationToDelete {
                    conversationManager.deleteConversation(conversation)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this conversation? This action cannot be undone.")
        }
        .alert("Rename Conversation", isPresented: $showingRenameAlert) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let conversation = conversationToRename {
                    var updated = conversation
                    updated.title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.updatedAt = Date()
                    conversationManager.updateConversation(updated, moveToTop: false)
                }
            }
        } message: {
            Text("Enter a new name for this conversation")
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Spacer()
            
            Text("Conversations")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
            
            Spacer()
        }
        .overlay(alignment: .trailing) {
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                isPresented = false
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
            }
            .tint(.primary)
            .glassEffect(in: .circle)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    // MARK: - Loading State
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading conversations...")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.secondary.opacity(0.6))
            
            Text("No conversations yet")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
            
            Text("Start a new chat from the home screen")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Conversations List
    
    private var conversationsList: some View {
        List {
            Section {
                ForEach(filteredConversations) { conversation in
                    Button(action: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        selectedConversation = conversation
                        isPresented = false
                    }) {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conversation.title)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                
                                HStack(spacing: 8) {
                                    Text(timeString(from: conversation.updatedAt))
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                    
                                    Text("•")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.quaternary)
                                    
                                    Text("\(conversation.messages.count) messages")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            
                            Spacer()
                            
                            modelBadge(for: conversation)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            conversationToDelete = conversation
                            showingDeleteAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            conversationToRename = conversation
                            renameText = conversation.title
                            showingRenameAlert = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            } header: {
                Text("Recents")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
    
    private func timeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    // MARK: - Model Badge
    
    private func modelBadge(for conversation: Conversation) -> some View {
        HStack(spacing: 4) {
            Image(systemName: conversation.provider == .anthropic ? "brain" : "sparkles")
                .font(.system(size: 9, weight: .semibold))
            Text(shortModelName(conversation.model))
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(conversation.provider == .anthropic ? .orange : .green)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(conversation.provider == .anthropic ? 
                      Color.orange.opacity(0.12) : 
                      Color.green.opacity(0.12))
        )
    }
    
    private func shortModelName(_ model: String) -> String {
        if model.contains("opus") { return "Opus" }
        if model.contains("sonnet") { return "Sonnet" }
        if model.contains("haiku") { return "Haiku" }
        if model.contains("gpt-4o") { return "4o" }
        if model.contains("gpt-4") { return "GPT-4" }
        if model.contains("gpt-5-mini") { return "5 Mini" }
        if model.contains("gpt-5-nano") { return "5 Nano" }
        if model.contains("gpt-5") { return "GPT-5" }
        return String(model.prefix(8))
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            
            TextField("Search", text: $searchText)
                .font(.body)
                .tint(.accentColor)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(in: .rect(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}

#Preview {
    ConversationsSheetView(
        selectedConversation: .constant(nil),
        isPresented: .constant(true)
    )
}

