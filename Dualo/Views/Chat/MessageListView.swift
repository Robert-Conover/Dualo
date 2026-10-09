//
//  MessageListView.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI

// MARK: - Message List View

struct MessageListView: View {
    @ObservedObject var viewModel: ChatViewModel
    let currentProvider: APIProvider
    @Binding var showScrollToBottom: Bool
    @Binding var scrollToBottomAction: (() -> Void)?
    @FocusState.Binding var isInputFocused: Bool
    /// Called with the last user message when it's picked for editing
    let onEditMessage: (UUID) -> Void
    /// The newest message a local model no longer remembers; a divider goes under it
    var lastForgottenMessageId: UUID? = nil

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                        let isCurrentlyStreaming = viewModel.isStreaming && message.id == viewModel.messages.last?.id && message.role == Message.Role.assistant
                        // One view per message: a lazy stack loses track of rows that
                        // sometimes produce a second view, and the list goes blank
                        VStack(spacing: 8) {
                            MessageBubbleView(
                                message: message,
                                isStreaming: isCurrentlyStreaming,
                                provider: currentProvider,
                                streamingContent: isCurrentlyStreaming ? viewModel.streamingMessageContent : nil,
                                onRetry: message.isFailed ? {
                                    Task {
                                        await viewModel.retryMessage(message.id)
                                    }
                                } : nil,
                                onEdit: message.id == viewModel.editableMessageId ? {
                                    onEditMessage(message.id)
                                } : nil,
                                onRegenerate: message.id == viewModel.regenerableMessageId ? {
                                    Task {
                                        await viewModel.regenerateReply(message.id)
                                    }
                                } : nil
                            )

                            if message.id == lastForgottenMessageId {
                                ModelMemoryDivider()
                            }
                        }
                        .id(message.id)
                        .transition(.asymmetric(
                            insertion: .push(from: .bottom)
                                .combined(with: .scale(scale: 0.9, anchor: .bottom))
                                .combined(with: .opacity)
                                .animation(.spring(response: 0.35, dampingFraction: 0.85).delay(Double(index) * 0.03)),
                            removal: .scale(scale: 0.8)
                                .combined(with: .opacity)
                                .animation(.spring(response: 0.25, dampingFraction: 0.9))
                        ))
                    }

                    if viewModel.isLoading && !viewModel.isStreaming {
                        loadingIndicator
                    }
                }
                .padding(.vertical, 16)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.messages.count)
            }
            // Read from the scroll view itself: a marker view at the end of the lazy stack
            // gets unloaded when the chat is scrolled far up, and then reports nothing
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentSize.height - geometry.visibleRect.maxY
            } action: { _, distanceFromBottom in
                updateScrollToBottomVisibility(distanceFromBottom: distanceFromBottom)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChangeCompat(of: viewModel.messages.count) { _ in
                scrollToBottomOnMessageChange(proxy: proxy)
            }
            .onChange(of: lastForgottenMessageId) { _, newValue in
                // A divider under the last message would land behind the composer
                if newValue == viewModel.messages.last?.id && !showScrollToBottom {
                    scrollToBottomOnMessageChange(proxy: proxy)
                }
            }
            .onChange(of: viewModel.streamingMessageContent) { oldValue, newValue in
                scrollDuringStreaming(proxy: proxy, oldValue: oldValue, newValue: newValue)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isInputFocused = false
            }
            .background(
                Color.clear.onAppear {
                    setupScrollAction(proxy: proxy)
                }
            )
        }
        .background(Color.theme.chatBackground)
    }

    // MARK: - Subviews

    private var loadingIndicator: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                // Animated dots
                HStack(spacing: 4) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.blue.opacity(0.7), .purple.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 8, height: 8)
                            .scaleEffect(viewModel.isLoading ? 1.0 : 0.3)
                            .opacity(viewModel.isLoading ? 1.0 : 0.3)
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.5)
                                .repeatForever()
                                .delay(Double(index) * 0.12),
                                value: viewModel.isLoading
                            )
                    }
                }

                Text("Thinking...")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(in: .capsule)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .id("loading")
        .transition(.asymmetric(
            insertion: .push(from: .bottom).combined(with: .opacity),
            removal: .scale(scale: 0.8).combined(with: .opacity)
        ))
    }

    // MARK: - Helper Methods

    private func updateScrollToBottomVisibility(distanceFromBottom: CGFloat) {
        // Don't update while streaming - it interferes with auto-scroll
        guard !viewModel.isStreaming else { return }
        guard !viewModel.messages.isEmpty else { return }

        // Show button when user has scrolled up more than threshold from bottom
        let threshold: CGFloat = 100
        let shouldShow = distanceFromBottom > threshold

        if shouldShow != showScrollToBottom {
            withAnimation(.easeInOut(duration: 0.3)) {
                showScrollToBottom = shouldShow
            }
        }
    }

    private func scrollToBottomOnMessageChange(proxy: ScrollViewProxy) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            if viewModel.isLoading && !viewModel.isStreaming {
                proxy.scrollTo("loading", anchor: .bottom)
                showScrollToBottom = false
            } else if let lastMessage = viewModel.messages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                showScrollToBottom = false
            }
        }
    }

    private func scrollDuringStreaming(proxy: ScrollViewProxy, oldValue: String, newValue: String) {
        // Auto-scroll while streaming - only if content is growing
        if viewModel.isStreaming && newValue.count > oldValue.count {
            if let lastMessage = viewModel.messages.last {
                // Use minimal animation to keep up with fast token generation
                withAnimation(.linear(duration: 0.1)) {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }

    private func setupScrollAction(proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            scrollToBottomAction = {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    if viewModel.isLoading && !viewModel.isStreaming {
                        proxy.scrollTo("loading", anchor: .bottom)
                    } else if let lastMessage = viewModel.messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    } else {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                    showScrollToBottom = false
                }
            }
        }
    }
}
