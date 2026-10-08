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
    @Binding var showPhotoPicker: Bool
    @Binding var showCamera: Bool
    @FocusState.Binding var isInputFocused: Bool

    let conversationId: UUID
    let currentProvider: APIProvider
    let onSendMessage: () -> Void

    @StateObject private var voiceInput = VoiceInputController()
    @AppStorage(AppConstants.LocalModels.showGenerationStatsKey) private var showGenerationStats = true

    var body: some View {
        VStack(spacing: 0) {
            // Live streaming stats (for local models while generating)
            if showsGenerationStats && viewModel.isStreaming && ggufService.isGenerating {
                streamingIndicatorSection
            }
            // Stats for this chat's last reply, shown until the next one starts
            else if showsGenerationStats, let stats = ggufService.lastGenerationStats,
                    stats.conversationId == conversationId, !viewModel.messages.isEmpty {
                generationStatsSection(stats: stats)
            }
            // Context usage, once the chat is close enough to the limit to matter
            else if !viewModel.messages.isEmpty && contextTracker.contextLimit > 0 && contextTracker.usageInfo.isNearLimit {
                contextUsageSection
            }

            if viewModel.editingMessageId != nil {
                editingSection
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
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.isStreaming)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.editingMessageId)
    }

    // MARK: - Subviews

    private var streamingIndicatorSection: some View {
        LocalModelStreamingIndicator(
            tokenCount: ggufService.currentTokenCount,
            startTime: ggufService.generationStartTime
        )
        .padding(.top, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func generationStatsSection(stats: GenerationStats) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)

            Text("\(stats.tokenCount) tokens")
                .font(.caption.weight(.medium))

            Text("•")
                .foregroundStyle(Color(.tertiaryLabel))

            Text(stats.formattedDuration)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("•")
                .foregroundStyle(Color(.tertiaryLabel))

            Text(stats.formattedSpeed)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)

            // Context usage indicator (compact, in stats banner)
            ContextUsageIndicator(usageInfo: contextTracker.usageInfo, style: .compact)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("generationStats")
        .padding(.top, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var editingSection: some View {
        HStack(spacing: 10) {
            Label("Editing message", systemImage: "pencil")
                .font(.footnote.weight(.medium))

            Button("Cancel Editing", systemImage: "xmark") {
                HapticFeedback.light()
                viewModel.cancelEditing()
                messageText = ""
            }
            .labelStyle(.iconOnly)
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("cancelEditingButton")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(in: .capsule)
        .padding(.top, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var contextUsageSection: some View {
        ContextUsageIndicator(usageInfo: contextTracker.usageInfo, style: .full)
            .padding(.top, 8)
            .transition(.opacity)
    }

    private var inputSection: some View {
        HStack(spacing: 12) {
            // Text input container with embedded send button
            HStack(spacing: 8) {
                // + button for attachments (hidden for models that can't take images)
                if currentProvider.supportsImageAttachments {
                    AttachmentMenu(showPhotoPicker: $showPhotoPicker, showCamera: $showCamera)
                        .disabled(viewModel.isLoading || viewModel.isStreaming)
                        .accessibilityIdentifier("chatAttachButton")
                }

                TextField("Message", text: $messageText, axis: .vertical)
                    .accessibilityIdentifier("chatComposer")
                    .font(.body)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .focused($isInputFocused)
                    .disabled(viewModel.isLoading || viewModel.isStreaming)
                    .onSubmit {
                        if canSendMessage && !viewModel.isStreaming {
                            send()
                        }
                    }

                VoiceInputButton(
                    voiceInput: voiceInput,
                    text: $messageText,
                    isInputFocused: $isInputFocused,
                    identifierPrefix: "chat"
                )
                .disabled(viewModel.isLoading || viewModel.isStreaming)

                // Embedded send button
                Button(action: {
                    HapticFeedback.medium()

                    if viewModel.isStreaming {
                        viewModel.stopStreaming()
                    } else {
                        send()
                    }
                }) {
                    Image(systemName: viewModel.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(
                            viewModel.isStreaming ? Color.primary :
                            canSendMessage ? .blue : .secondary
                        )
                        .scaleEffect(canSendMessage || viewModel.isStreaming ? 1.0 : 0.8)
                        .contentTransition(.symbolEffect(.replace))
                }
                .disabled(!canSendMessage && !viewModel.isStreaming)
                .accessibilityLabel(viewModel.isStreaming ? "Stop" : "Send")
                .accessibilityIdentifier("chatSendButton")
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: canSendMessage)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: viewModel.isStreaming)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(in: .rect(cornerRadius: 22))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    /// Generation stats are on in Settings and this chat runs on a local model
    private var showsGenerationStats: Bool {
        showGenerationStats && currentProvider == .local
    }

    private func send() {
        // Send what's been heard so far; later results mustn't refill the cleared composer
        voiceInput.cancel()
        onSendMessage()
    }

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
