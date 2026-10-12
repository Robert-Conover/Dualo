//
//  LocalModelManager.swift
//  Dualo
//
//  Manages downloading, storage, and lifecycle of local GGUF models.
//

import Foundation
import SwiftUI
import LLM
import OSLog

// MARK: - Local Model Error

enum LocalModelError: LocalizedError {
    case modelNotFound
    case downloadFailed(String)
    case insufficientStorage
    case deletionFailed(String)
    case invalidModelPath
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Model not found"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .insufficientStorage:
            return "Not enough storage space to download this model"
        case .deletionFailed(let message):
            return "Failed to delete model: \(message)"
        case .invalidModelPath:
            return "Invalid model path"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

// MARK: - Local Model Manager

@MainActor
class LocalModelManager: ObservableObject {
    static let shared = LocalModelManager()
    
    // MARK: - Published Properties
    
    @Published var availableModels: [LocalModel] = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var isDownloading: Bool = false
    @Published var currentDownloadingModelId: String?
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private let fileManager = FileManager.default
    private var downloadTask: URLSessionDownloadTask?
    private var downloadObservation: NSKeyValueObservation?
    
    // MARK: - Storage Paths
    
    private var modelsDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent(AppConstants.LocalModels.modelsDirectoryName, isDirectory: true)
    }
    
    // MARK: - Initialization
    
    private init() {
        setupModelsDirectory()
        loadAvailableModels()
    }
    
    private func setupModelsDirectory() {
        if !fileManager.fileExists(atPath: modelsDirectory.path) {
            do {
                try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
            } catch {
                Logger.localModels.fault("Failed to create models directory: \(String(describing: error), privacy: .public)")
            }
        }
    }
    
    private func loadAvailableModels() {
        // Start with the catalog
        var models = LocalModelCatalog.availableModels
        
        // Update download states from persisted data
        if let savedStates = loadPersistedStates() {
            for (index, model) in models.enumerated() {
                if let savedState = savedStates[model.id] {
                    models[index].downloadState = savedState
                }
            }
        }
        
        // Verify downloaded models still exist on disk
        // Use the current models directory path (handles container UUID changes on iOS)
        for (index, model) in models.enumerated() {
            if case .downloaded(let path) = model.downloadState {
                // Extract just the filename from the stored path and check in current models directory
                let fileName = URL(fileURLWithPath: path).lastPathComponent
                let currentPath = modelsDirectory.appendingPathComponent(fileName)
                
                if fileManager.fileExists(atPath: currentPath.path) {
                    // File exists - update the path to the current location if it changed
                    if currentPath.path != path {
                        Logger.localModels.info("Updated model path for \(model.displayName, privacy: .public): \(currentPath.path, privacy: .public)")
                        models[index].downloadState = .downloaded(localPath: currentPath.path)
                    }
                } else {
                    Logger.localModels.warning("Model file not found at: \(currentPath.path, privacy: .public)")
                    models[index].downloadState = .notDownloaded
                }
            }
        }
        
        // Also load any user-imported models
        loadUserImportedModels(&models)

        #if DEBUG
        if UITestSupport.isSimulatingFirstLaunch {
            models = LocalModelCatalog.availableModels
        }
        #endif
        
        availableModels = models
        persistStates()
    }
    
