//
//  CodeBlockView.swift
//  Dualo
//
//  Created by Robert Conover on 8/13/25.
//

import SwiftUI

struct CodeBlockView: View {
    let code: String
    let language: String?
    @State private var showCopyToast = false
    @Environment(\.colorScheme) var colorScheme
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : Color(UIColor.systemGray6)
    }
    
    private var borderColor: Color {
        colorScheme == .dark ? Color(UIColor.separator).opacity(0.3) : Color(UIColor.separator).opacity(0.2)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language = language, !language.isEmpty {
                HStack {
                    Text(language.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button(action: copyCode) {
                        Image(systemName: showCopyToast ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy code block")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(backgroundColor.opacity(0.5))
                
                Divider()
                    .overlay(borderColor)
            } else {
                HStack {
                    Spacer()
                    
                    Button(action: copyCode) {
                        Image(systemName: showCopyToast ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy code block")
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.primary)
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
    }
    
    private func copyCode() {
        UIPasteboard.general.string = code
        
        HapticFeedback.light()
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showCopyToast = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showCopyToast = false
            }
        }
    }
}