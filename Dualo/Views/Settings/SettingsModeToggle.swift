//
//  SettingsModeToggle.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI

// MARK: - Settings Mode

enum SettingsMode: String, CaseIterable {
    case local = "On-Device"
    case cloud = "Cloud AI"

    var icon: String {
        switch self {
        case .cloud: return "cloud.fill"
        case .local: return "iphone"
        }
    }

    var description: String {
        switch self {
        case .cloud: return "Use Anthropic or OpenAI APIs"
        case .local: return "Run models privately on device"
        }
    }
}

// MARK: - Settings Mode Toggle View

struct SettingsModeToggle: View {
    @Binding var selectedMode: SettingsMode
    @State private var animateHeader = false

    var body: some View {
        VStack(spacing: 16) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: selectedMode == .cloud
                                ? [.blue.opacity(0.3), .purple.opacity(0.2)]
                                : [.green.opacity(0.3), .mint.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .scaleEffect(animateHeader ? 1.05 : 0.95)

                Image(systemName: selectedMode.icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: selectedMode == .cloud
                                ? [.blue, .purple]
                                : [.green, .mint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.pulse.wholeSymbol, options: .speed(0.5))
            }

            Text(selectedMode.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Toggle pills
            HStack(spacing: 0) {
                ForEach(SettingsMode.allCases, id: \.self) { mode in
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            selectedMode = mode
                        }
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 14, weight: .semibold))
                            Text(mode.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(selectedMode == mode ? .white : .secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background {
                            if selectedMode == mode {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: mode == .cloud
                                                ? [.blue, .purple.opacity(0.8)]
                                                : [.green, .mint.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: mode == .cloud ? .blue.opacity(0.3) : .green.opacity(0.3), radius: 8, y: 4)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                Capsule()
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .padding(.vertical, 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                animateHeader = true
            }
        }
    }
}

#Preview {
    SettingsModeToggle(selectedMode: .constant(.cloud))
        .padding()
        .background(Color(.systemGroupedBackground))
}
