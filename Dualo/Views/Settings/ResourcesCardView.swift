//
//  ResourcesCardView.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI

// MARK: - Resources Card View

struct ResourcesCardView: View {
    let provider: APIProvider

    private var providerURL: URL? {
        let urlString = provider == .anthropic ? "https://console.anthropic.com" : "https://platform.openai.com"
        return URL(string: urlString)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resources")
                .font(.headline)
                .foregroundStyle(.primary)

            if let url = providerURL {
                Link(destination: url) {
                    HStack {
                        Label {
                            Text("Get \(provider.displayName) API Key")
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "link")
                                .foregroundStyle(.blue)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.tertiarySystemGroupedBackground))
                    )
                }
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
    VStack(spacing: 20) {
        ResourcesCardView(provider: .anthropic)
        ResourcesCardView(provider: .openai)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
