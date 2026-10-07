//
//  ConversationsSheetView.swift
//  Dualo
//
//  Created by Robert Conover on 12/7/25.
//

import SwiftUI

struct ConversationsSheetView: View {
    @EnvironmentObject var conversationManager: ConversationManager
    @Binding var selectedConversation: Conversation?
    @Binding var isPresented: Bool
    
    @State private var searchText = ""
    @State private var showingDeleteAlert = false
    @State private var conversationToDelete: Conversation?
    @State private var showingRenameAlert = false
    @State private var conversationToRename: Conversation?
    @State private var renameText = ""
    
    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            let searchResults = ConversationSearch.search(conversationManager.conversations, for: searchText)
            VStack(spacing: 0) {
                // Header
                headerView

                if !conversationManager.conversations.isEmpty {
                    searchBar
                }

                if conversationManager.isLoading {
                    loadingView
                } else if conversationManager.conversations.isEmpty {
                    emptyStateView
                } else if searchResults.isEmpty {
                    noResultsView
                } else {
                    // Conversations list
                    conversationsList(searchResults)
                }
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
            if let conversation = conversationToDelete {
                let truncatedTitle = conversation.title.count > 50
                    ? String(conversation.title.prefix(50)) + "..."
                    : conversation.title
                Text("Delete '\(truncatedTitle)'?\n\nThis action cannot be undone.")
            } else {
                Text("Are you sure you want to delete this conversation? This action cannot be undone.")
            }
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
                HapticFeedback.light()
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

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.secondary.opacity(0.6))

            Text("No results for \u{201C}\(searchText.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Conversations List
    
    private func conversationsList(_ searchResults: [ConversationSearch.Result]) -> some View {
        List {
            Section {
                ForEach(searchResults) { result in
                    let conversation = result.conversation
                    Button(action: {
                        HapticFeedback.light()
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

                                if let snippet = result.snippet {
                                    Text(highlighted(snippet))
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .accessibilityIdentifier("conversationSearchSnippet")
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
                Text(isSearching ? "Results" : "Recents")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    /// The snippet with the search term in bold
    private func highlighted(_ snippet: String) -> AttributedString {
        var text = AttributedString(snippet)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = text.range(of: query, options: ConversationSearch.matchOptions) {
            text[match].font = .system(size: 14, weight: .semibold)
            text[match].foregroundColor = .primary
        }
        return text
    }
    
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private func timeString(from date: Date) -> String {
        Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
    
    // MARK: - Model Badge
    
    private func modelBadge(for conversation: Conversation) -> some View {
        let isLocal = conversation.provider == .local

        return HStack(spacing: 4) {
            Image(systemName: isLocal ? "iphone" : "sparkles")
                .font(.system(size: 9, weight: .semibold))
            Text(shortModelName(conversation.model))
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(isLocal ? .blue : .green)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isLocal ? Color.blue.opacity(0.12) : Color.green.opacity(0.12))
        )
    }
    
    private func shortModelName(_ model: String) -> String {
        switch model {
        case "gpt-6-astra": return "Astra"
        case "gpt-6.1-sol": return "Sol"
        case "gpt-6-luna": return "Luna"
        default:
            // Local models are stored by id ("qwen3.5-0.8b-q4"); show their name ("Qwen3.5 0.8B")
            return LocalModelCatalog.model(withId: model)?.displayName ?? model
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search chats", text: $searchText)
                .font(.body)
                .tint(.accentColor)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("conversationSearchField")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .glassEffect(in: .capsule)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

#Preview {
    ConversationsSheetView(
        selectedConversation: .constant(nil),
        isPresented: .constant(true)
    )
    .environmentObject(ConversationManager.shared)
}
