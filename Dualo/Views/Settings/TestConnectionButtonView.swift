//
//  TestConnectionButtonView.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import SwiftUI

// MARK: - Connection Test Result

enum ConnectionTestResult {
    case success
    case failure(String)
}

// MARK: - Test Connection Button View

struct TestConnectionButtonView: View {
    let isAPIKeyEmpty: Bool
    let isTestingConnection: Bool
    let connectionTestResult: ConnectionTestResult?
    let onTest: () -> Void
    let onDismissResult: () -> Void

    // Rendered as a plain List row; the containing Section supplies the card styling.
    // Both buttons use .borderless so a tap only triggers the one under the finger.
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTest) {
                HStack(spacing: 12) {
                    statusIcon
                        .frame(width: 28, height: 28)

                    Text(buttonText)
                        .foregroundStyle(textColor)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(isAPIKeyEmpty || isTestingConnection)

            // Dismiss button (only visible when there's a result)
            if connectionTestResult != nil && !isTestingConnection {
                Button(action: onDismissResult) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isTestingConnection {
            ProgressView()
        } else if let result = connectionTestResult {
            switch result {
            case .success:
                SettingsIcon(systemName: "checkmark", color: .green)
            case .failure:
                SettingsIcon(systemName: "xmark", color: .red)
            }
        } else {
            SettingsIcon(systemName: "wifi", color: isAPIKeyEmpty ? .gray : .blue)
        }
    }

    private var textColor: Color {
        if isAPIKeyEmpty { return .secondary }
        switch connectionTestResult {
        case .success: return .green
        case .failure: return .red
        case nil: return .blue
        }
    }

    private var buttonText: String {
        if isTestingConnection {
            return "Testing..."
        } else if let result = connectionTestResult {
            switch result {
            case .success:
                return "Connected!"
            case .failure(let error):
                return error
            }
        } else {
            return "Test Connection"
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        TestConnectionButtonView(
            isAPIKeyEmpty: false,
            isTestingConnection: false,
            connectionTestResult: nil,
            onTest: {},
            onDismissResult: {}
        )

        TestConnectionButtonView(
            isAPIKeyEmpty: false,
            isTestingConnection: true,
            connectionTestResult: nil,
            onTest: {},
            onDismissResult: {}
        )

        TestConnectionButtonView(
            isAPIKeyEmpty: false,
            isTestingConnection: false,
            connectionTestResult: .success,
            onTest: {},
            onDismissResult: {}
        )

        TestConnectionButtonView(
            isAPIKeyEmpty: false,
            isTestingConnection: false,
            connectionTestResult: .failure("Connection failed"),
            onTest: {},
            onDismissResult: {}
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