    /// Scan models directory for user-imported GGUF files
    private func loadUserImportedModels(_ models: inout [LocalModel]) {
        do {
            let files = try fileManager.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: [.fileSizeKey])
            for file in files where file.pathExtension.lowercased() == "gguf" {
                let fullFileName = file.lastPathComponent // e.g., "Qwen3.5-0.8B-Q4_K_M.gguf"
                let fileNameWithoutExtension = file.deletingPathExtension().lastPathComponent
                
                // A catalog model's file: mark it downloaded even if its saved state was lost
                if let index = models.firstIndex(where: { $0.ggufFileName == fullFileName && !$0.isUserImported }) {
                    if !models[index].downloadState.isDownloaded {
                        models[index].downloadState = .downloaded(localPath: file.path)
                    }
                    continue
                }
                
                // Skip if already added as user-imported (by id matching filename without extension)
                if models.contains(where: { $0.id == fileNameWithoutExtension && $0.isUserImported }) {
                    continue
                }
                
                // Get file size
                let resourceValues = try file.resourceValues(forKeys: [.fileSizeKey])
                let fileSize = Int64(resourceValues.fileSize ?? 0)
                
                // Add as user-imported model
                let importedModel = LocalModel(
                    id: fileNameWithoutExtension,
                    displayName: fileNameWithoutExtension,
                    huggingFaceRepo: "",
                    ggufFileName: fullFileName,
                    sizeBytes: fileSize,
                    description: "User-imported model",
                    recommended: false,
                    minRAMGB: 4, // Conservative estimate
                    contextSize: 4096, // Conservative default for unknown models
                    downloadState: .downloaded(localPath: file.path)
                )
                models.append(importedModel)
            }
        } catch {
            Logger.localModels.error("Error scanning models directory: \(String(describing: error), privacy: .public)")
        }
    }
    
    // MARK: - Persistence
    
    private func loadPersistedStates() -> [String: LocalModelDownloadState]? {
        guard let data = UserDefaults.standard.data(forKey: AppConstants.LocalModels.downloadedModelsKey) else {
            return nil
        }
        return try? JSONDecoder().decode([String: LocalModelDownloadState].self, from: data)
    }
    
    private func persistStates() {
        #if DEBUG
        // Leave the real download states for the next normal launch
        if UITestSupport.isSimulatingFirstLaunch { return }
        #endif
        let states = Dictionary(uniqueKeysWithValues: availableModels.map { ($0.id, $0.downloadState) })
        if let data = try? JSONEncoder().encode(states) {
            UserDefaults.standard.set(data, forKey: AppConstants.LocalModels.downloadedModelsKey)
        }
    }
    
    // MARK: - Public Methods
    
    /// Get all downloaded models
    var downloadedModels: [LocalModel] {
        availableModels.filter { $0.downloadState.isDownloaded }
    }
    
    /// Get the selected local model ID
    var selectedModelId: String? {
        get {
            UserDefaults.standard.string(forKey: AppConstants.LocalModels.selectedLocalModelKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: AppConstants.LocalModels.selectedLocalModelKey)
        }
    }
    
    /// Get the currently selected model
    var selectedModel: LocalModel? {
        guard let id = selectedModelId else { return nil }
        return availableModels.first { $0.id == id && $0.downloadState.isDownloaded }
    }
    
    /// Get the local file path for a downloaded model (GGUF file)
    func getModelLocalPath(_ modelId: String) -> URL? {
        guard let model = availableModels.first(where: { $0.id == modelId }),
              case .downloaded(let localPath) = model.downloadState else {
            return nil
        }
        return URL(fileURLWithPath: localPath)
    }
    
    /// Get the Hugging Face repo ID for a model
    func getModelHuggingFaceRepo(_ modelId: String) -> String? {
        guard let model = availableModels.first(where: { $0.id == modelId }) else {
            return nil
        }
        return model.huggingFaceRepo.isEmpty ? nil : model.huggingFaceRepo
    }
    
    /// Get the full path to a downloaded model
    func getModelPath(_ modelId: String) -> URL? {
        return getModelLocalPath(modelId)
    }
    
    private func fileSize(at url: URL) -> Int64 {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
            return Int64(resourceValues.fileSize ?? 0)
        } catch {
            return 0
        }
    }
    
    /// Get the actual size of a downloaded model on disk
    func getActualModelSize(_ modelId: String) -> Int64? {
        guard let path = getModelLocalPath(modelId) else {
            return nil
        }
        let size = fileSize(at: path)
        return size > 0 ? size : nil
    }
    
    /// Get formatted size string for a model (actual if downloaded, estimated if not)
    func getModelSizeString(_ model: LocalModel) -> String {
        if let actualSize = getActualModelSize(model.id) {
            return ByteCountFormatter.string(fromByteCount: actualSize, countStyle: .file)
        } else {
            return "~\(model.formattedSize)"
        }
    }
    
    // MARK: - Download Management
    
    /// Download a GGUF model from Hugging Face
    func downloadModel(_ model: LocalModel) async throws {
        // Check storage space
        if DeviceCapability.availableStorageBytes < model.sizeBytes {
            throw LocalModelError.insufficientStorage
        }
        
        guard !model.huggingFaceRepo.isEmpty, let ggufFileName = model.ggufFileName else {
            throw LocalModelError.downloadFailed("Model has no download source")
        }
        
        // Build the download URL
        // Format: https://huggingface.co/{repo}/resolve/main/{filename}
        let downloadURLString = "https://huggingface.co/\(model.huggingFaceRepo)/resolve/main/\(ggufFileName)"
        guard let downloadURL = URL(string: downloadURLString) else {
            throw LocalModelError.downloadFailed("Invalid download URL")
        }
        
        // Destination path
        let destinationPath = modelsDirectory.appendingPathComponent(ggufFileName)
        
        // Update state
        isDownloading = true
        currentDownloadingModelId = model.id
        updateModelState(model.id, state: .downloading(progress: 0))

        #if DEBUG
        if UITestSupport.isSimulatingFirstLaunch {
            try await pretendToDownload(model, to: destinationPath)
            return
        }
        #endif
        
        Logger.localModels.info("Starting download of \(model.displayName, privacy: .public)")
        Logger.localModels.debug("URL: \(downloadURLString, privacy: .public)")
        Logger.localModels.debug("Destination: \(destinationPath.path, privacy: .public)")
        
        do {
            // Create download delegate for progress tracking
            let delegate = DownloadProgressDelegate { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.updateModelState(model.id, state: .downloading(progress: progress))
                    if Int(progress * 100) % 10 == 0 {
                        Logger.localModels.debug("Progress: \(Int(progress * 100))%")
                    }
                }
            }
            
            // Create a session with the delegate
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            
            // Use continuation to bridge delegate-based API to async/await
            let tempURL: URL = try await withCheckedThrowingContinuation { continuation in
                delegate.completionHandler = { result in
                    switch result {
                    case .success(let url):
                        continuation.resume(returning: url)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                
                let task = session.downloadTask(with: downloadURL)
                self.downloadTask = task
                task.resume()
            }
            
            // Move to final destination
            if fileManager.fileExists(atPath: destinationPath.path) {
                try fileManager.removeItem(at: destinationPath)
            }
            try fileManager.moveItem(at: tempURL, to: destinationPath)
            
            Logger.localModels.info("Model \(model.displayName, privacy: .public) downloaded successfully")
            Logger.localModels.debug("Saved to: \(destinationPath.path, privacy: .public)")
            
            // Update state
            updateModelState(model.id, state: .downloaded(localPath: destinationPath.path))
            
            // Select this model if it's the first downloaded
            if selectedModelId == nil {
                selectedModelId = model.id
            }
            
        } catch {
            // Check if this was a user-initiated cancellation (URLError.cancelled)
            // In that case, cancelDownload() already set the state to .notDownloaded
            let isCancellation = (error as? URLError)?.code == .cancelled
            
            if isCancellation {
                Logger.localModels.info("Download cancelled for \(model.displayName, privacy: .public)")
                // State already set to .notDownloaded by cancelDownload(), don't overwrite
            } else {
                Logger.localModels.error("Download failed: \(String(describing: error), privacy: .public)")
                updateModelState(model.id, state: .failed(error: error.localizedDescription))
            }
            
            isDownloading = false
            currentDownloadingModelId = nil
            
            if !isCancellation {
                throw LocalModelError.downloadFailed(error.localizedDescription)
            }
        }
        
        isDownloading = false
        currentDownloadingModelId = nil
    }
    
    #if DEBUG
    /// Shows progress for a few seconds, then marks the model downloaded if its file is
    /// already on the simulator
    private func pretendToDownload(_ model: LocalModel, to destinationPath: URL) async throws {
        defer {
            isDownloading = false
            currentDownloadingModelId = nil
        }
        for step in 1...10 {
            try? await Task.sleep(for: .milliseconds(300))
            // Cancelling sets the state back to not downloaded
            guard availableModels.first(where: { $0.id == model.id })?.downloadState.isDownloading == true else { return }
            updateModelState(model.id, state: .downloading(progress: Double(step) / 10))
        }
        guard fileManager.fileExists(atPath: destinationPath.path) else {
            updateModelState(model.id, state: .failed(error: "Model isn't on the simulator"))
            throw LocalModelError.downloadFailed("Model isn't on the simulator")
        }
        updateModelState(model.id, state: .downloaded(localPath: destinationPath.path))
        if selectedModelId == nil {
            selectedModelId = model.id
        }
    }
    #endif

    /// Cancel an ongoing download
    func cancelDownload(_ modelId: String) {
        downloadTask?.cancel()
        downloadTask = nil
        downloadObservation = nil
        
        updateModelState(modelId, state: .notDownloaded)
        
        if currentDownloadingModelId == modelId {
            isDownloading = false
            currentDownloadingModelId = nil
        }
        
        Logger.localModels.info("Download cancelled for \(modelId, privacy: .public)")
    }
    
    /// Import a GGUF model from a local file URL
    func importModel(from sourceURL: URL) throws -> LocalModel {
        let fileName = sourceURL.lastPathComponent
        let destinationPath = modelsDirectory.appendingPathComponent(fileName)
        
        // Copy file to models directory
        if fileManager.fileExists(atPath: destinationPath.path) {
            try fileManager.removeItem(at: destinationPath)
        }
        
        // Start accessing security-scoped resource
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        try fileManager.copyItem(at: sourceURL, to: destinationPath)
        
        // Get file size
        let resourceValues = try destinationPath.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = Int64(resourceValues.fileSize ?? 0)
        
        // Create model entry
        let modelId = destinationPath.deletingPathExtension().lastPathComponent
        let importedModel = LocalModel(
            id: modelId,
            displayName: modelId,
            huggingFaceRepo: "",
            ggufFileName: fileName,
            sizeBytes: fileSize,
            description: "User-imported model",
            recommended: false,
            minRAMGB: 4,
            contextSize: 4096, // Conservative default for unknown models
            downloadState: .downloaded(localPath: destinationPath.path)
        )
        
        // Add to available models if not already there
        if !availableModels.contains(where: { $0.id == modelId }) {
            availableModels.append(importedModel)
        }
        
        persistStates()
        
        Logger.localModels.info("Imported model: \(fileName, privacy: .public)")
        
        return importedModel
    }
    
    /// Delete a downloaded model and its files from disk
    func deleteModel(_ model: LocalModel) throws {
        guard case .downloaded(let localPath) = model.downloadState else {
            return
        }
        
        let modelURL = URL(fileURLWithPath: localPath)
        
        // Delete the model file
        if fileManager.fileExists(atPath: modelURL.path) {
            do {
                try fileManager.removeItem(at: modelURL)
                Logger.localModels.info("Deleted model file: \(modelURL.path, privacy: .public)")
            } catch {
                Logger.localModels.error("Failed to delete model file: \(String(describing: error), privacy: .public)")
                throw LocalModelError.deletionFailed(error.localizedDescription)
            }
        }
        
        // Update state
        if model.isUserImported {
            // Remove user-imported models from the list entirely
            availableModels.removeAll { $0.id == model.id }
        } else {
            // Reset catalog models to not downloaded
            updateModelState(model.id, state: .notDownloaded)
        }
        
        // Clear selection if this was the selected model
        if selectedModelId == model.id {
            selectedModelId = downloadedModels.first?.id
        }
        
        Logger.localModels.info("Model \(model.displayName, privacy: .public) deleted successfully")
    }
    
    // MARK: - Private Helpers
    
    private func updateModelState(_ modelId: String, state: LocalModelDownloadState) {
        if let index = availableModels.firstIndex(where: { $0.id == modelId }) {
            availableModels[index].downloadState = state
            
            if case .downloading(let progress) = state {
                downloadProgress[modelId] = progress
            } else {
                downloadProgress[modelId] = nil
            }
            
            persistStates()
        }
    }
}

// MARK: - Download Progress Delegate

private class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    private let progressHandler: (Double) -> Void
    var completionHandler: ((Result<URL, Error>) -> Void)?
    private var tempFileURL: URL?
    
    init(progressHandler: @escaping (Double) -> Void) {
        self.progressHandler = progressHandler
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler(progress)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Copy the file to a temporary location before the delegate returns
        // (the location URL becomes invalid after this method returns)
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".gguf")
            try FileManager.default.copyItem(at: location, to: tempFile)
            tempFileURL = tempFile
        } catch {
            completionHandler?(.failure(error))
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            completionHandler?(.failure(error))
        } else if let tempFileURL = tempFileURL {
            completionHandler?(.success(tempFileURL))
        } else {
            completionHandler?(.failure(LocalModelError.downloadFailed("Download completed but file not found")))
        }
    }
}
