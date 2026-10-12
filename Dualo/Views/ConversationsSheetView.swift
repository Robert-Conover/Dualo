//
//  ConversationsSheetView.swift
//  Dualo
//
//  Created by Robert Conover on 12/7/25.
//

import SwiftUI

/// Saved chats, with pinned chats first, search, rename, delete, and a tap to open one.
struct ConversationsSheetView: View {
    @EnvironmentObject var conversationManager: ConversationManager
    @Binding var selectedConversation: Conversation?
    @Binding var isPresented: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
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
            Group {
                if conversationManager.isLoading {
                    ProgressView("Loading Conversations…")
                } else if conversationManager.conversations.isEmpty {
                    ContentUnavailableView(
                        "No Conversations",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Chats you start from the home screen show up here.")
                    )
                } else if searchResults.isEmpty {
                    ContentUnavailableView.search(text: searchText.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    conversationsList(searchResults)
                }
            }
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) {
                        HapticFeedback.light()
                        isPresented = false
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search chats")
            .autocorrectionDisabled()
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
    
    // MARK: - Conversations List
    
    private func conversationsList(_ searchResults: [ConversationSearch.Result]) -> some View {
        List {
            conversationSection(searchResults.filter { $0.conversation.isPinned }, title: "Pinned")
            conversationSection(searchResults.filter { !$0.conversation.isPinned }, title: isSearching ? "Results" : "Recents")
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder
    private func conversationSection(_ results: [ConversationSearch.Result], title: String) -> some View {
        if !results.isEmpty {
            Section {
                ForEach(results) { result in
                    conversationRow(result)
                }
            } header: {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
    }

    private func conversationRow(_ result: ConversationSearch.Result) -> some View {
        let conversation = result.conversation
        return Button(action: {
            HapticFeedback.light()
            selectedConversation = conversation
            isPresented = false
        }) {
            rowLayout {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if conversation.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        Text(conversation.title)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    Text("\(timeString(from: conversation.updatedAt)) · ^[\(conversation.messages.count) message](inflect: true)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let snippet = result.snippet {
                        Text(highlighted(snippet))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .accessibilityIdentifier("conversationSearchSnippet")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                modelBadge(for: conversation)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("conversationRow-\(conversation.id)")
        .accessibilityValue(conversation.isPinned ? "Pinned" : "")
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            pinButton(for: conversation)
                .tint(.orange)
        }
        .contextMenu {
            pinButton(for: conversation)
        }
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

    private func pinButton(for conversation: Conversation) -> some View {
        Button {
            HapticFeedback.light()
            withAnimation {
                conversationManager.togglePin(for: conversation.id)
            }
        } label: {
            Label(conversation.isPinned ? "Unpin" : "Pin", systemImage: conversation.isPinned ? "pin.slash" : "pin")
        }
    }

    /// Side by side, or the badge under the text when accessibility text sizes leave no room
    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    }

    /// The snippet with the search term in bold
    private func highlighted(_ snippet: String) -> AttributedString {
        var text = AttributedString(snippet)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = text.range(of: query, options: ConversationSearch.matchOptions) {
            text[match].font = .subheadline.weight(.semibold)
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
                .font(.caption2.weight(.semibold))
            Text(shortModelName(conversation.model))
                .font(.caption2.weight(.medium))
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
}

#Preview {
    ConversationsSheetView(
        selectedConversation: .constant(nil),
        isPresented: .constant(true)
    )
    .environmentObject(ConversationManager.shared)
}
