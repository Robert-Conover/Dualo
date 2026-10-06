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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: Circle()
                    )
                    .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 4)
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
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
