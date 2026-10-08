//
//  ChatEmptyStateView.swift
//  Dualo
//

import SwiftUI

/// Shown in a chat with no messages yet: a greeting plus quick prompts that fill the composer.
struct ChatEmptyStateView: View {
    let isLoadingModel: Bool
    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 44
    @ScaledMetric(relativeTo: .title2) private var circleSize: CGFloat = 100
    let onSelectPrompt: (String) -> Void

    private let quickPrompts = [
        ("lightbulb", "Explain a concept to me"),
        ("pencil.line", "Help me write something"),
        ("ladybug", "Debug this code")
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Animated conversation icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.1), .purple.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: circleSize, height: circleSize)

                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: iconSize, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue.opacity(0.7), .purple.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.pulse.wholeSymbol, options: .speed(0.5).repeat(.continuous))
            }

            VStack(spacing: 8) {
                Text("Start a Conversation")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Ask me anything — I'm here to help!")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                // Loading indicator for local model
                if isLoadingModel {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .secondary))
                            .scaleEffect(0.8)

                        Text("Loading model...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }

            // Quick prompt buttons
            VStack(spacing: 10) {
                ForEach(quickPrompts, id: \.1) { symbol, text in
                    Button(action: {
                        HapticFeedback.light()
                        onSelectPrompt(text)
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: symbol)
                                .font(.body)
                                .foregroundStyle(.tint)
                                .frame(minWidth: 24)
                            Text(text)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(.secondarySystemGroupedBackground))
                                .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.theme.chatBackground)
    }
}

#Preview {
    ChatEmptyStateView(isLoadingModel: true, onSelectPrompt: { _ in })
}
