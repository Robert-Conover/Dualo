//
//  SettingsRow.swift
//  Dualo
//
//  Reusable row component for Settings view.
//

import SwiftUI

// MARK: - Icon Tile

/// Rounded, tinted icon tile used at the leading edge of settings rows.
struct SettingsIcon: View {
    let systemName: String
    let color: Color
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.15))
                .frame(width: size, height: size)

            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let color: Color
    var subtitle: String? = nil
    var subtitleLineLimit: Int? = nil
    var showChevron: Bool = true
    
    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemName: icon, color: color)
            
            // Title and optional subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(subtitleLineLimit)
                }
            }
            
            Spacer()
            
            // Optional chevron for navigation rows
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Gradient Row Variant (matches toggle styling)

struct SettingsRowGradient: View {
    let icon: String
    let title: String
    let gradientColors: [Color]
    var subtitle: String? = nil
    var showChevron: Bool = true
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 28
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon with gradient background
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: gradientColors.map { $0.opacity(0.2) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: iconSize, height: iconSize)
                
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            // Title and optional subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Optional chevron for navigation rows
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Static Row Variant (no chevron, for info display)

struct SettingsInfoRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemName: icon, color: color)
            
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
            
            Spacer()
            
            Text(value)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    List {
        Section("App") {
            SettingsRowGradient(
                icon: "iphone",
                title: "Manage models",
                gradientColors: [.green, .mint],
                subtitle: "On-device models"
            )
            SettingsRowGradient(
                icon: "cloud.fill",
                title: "Manage models",
                gradientColors: [.blue, .purple],
                subtitle: "Cloud API providers"
            )
            SettingsRow(icon: "person.circle", title: "Personalization", color: .purple, subtitle: "Customize your experience")
        }
        
        Section("About") {
            SettingsInfoRow(icon: "info.circle", title: "Version", value: "1.0.0", color: .gray)
        }
    }
    .listStyle(.insetGrouped)
}

