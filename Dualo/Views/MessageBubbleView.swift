//
//  MessageBubbleView.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI

struct MessageBubbleView: View {
    let message: Message
    let isStreaming: Bool
    var provider: APIProvider?
    /// Live streaming content for token-by-token rendering (only used when isStreaming is true)
    var streamingContent: String?
    /// Callback when user taps retry on a failed message
    var onRetry: (() -> Void)?
    
    @State private var showTimestamp = false
    
    init(message: Message, isStreaming: Bool = false, provider: APIProvider? = nil, streamingContent: String? = nil, onRetry: (() -> Void)? = nil) {
        self.message = message
        self.isStreaming = isStreaming
        self.provider = provider
        self.streamingContent = streamingContent
        self.onRetry = onRetry
    }
    
    /// The content to display - uses live streaming buffer when available, otherwise message content
    private var displayContent: String {
        if isStreaming, let streaming = streamingContent, !streaming.isEmpty {
            return streaming
        }
        return message.content
    }
    
    private var isUser: Bool {
        message.role == Message.Role.user
    }
    
    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            if showTimestamp {
                Text(message.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
            }
            
            HStack {
                if isUser { Spacer(minLength: 60) }
                
                VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                    // Display attachments if present
                    if message.hasAttachments {
                        attachmentsView
                    }
                    
                    if isUser {
                        // User message with subtle pill background
                        VStack(alignment: .trailing, spacing: 6) {
                            if !message.content.isEmpty {
                                Text(message.content)
                                    .font(.body)
                                    .multilineTextAlignment(.trailing)
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(
                                        message.isFailed ? Color.red.opacity(0.15) : Color.theme.messageBubbleUser
                                    )
                                    .clipShape(.rect(cornerRadius: 20, style: .continuous))
                                    .overlay(
                                        // Failed indicator border
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .stroke(Color.red.opacity(0.4), lineWidth: message.isFailed ? 1 : 0)
                                    )
                            }
                            
                            // Send status indicator
                            if message.isSending {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                    Text("Sending...")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            } else if message.isFailed {
                                Button(action: {
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                    impactFeedback.impactOccurred()
                                    onRetry?()
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .font(.caption)
                                        Text("Failed to send")
                                            .font(.caption2)
                                        Text("· Tap to retry")
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                    }
                                    .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        // AI message - plain text, no background
                        if displayContent.isEmpty && isStreaming {
                            // Show processing indicator when streaming with no content yet
                            HStack(spacing: 4) {
                                ForEach(0..<3) { index in
                                    Circle()
                                        .fill(Color.secondary.opacity(0.5))
                                        .frame(width: 6, height: 6)
                                        .scaleEffect(isStreaming ? 1.0 : 0.5)
                                        .animation(
                                            .easeInOut(duration: 0.6)
                                            .repeatForever()
                                            .delay(Double(index) * 0.2),
                                            value: isStreaming
                                        )
                                }
                            }
                            .padding(.vertical, 8)
                        } else if isStreaming {
                            // While streaming: use plain text to avoid expensive Markdown/code parsing on every UI update
                            // This significantly reduces CPU usage during high-frequency token streaming
                            Text(displayContent)
                                .font(.body)
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            // After streaming: use rich rendering with Markdown/code block parsing
                            MessageContentView(content: displayContent, isUser: false)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .contextMenu {
                    Button(action: {
                        // Use displayContent to copy what the user actually sees (including streaming snapshot)
                        UIPasteboard.general.string = displayContent
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                    }) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    
                    Button(action: {
                        // Use displayContent to share what the user actually sees (including streaming snapshot)
                        let activityController = UIActivityViewController(
                            activityItems: [displayContent],
                            applicationActivities: nil
                        )
                        
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let window = windowScene.windows.first {
                            window.rootViewController?.present(activityController, animated: true)
                        }
                    }) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                
                if !isUser { Spacer(minLength: 60) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showTimestamp.toggle()
            }
            
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        }
    }

    // MARK: - Attachments View

    @ViewBuilder
    private var attachmentsView: some View {
        if message.attachments.count == 1 {
            // Single image - larger display
            ImageAttachmentView(attachment: message.attachments[0])
        } else {
            // Multiple images - grid layout
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 4),
                GridItem(.flexible(), spacing: 4)
            ], spacing: 4) {
                ForEach(message.attachments) { attachment in
                    ImageAttachmentView(attachment: attachment)
                        .frame(maxWidth: 100, maxHeight: 100)
                }
            }
        }
    }
}
