//
//  ModelSetupCard.swift
//  Dualo
//
//  Shown on Home until there's a model to chat with: downloads the recommended
//  on-device model, or points to Settings for an API key.
//

import SwiftUI

struct ModelSetupCard: View {
    let model: LocalModel
    /// Why the last download didn't start, if it didn't
    let errorMessage: String?
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onUseAPIKey: () -> Void

    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 44

    /// "iPhone" or "iPad"
    private let device = UIDevice.current.localizedModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: SystemImages.iphone)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: iconSize, height: iconSize)
                    .background(Color.blue.opacity(0.15), in: .rect(cornerRadius: 12))
                    .accessibilityHidden(true)

                Text("Chat on your \(device)")
                    .font(.headline)
            }

            Text("Download \(model.displayName) to chat with an AI that runs entirely on this \(device). Your chats stay on your device, and it works without internet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            downloadControls

            Button("Use an OpenAI API key instead", action: onUseAPIKey)
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("setupUseAPIKeyButton")
        }
        .padding(20)
        .glassEffect(in: .rect(cornerRadius: 24))
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var downloadControls: some View {
        switch model.downloadState {
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress)
                    .tint(.blue)
                HStack {
                    Text("Downloading… \(Int(progress * 100))%")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .accessibilityIdentifier("setupDownloadProgress")
                    Spacer()
                    Button("Cancel", role: .cancel, action: onCancel)
                        .font(.footnote.weight(.medium))
                        .accessibilityIdentifier("setupCancelButton")
                }
                Text("Keep Dualo open until the download finishes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        default:
            VStack(spacing: 8) {
                if let error = failureMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("setupDownloadError")
                }
                Button(action: onDownload) {
                    Text(failureMessage == nil ? "Download (\(model.formattedSize))" : "Try Again")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("setupDownloadButton")

                Text("Best over Wi-Fi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var failureMessage: String? {
        if case .failed(let error) = model.downloadState { return error }
        return errorMessage
    }
}
