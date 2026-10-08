//
//  ModelSelectorMenu.swift
//  Dualo
//

import SwiftUI

/// Toolbar menu for switching the current chat between cloud and downloaded local models.
struct ModelSelectorMenu: View {
    let currentModel: String
    let currentProvider: APIProvider
    /// Disabled while streaming or loading, since switching mid-generation can crash.
    let isDisabled: Bool
    let onSelectCloudModel: (String, APIProvider) -> Void
    let onSelectLocalModel: (LocalModel) -> Void

    @EnvironmentObject var localModelManager: LocalModelManager

    var body: some View {
        Menu {
            cloudProvidersSection
            localModelsSection
        } label: {
            label
        }
        .disabled(isDisabled)
    }

    @ViewBuilder
    private var cloudProvidersSection: some View {
        ForEach([APIProvider.openai], id: \.self) { provider in
            Section(provider.displayName) {
                ForEach(provider.availableModels, id: \.self) { model in
                    Button(action: {
                        onSelectCloudModel(model, provider)
                    }) {
                        HStack {
                            Text(modelDisplayName(for: model))
                            if model == currentModel && provider == currentProvider {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(!ModelUtilities.isConfigured(provider, downloadedModels: localModelManager.downloadedModels))
                }
            }
        }
    }

    @ViewBuilder
    private var localModelsSection: some View {
        Section(StringConstants.UI.localModelsTitle) {
            if localModelManager.downloadedModels.isEmpty {
                Text(StringConstants.UI.noModelsDownloaded)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(localModelManager.downloadedModels) { model in
                    Button(action: {
                        onSelectLocalModel(model)
                    }) {
                        HStack {
                            Text(model.displayName)
                            if currentProvider == .local && currentModel == model.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(!DeviceCapability.supportsLocalLLM)
                }
            }
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: ModelUtilities.icon(for: currentProvider))
                .font(.system(size: 12, weight: .medium))

            Text(modelDisplayName(for: currentModel))
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 6)
    }

    private func modelDisplayName(for model: String) -> String {
        ModelUtilities.displayName(for: model, localModels: localModelManager.availableModels)
    }
}
