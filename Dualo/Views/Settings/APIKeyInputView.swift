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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("API Key")
                    .font(.headline)
            } icon: {
                Image(systemName: "key.fill")
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    SecureField("Enter your \(provider.displayName) API key", text: $apiKey)
                        .textContentType(.password)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .focused($isInputFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.tertiarySystemGroupedBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(validationError != nil ? Color.red : Color.clear, lineWidth: 1)
                                )
                        )
                        .onChange(of: apiKey) { _, newValue in
                            onKeyChange(newValue)
                        }
                }

                // Inline validation error
                if let errorMessage = validationError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption)
                        Text(errorMessage)
                            .font(.caption)
                    }
                    .foregroundStyle(.red)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Label("Encrypted and stored securely in Keychain", systemImage: "lock.shield.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        APIKeyInputView(
            provider: .anthropic,
            apiKey: .constant("sk-ant-123456789"),
            validationError: nil,
            onKeyChange: { _ in }
        )

        APIKeyInputView(
            provider: .openai,
            apiKey: .constant("invalid-key"),
            validationError: "OpenAI API keys must start with 'sk-'",
            onKeyChange: { _ in }
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
