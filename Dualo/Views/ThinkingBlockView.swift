//
//  ThinkingBlockView.swift
//  Dualo
//
//  Created by Robert Conover on 12/21/25.
//

import SwiftUI

struct ThinkingBlockView: View {
    let content: String
    @State private var isExpanded = false
    @State private var showCopyConfirmation = false
    @Environment(\.colorScheme) var colorScheme
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : Color(UIColor.systemGray6)
    }
    
    private var borderColor: Color {
        colorScheme == .dark ? Color(UIColor.separator).opacity(0.3) : Color(UIColor.separator).opacity(0.2)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - always visible, tappable to expand/collapse
            HStack(spacing: 8) {
                Button(action: toggleExpanded) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        
                        Image(systemName: SystemImages.brainProfile)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        
                        Text("Thought process")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        if !isExpanded, !previewText.isEmpty {
                            Text(previewText)
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Thought process")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint("Double tap to expand or collapse")
                
                Button(action: copyContent) {
                    Image(systemName: showCopyConfirmation ? "checkmark" : SystemImages.copyIcon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy thought process")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            // Expanded content
            if isExpanded {
                Divider()
                    .overlay(borderColor)
                
                Text(content)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        }
        .animation(.spring(response: AppConstants.UI.springAnimationResponse, dampingFraction: AppConstants.UI.springAnimationDamping), value: isExpanded)
    }
    
    private var previewText: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        let maxLength = AppConstants.UI.previewMaxLength
        let preview = String(firstLine.prefix(maxLength))
        return preview.count < firstLine.count ? preview + "…" : preview
    }
    
    private func toggleExpanded() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        withAnimation(.spring(response: AppConstants.UI.springAnimationResponse, dampingFraction: AppConstants.UI.springAnimationDamping)) {
            isExpanded.toggle()
        }
    }
    
    private func copyContent() {
        UIPasteboard.general.string = content
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showCopyConfirmation = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showCopyConfirmation = false
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ThinkingBlockView(content: """
        Okay, the user said, "Hi!" and I need to respond appropriately. First, I should acknowledge their greeting. Let me think about common greetings in many languages. Since this is an informal exchange, maybe "Hi" is too casual, so using something more respectful would be better.

        Let me try to be polite and open-ended. Perhaps I can ask something like "Hello! How are you?" that shows I'm engaging in a conversation. But since they might be checking in on the conversation flow, asking about their recent thoughts might be appropriate.

        Alternatively, keeping the response brief is good in most cases. "Hello!" is concise, and "How's your day?" keeps it natural and polite.
        """)
        
        ThinkingBlockView(content: "Short thinking content.")
    }
    .padding()
}

