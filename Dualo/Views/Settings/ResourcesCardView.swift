//
//  ResourcesCardView.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI

// MARK: - Resources Row View

/// Rendered as a plain List row; the containing Section supplies the card styling.
struct ResourcesCardView: View {
    private var providerURL: URL? {
        URL(string: "https://platform.openai.com")
    }

    var body: some View {
        if let url = providerURL {
            Link(destination: url) {
                HStack(spacing: 12) {
                    SettingsIcon(systemName: "link", color: .blue)

                    Text("Get an OpenAI API Key")
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

#Preview {
    List {
        Section {
            ResourcesCardView()
        }
    }
    .listStyle(.insetGrouped)
}
