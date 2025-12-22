//
//  LocalModelStreamingIndicator.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI

// MARK: - Local Model Streaming Indicator

struct LocalModelStreamingIndicator: View {
    let tokenCount: Int
    let startTime: Date?

    @State private var isPulsing = false

    private var elapsedTime: TimeInterval {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    private var tokensPerSecond: Double {
        guard elapsedTime > 0.5 else { return 0 } // Wait a bit before showing speed
        return Double(tokenCount) / elapsedTime
    }

    var body: some View {
        HStack(spacing: 10) {
            // Pulsing indicator - uses its own state, not tokenCount
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
                .scaleEffect(isPulsing ? 1.2 : 0.8)
                .opacity(isPulsing ? 1.0 : 0.6)

            Text("\(tokenCount)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .monospacedDigit()

            Text("tokens")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if tokensPerSecond > 0 {
                Text("•")
                    .foregroundStyle(Color(.tertiaryLabel))

                Text(String(format: "%.1f tok/s", tokensPerSecond))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.green)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    Capsule()
                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                )
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}
