//
//  LocalModel.swift
//  Dualo
//
//  Local GGUF model support using LLM.swift (llama.cpp).
//

import Foundation

// MARK: - Template Type

/// Chat template types for different model families
enum TemplateType: String, Codable {
    case chatML     // ChatML format (default, works with many models)
    case gemma      // Google Gemma models
    case llama      // Meta Llama models
    case qwen       // Qwen models
}

// MARK: - Download State

enum LocalModelDownloadState: Codable, Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded(localPath: String)
    case failed(error: String)
    
    var isDownloaded: Bool {
        if case .downloaded = self { return true }
        return false
    }
    
    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
    
    var progress: Double? {
        if case .downloading(let progress) = self { return progress }
        return nil
    }
    
    var localPath: String? {
        if case .downloaded(let path) = self { return path }
        return nil
    }
}

// MARK: - Local Model

struct LocalModel: Identifiable, Codable, Equatable {
    let id: String                      // Unique identifier, e.g., "qwen3-0.6b-q4"
    let displayName: String             // e.g., "Qwen3 0.6B (Q4_K_M)"
    let huggingFaceRepo: String         // e.g., "unsloth/Qwen3-0.6B-GGUF"
    let ggufFileName: String?           // Specific GGUF file name, e.g., "Qwen3-0.6B-Q4_K_M.gguf"
    let sizeBytes: Int64                // Estimated size in bytes
    let description: String
    let recommended: Bool
    let minRAMGB: Int                   // Minimum RAM required
    let templateType: TemplateType      // Chat template type for this model
    let contextSize: Int                // Maximum context window in tokens
    var downloadState: LocalModelDownloadState
    
    /// Human-readable estimated size string (e.g., "3.86 GB")
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
    
    /// Whether this model can run on the current device
    var isCompatibleWithDevice: Bool {
        // Check if device has enough RAM
        let totalRAM = ProcessInfo.processInfo.physicalMemory
        let totalRAMGB = Int(totalRAM / (1024 * 1024 * 1024))
        return totalRAMGB >= minRAMGB
    }
    
    /// Whether this is a user-imported model (not from catalog)
    var isUserImported: Bool {
        huggingFaceRepo.isEmpty
    }
}

// MARK: - Available Models Catalog

