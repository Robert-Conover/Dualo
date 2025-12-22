//
//  ModelSelectionCardView.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI

// MARK: - Model Selection Card View

struct ModelSelectionCardView: View {
    let currentModel: String
    let isAPIKeyEmpty: Bool
    let modelSelectionView: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Default Model")
                    .font(.headline)
            } icon: {
                Image(systemName: "cpu")
                    .foregroundStyle(.purple)
            }

            NavigationLink(destination: modelSelectionView) {
                HStack {
                    Text(currentModel.isEmpty ? "Select Model" : currentModel)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.tertiarySystemGroupedBackground))
                )
            }
            .disabled(isAPIKeyEmpty)
            .opacity(isAPIKeyEmpty ? 0.5 : 1)

            if isAPIKeyEmpty {
                Label("Enter an API key to select models", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

#Preview {
    NavigationStack {
        VStack(spacing: 20) {
            ModelSelectionCardView(
                currentModel: "claude-3-5-sonnet-20241022",
                isAPIKeyEmpty: false,
                modelSelectionView: AnyView(Text("Model Selection"))
            )

            ModelSelectionCardView(
                currentModel: "",
                isAPIKeyEmpty: true,
                modelSelectionView: AnyView(Text("Model Selection"))
            )
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}
