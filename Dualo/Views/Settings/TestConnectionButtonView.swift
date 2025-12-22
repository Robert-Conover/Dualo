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

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTest) {
                HStack(spacing: 12) {
                    if isTestingConnection {
                        ProgressView()
                            .scaleEffect(0.9)
                    } else if let result = connectionTestResult {
                        switch result {
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failure:
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    } else {
                        Image(systemName: "wifi.circle")
                            .foregroundStyle(.blue)
                    }

                    Text(buttonText)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
            .disabled(isAPIKeyEmpty || isTestingConnection)
            .opacity(isAPIKeyEmpty ? 0.5 : 1)

            // Dismiss button (only visible when there's a result)
            if connectionTestResult != nil && !isTestingConnection {
                Button(action: onDismissResult) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                }
                .transition(.scale.combined(with: .opacity))
            }
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
