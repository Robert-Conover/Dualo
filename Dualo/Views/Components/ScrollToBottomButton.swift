//
//  ScrollToBottomButton.swift
//  Dualo
//

import SwiftUI

/// Floating button over the message list that jumps back to the newest message.
struct ScrollToBottomButton: View {
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        if isVisible {
            Button(action: action) {
                Image(systemName: "arrow.down")
                    .font(.body.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Scroll to bottom")
            .padding(.trailing, 16)
            .padding(.bottom, 8)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.7, anchor: .bottomTrailing)
                    .combined(with: .opacity)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7)),
                removal: .scale(scale: 0.5, anchor: .bottomTrailing)
                    .combined(with: .opacity)
                    .animation(.spring(response: 0.25, dampingFraction: 0.9))
            ))
        }
    }
}
