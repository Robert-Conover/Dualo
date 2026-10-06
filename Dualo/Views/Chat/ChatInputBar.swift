//
//  ChatInputBar.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI
import UIKit

// MARK: - Chat Input Bar

struct ChatInputBar: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var ggufService: GGUFService
    @ObservedObject var contextTracker: ContextTracker

    @Binding var messageText: String
    @Binding var pendingAttachments: [ImageAttachment]
    @Binding var showAttachmentOptions: Bool
    @Binding var showGenerationStats: Bool
    @FocusState.Binding var isInputFocused: Bool

    let currentProvider: APIProvider
    let onSendMessage: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Live streaming stats (for local models while generating)
            if viewModel.isStreaming && currentProvider == .local && ggufService.isGenerating {
                streamingIndicatorSection
            }
            // Post-generation stats banner (for local models after completion)
            else if showGenerationStats, let stats = ggufService.lastGenerationStats, currentProvider == .local {
                generationStatsSection(stats: stats)
            }
            // Context usage indicator (when not streaming/showing stats but has messages)
            else if !viewModel.messages.isEmpty && contextTracker.contextLimit > 0 {
                contextUsageSection
            }

            // Pending attachments preview
            if !pendingAttachments.isEmpty {
                PendingAttachmentPreview(attachments: pendingAttachments) { attachment in
                    pendingAttachments.removeAll { $0.id == attachment.id }
                }
            }

            // Input field and send button
            inputSection
        }
        .background(Color.theme.chatBackground.opacity(0.95))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 0)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showGenerationStats)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.isStreaming)
    }

    // MARK: - Subviews

    private var streamingIndicatorSection: some View {
        HStack {
            LocalModelStreamingIndicator(
                tokenCount: ggufService.currentTokenCount,
                startTime: ggufService.generationStartTime
            )
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.95))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func generationStatsSection(stats: GenerationStats) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.green)

            Text("\(stats.tokenCount) tokens")
                .font(.system(size: 12, weight: .medium))

            Text("•")
                .foregroundStyle(Color(.tertiaryLabel))

            Text(stats.formattedDuration)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text("•")
                .foregroundStyle(Color(.tertiaryLabel))

            Text(stats.formattedSpeed)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)

            Spacer()

            // Context usage indicator (compact, in stats banner)
            ContextUsageIndicator(usageInfo: contextTracker.usageInfo, style: .compact)

            Button(action: {
                withAnimation(.easeOut(duration: 0.2)) {
                    showGenerationStats = false
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var contextUsageSection: some View {
        ContextUsageIndicator(usageInfo: contextTracker.usageInfo, style: .full)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .transition(.opacity)
    }

    private var inputSection: some View {
        HStack(spacing: 12) {
            // Text input container with embedded send button
            HStack(spacing: 8) {
                // + button for attachments
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    showAttachmentOptions = true
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.blue)
                        .frame(width: 24, height: 24)
                }
                .disabled(viewModel.isLoading || viewModel.isStreaming)

                TextField("Message", text: $messageText, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .focused($isInputFocused)
                    .disabled(viewModel.isLoading || viewModel.isStreaming)
                    .onSubmit {
                        if canSendMessage && !viewModel.isStreaming {
                            onSendMessage()
                        }
                    }

                // Embedded send button
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()

                    if viewModel.isStreaming {
                        viewModel.stopStreaming()
                    } else {
                        onSendMessage()
                    }
                }) {
                    Image(systemName: viewModel.isStreaming ? "stop.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(
                            viewModel.isStreaming ? .red :
                            canSendMessage ? .blue : .secondary
                        )
                        .scaleEffect(canSendMessage || viewModel.isStreaming ? 1.0 : 0.8)
                        .rotationEffect(.degrees(viewModel.isStreaming ? 90 : 0))
                }
                .disabled(!canSendMessage && !viewModel.isStreaming)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: canSendMessage)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: viewModel.isStreaming)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(in: .rect(cornerRadius: 22))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Helpers

    private var canSendMessage: Bool {
        let hasText = !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !pendingAttachments.isEmpty
        let hasContent = hasText || hasAttachments
        let notBusy = !viewModel.isLoading && !viewModel.isStreaming

        // For local models, also check if model is loaded and not currently loading
        if currentProvider == .local {
            let modelReady = ggufService.isModelLoaded && !ggufService.isLoading
            return hasContent && notBusy && modelReady
        }

        return hasContent && notBusy
    }
}
