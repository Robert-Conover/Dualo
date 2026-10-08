//
//  APIKeyLinkRow.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI

// MARK: - API Key Link Row

/// Rendered as a plain List row; the containing Section supplies the card styling.
struct APIKeyLinkRow: View {
    private static let apiKeysURL = URL(string: "https://platform.openai.com/api-keys")!

    var body: some View {
        Link(destination: Self.apiKeysURL) {
            HStack(spacing: 12) {
                SettingsIcon(systemName: "link", color: .blue)

                Text("Get an OpenAI API Key")
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

#Preview {
    List {
        Section {
            APIKeyLinkRow()
        }
    }
    .listStyle(.insetGrouped)
}
