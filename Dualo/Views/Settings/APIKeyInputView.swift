//
//  APIKeyInputView.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI

// MARK: - API Key Input View

struct APIKeyInputView: View {
    let provider: APIProvider
    @Binding var apiKey: String
    let validationError: String?
    let onKeyChange: (String) -> Void

    @FocusState private var isInputFocused: Bool

    // Rendered as a plain List row; the containing Section supplies the card styling.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                SettingsIcon(systemName: "key.fill", color: .orange)

                SecureField("\(provider.displayName) API key", text: $apiKey)
                    .textContentType(.password)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .focused($isInputFocused)
                    .onChange(of: apiKey) { _, newValue in
                        onKeyChange(newValue)
                    }
            }

            // Inline validation error
            if let errorMessage = validationError {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, 40)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

#Preview {
    List {
        Section {
            APIKeyInputView(
                provider: .openai,
                apiKey: .constant("invalid-key"),
                validationError: "OpenAI API keys must start with 'sk-'",
                onKeyChange: { _ in }
            )
        }
    }
    .listStyle(.insetGrouped)
}