struct LocalModelCatalog {
    /// All available local models that can be downloaded (GGUF format)
    /// These are small, efficient models suitable for mobile devices
    static let availableModels: [LocalModel] = [
        // MARK: - Recommended for Mobile
        LocalModel(
            id: "qwen3-0.6b-q4",
            displayName: "Qwen3 0.6B",
            huggingFaceRepo: "unsloth/Qwen3-0.6B-GGUF",
            ggufFileName: "Qwen3-0.6B-Q4_K_M.gguf",
            sizeBytes: 500_000_000, // ~500MB
            description: "Tiny but capable. Great for quick responses on any device. Recommended for testing.",
            recommended: true,
            minRAMGB: 2,
            templateType: .qwen,
            contextSize: 32_768, // 32K context
            downloadState: .notDownloaded
        ),
        
        // MARK: - Google Gemma 3 (Latest)
        LocalModel(
            id: "gemma-3-4b-q4",
            displayName: "Gemma 3 4B",
            huggingFaceRepo: "bartowski/google_gemma-3-4b-it-GGUF",
            ggufFileName: "google_gemma-3-4b-it-Q4_K_M.gguf",
            sizeBytes: 2_800_000_000, // ~2.8GB
            description: "Google's Gemma 3 4B (Dec 2024). State-of-the-art for its size. Requires 8GB+ RAM.",
            recommended: false,
            minRAMGB: 8,
            templateType: .gemma,
            contextSize: 8_192, // 8K context
            downloadState: .notDownloaded
        ),
        
        // MARK: - Qwen 3 Series
        LocalModel(
            id: "qwen3-1.7b-q4",
            displayName: "Qwen3 1.7B",
            huggingFaceRepo: "unsloth/Qwen3-1.7B-GGUF",
            ggufFileName: "Qwen3-1.7B-Q4_K_M.gguf",
            sizeBytes: 1_200_000_000, // ~1.2GB
            description: "Good balance of size and capability. Works well on most modern iPhones.",
            recommended: false,
            minRAMGB: 4,
            templateType: .qwen,
            contextSize: 32_768, // 32K context
            downloadState: .notDownloaded
        ),
        LocalModel(
            id: "qwen3-4b-q4",
            displayName: "Qwen3 4B",
            huggingFaceRepo: "unsloth/Qwen3-4B-GGUF",
            ggufFileName: "Qwen3-4B-Q4_K_M.gguf",
            sizeBytes: 2_700_000_000, // ~2.7GB
            description: "Powerful reasoning model from Alibaba. Great for complex tasks. Requires 8GB+ RAM.",
            recommended: false,
            minRAMGB: 8,
            templateType: .qwen,
            contextSize: 32_768, // 32K context
            downloadState: .notDownloaded
        ),
        
        // MARK: - Meta Llama 3.2 Series
        LocalModel(
            id: "llama-3.2-1b-q4",
            displayName: "Llama 3.2 1B",
            huggingFaceRepo: "bartowski/Llama-3.2-1B-Instruct-GGUF",
            ggufFileName: "Llama-3.2-1B-Instruct-Q4_K_M.gguf",
            sizeBytes: 800_000_000, // ~800MB
            description: "Meta's compact Llama model optimized for mobile. Fast and efficient.",
            recommended: false,
            minRAMGB: 3,
            templateType: .llama,
            contextSize: 131_072, // 128K context
            downloadState: .notDownloaded
        ),
        LocalModel(
            id: "llama-3.2-3b-q4",
            displayName: "Llama 3.2 3B",
            huggingFaceRepo: "bartowski/Llama-3.2-3B-Instruct-GGUF",
            ggufFileName: "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
            sizeBytes: 2_000_000_000, // ~2GB
            description: "Larger Llama model with better reasoning. Requires 6GB+ RAM.",
            recommended: false,
            minRAMGB: 6,
            templateType: .llama,
            contextSize: 131_072, // 128K context
            downloadState: .notDownloaded
        ),
        
        // MARK: - Microsoft Phi Series
        LocalModel(
            id: "phi-4-mini-q4",
            displayName: "Phi-4 Mini 3.8B",
            huggingFaceRepo: "bartowski/microsoft_Phi-4-mini-instruct-GGUF",
            ggufFileName: "microsoft_Phi-4-mini-instruct-Q4_K_M.gguf",
            sizeBytes: 2_400_000_000, // ~2.4GB
            description: "Microsoft's latest Phi-4 Mini (Jan 2025). Excellent reasoning. Requires 6GB+ RAM.",
            recommended: false,
            minRAMGB: 6,
            templateType: .chatML,
            contextSize: 16_384, // 16K context
            downloadState: .notDownloaded
        ),
        
        // MARK: - Google Gemma 2 (Older but stable)
        LocalModel(
            id: "gemma-2-2b-q4",
            displayName: "Gemma 2 2B",
            huggingFaceRepo: "bartowski/gemma-2-2b-it-GGUF",
            ggufFileName: "gemma-2-2b-it-Q4_K_M.gguf",
            sizeBytes: 1_700_000_000, // ~1.7GB
            description: "Google's Gemma 2 instruction-tuned model. Stable and reliable. Requires 6GB+ RAM.",
            recommended: false,
            minRAMGB: 6,
            templateType: .gemma,
            contextSize: 8_192, // 8K context
            downloadState: .notDownloaded
        )
    ]
    
    /// Get a model by its ID
    static func model(withId id: String) -> LocalModel? {
        availableModels.first { $0.id == id }
    }
}

// MARK: - Device Capability

struct DeviceCapability {
    /// Whether the current device supports local LLM inference
    /// GGUF models work on both simulator and device (though slower on simulator)
    static var supportsLocalLLM: Bool {
        return true // GGUF/llama.cpp works everywhere
    }
    
    /// Total device RAM in GB
    static var totalRAMGB: Int {
        let totalRAM = ProcessInfo.processInfo.physicalMemory
        return Int(totalRAM / (1024 * 1024 * 1024))
    }
    
    /// Available storage space in bytes
    static var availableStorageBytes: Int64 {
        do {
            let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage ?? 0
        } catch {
            return 0
        }
    }
    
    /// Total storage space in bytes
    static var totalStorageBytes: Int64 {
        do {
            let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let values = try fileURL.resourceValues(forKeys: [.volumeTotalCapacityKey])
            return Int64(values.volumeTotalCapacity ?? 0)
        } catch {
            return 0
        }
    }
}
