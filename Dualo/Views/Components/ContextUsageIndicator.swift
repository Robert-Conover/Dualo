//
//  ContextUsageIndicator.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI

// MARK: - Context Usage Indicator

struct ContextUsageIndicator: View {
    let usageInfo: ContextUsageInfo
    var style: Style = .full

    enum Style {
        case full       // Shows full info with progress bar
        case compact    // Just percentage badge
    }

    private var progressColor: Color {
        if usageInfo.forgetsMessages {
            return .orange // Expected in a long chat, not an error
        } else if usageInfo.isAtLimit {
            return .red
        } else if usageInfo.isNearLimit {
            return .orange
        } else {
            return .blue
        }
    }

    private var statusIcon: String {
        if usageInfo.forgetsMessages {
            return "clock.arrow.circlepath"
        } else if usageInfo.isAtLimit {
            return "exclamationmark.triangle.fill"
        } else if usageInfo.isNearLimit {
            return "exclamationmark.circle.fill"
        } else {
            return "circle.dotted"
        }
    }

    var body: some View {
        switch style {
        case .full:
            fullIndicator
        case .compact:
            compactIndicator
        }
    }

    // MARK: - Full Indicator

    private var fullIndicator: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: statusIcon)
                .font(.caption2.weight(.medium))
                .foregroundStyle(progressColor)

            // Progress bar with text
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(usageInfo.forgetsMessages ? "Forgetting oldest" : "Context")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(usageInfo.formattedUsage)
                        .font(.system(.caption2, design: .monospaced, weight: .medium))
                        .foregroundStyle(.primary)
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        Capsule()
                            .fill(Color(.systemGray5))
                            .frame(height: 4)

                        // Fill
                        Capsule()
                            .fill(progressColor)
                            .frame(width: max(0, geometry.size.width * usageInfo.usagePercentage / 100), height: 4)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: usageInfo.usagePercentage)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: 160)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(in: .capsule)
    }

    // MARK: - Compact Indicator

    private var compactIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.caption2.weight(.medium))

            Text(usageInfo.compactUsage)
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
        }
        .foregroundStyle(progressColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(progressColor.opacity(0.1))
        )
    }
}
