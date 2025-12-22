//
//  ProviderCardView.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI

// MARK: - Provider Card View

struct ProviderCardView: View {
    let provider: APIProvider
    let isSelected: Bool
    let hasKey: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: provider == .anthropic
                                    ? [.orange.opacity(0.2), .pink.opacity(0.15)]
                                    : [.green.opacity(0.2), .mint.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)

                    Image(systemName: provider == .anthropic ? "brain" : "sparkles")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(provider == .anthropic ? .orange : .green)
                }

                // Name
                Text(provider.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                // Status badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(hasKey ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(hasKey ? "Ready" : "Setup")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(hasKey ? .green : .orange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(hasKey ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isSelected
                                    ? (provider == .anthropic ? Color.orange : Color.green)
                                    : Color.clear,
                                lineWidth: 2
                            )
                    )
                    .shadow(color: isSelected ? (provider == .anthropic ? .orange.opacity(0.15) : .green.opacity(0.15)) : .clear, radius: 8, y: 4)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

#Preview {
    HStack(spacing: 12) {
        ProviderCardView(
            provider: .anthropic,
            isSelected: true,
            hasKey: true,
            onSelect: {}
        )
        ProviderCardView(
            provider: .openai,
            isSelected: false,
            hasKey: false,
            onSelect: {}
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
