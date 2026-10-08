//
//  LocalModelsView.swift
//  Dualo
//
//  Model manager UI for downloading and managing local LLM models.
//

import SwiftUI

struct LocalModelsView: View {
    @EnvironmentObject var modelManager: LocalModelManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var showDeleteAlert = false
    @State private var modelToDelete: LocalModel?
    @State private var downloadError: String?
    @State private var showDownloadError = false
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var deleteButtonSize: CGFloat = 32
    
    var body: some View {
        List {
            // Available models section
            modelsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(StringConstants.UI.localModelsTitle)
        .navigationBarTitleDisplayMode(.large)
        .alert("Delete Model", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let model = modelToDelete {
                    deleteModel(model)
                }
            }
        } message: {
            if let model = modelToDelete {
                Text("Are you sure you want to delete \(model.displayName)? This will free up \(modelManager.getModelSizeString(model)) of storage.")
            }
        }
        .alert("Download Error", isPresented: $showDownloadError) {
            Button("OK") {}
        } message: {
            Text(downloadError ?? "An unknown error occurred")
        }
    }
    
    // MARK: - Models Section
    
    private var modelsSection: some View {
        Section {
            ForEach(modelManager.availableModels) { model in
                modelRow(model)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if model.downloadState.isDownloaded {
                            Button(role: .destructive) {
                                confirmDelete(model)
                            } label: {
                                Label("Delete", systemImage: SystemImages.trash)
                            }
                        }
                    }
            }
        } header: {
            Text("Available Models")
        } footer: {
            Text("Models are downloaded from Hugging Face in GGUF format. They run entirely offline for full privacy.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Model Row
    
    @ViewBuilder
    private func modelRow(_ model: LocalModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row with icon, name, and action button
            HStack(alignment: .top, spacing: 12) {
                // Model icon based on template type
                modelIcon(for: model)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayName)
                        .font(.headline)
                    
                    Text(model.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                
                Spacer()
                
                // Action button
                actionButton(for: model)
            }
            
            // Footer row with size and badges
            HStack(spacing: 8) {
                Text(modelManager.getModelSizeString(model))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if model.recommended {
                    Text(StringConstants.UI.recommendedBadge)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.15), in: Capsule())
                }
                
                if !model.isCompatibleWithDevice {
                    Text("Requires more RAM")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                }
                
                Spacer()
            }
            
            // Download progress bar
            if case .downloading(let progress) = model.downloadState {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                    
                    Text("Downloading... \(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Action Button
    
    @ViewBuilder
    private func actionButton(for model: LocalModel) -> some View {
        switch model.downloadState {
        case .notDownloaded:
            Button(action: { downloadModel(model) }) {
                Text(StringConstants.UI.downloadButton)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue, in: Capsule())
            }
            .disabled(!model.isCompatibleWithDevice)
            
        case .downloading:
            Button(action: { cancelDownload(model) }) {
                Text("Cancel")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.15), in: Capsule())
            }
            
        case .downloaded:
            // Delete button only - model selection happens via the model picker in chat views
            Button(action: { confirmDelete(model) }) {
                Image(systemName: SystemImages.trash)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
                    .frame(width: deleteButtonSize, height: deleteButtonSize)
                    .background(Color.red.opacity(0.15), in: Circle())
            }
            
        case .failed(let error):
            VStack(alignment: .trailing, spacing: 4) {
                Button(action: { downloadModel(model) }) {
                    Text("Retry")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.orange, in: Capsule())
                }
                
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
    }
    
    // MARK: - Model Icon
    
    @ViewBuilder
    private func modelIcon(for model: LocalModel) -> some View {
        let (letter, colors) = iconConfig(for: model)
        
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: colors.map { $0.opacity(0.2) },
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: iconSize, height: iconSize)
            
            Text(letter)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
    
    private func iconConfig(for model: LocalModel) -> (String, [Color]) {
        // Choose icon based on model name/template
        let name = model.displayName.lowercased()
        
        if name.contains("qwen") {
            return ("Q", [.purple, .blue])
        } else if name.contains("gemma") {
            return ("G", [.blue, .cyan])
        } else if name.contains("llama") {
            return ("L", [.orange, .red])
        } else if name.contains("mistral") {
            return ("M", [.indigo, .purple])
        } else if model.isUserImported {
            return ("U", [.gray, .secondary])
        } else {
            // Default
            return ("AI", [.blue, .green])
        }
    }
    
    // MARK: - Actions
    
    private func downloadModel(_ model: LocalModel) {
        Task {
            do {
                try await modelManager.downloadModel(model)
                HapticFeedback.success()
            } catch {
                downloadError = error.localizedDescription
                showDownloadError = true
                HapticFeedback.error()
            }
        }
    }
    
    private func cancelDownload(_ model: LocalModel) {
        modelManager.cancelDownload(model.id)
        HapticFeedback.light()
    }
    
    private func confirmDelete(_ model: LocalModel) {
        modelToDelete = model
        showDeleteAlert = true
    }
    
    private func deleteModel(_ model: LocalModel) {
        do {
            try modelManager.deleteModel(model)
            HapticFeedback.medium()
        } catch {
            downloadError = error.localizedDescription
            showDownloadError = true
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LocalModelsView()
            .environmentObject(LocalModelManager.shared)
    }
}

