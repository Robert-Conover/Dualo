//
//  OnDeviceSettingsView.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI

// MARK: - On-Device Settings View

struct OnDeviceSettingsView: View {
    @ObservedObject var localModelManager: LocalModelManager

    var body: some View {
        VStack(spacing: 20) {
            // Models list
            modelsListCard

            // Privacy info
            privacyInfoCard
        }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    // MARK: - Models List Card

    private var modelsListCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Available Models")
                    .font(.headline)

                Spacer()

                NavigationLink(destination: LocalModelsView()) {
                    Text("Manage")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)
                }
            }

            // Quick model list
            ForEach(localModelManager.availableModels.prefix(3)) { model in
                modelQuickRow(model)
            }

            if localModelManager.availableModels.count > 3 {
                NavigationLink(destination: LocalModelsView()) {
                    HStack {
                        Text("See all \(localModelManager.availableModels.count) models")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func modelQuickRow(_ model: LocalModel) -> some View {
        HStack(spacing: 12) {
            // Icon
            modelIcon(for: model)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(localModelManager.getModelSizeString(model))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Status
            modelStatusBadge(for: model)
        }
        .padding(.vertical, 8)
    }

    private func modelIcon(for model: LocalModel) -> some View {
        let (letter, colors) = iconConfig(for: model)

        return ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: colors.map { $0.opacity(0.2) },
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 36, height: 36)

            Text(letter)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private func iconConfig(for model: LocalModel) -> (String, [Color]) {
        let name = model.displayName.lowercased()

        if name.contains("qwen") {
            return ("Q", [.purple, .blue])
        } else if name.contains("gemma") {
            return ("G", [.blue, .cyan])
        } else if name.contains("llama") {
            return ("L", [.orange, .red])
        } else if name.contains("mistral") {
            return ("M", [.indigo, .purple])
        } else {
            return ("AI", [.blue, .green])
        }
    }

    @ViewBuilder
    private func modelStatusBadge(for model: LocalModel) -> some View {
        switch model.downloadState {
        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .downloading(let progress):
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("\(Int(progress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
        case .notDownloaded:
            Text("Available")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Privacy Info Card

    private var privacyInfoCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 24))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 4) {
                Text("100% Private")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Models run entirely on your device. No data is sent to any server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.green.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            OnDeviceSettingsView(localModelManager: LocalModelManager.shared)
                .padding(.horizontal, 20)
        }
        .background(Color(.systemGroupedBackground))
    }
}
