//
//  LocalModel.swift
//  Dualo
//
//  Local GGUF model support using LLM.swift (llama.cpp).
//

import Foundation

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
    let id: String                      // Unique identifier, e.g., "qwen3.5-0.8b-q4"
    let displayName: String             // e.g., "Qwen3.5 0.8B"
    let huggingFaceRepo: String         // e.g., "unsloth/Qwen3.5-0.8B-GGUF"
    let ggufFileName: String?           // Specific GGUF file name, e.g., "Qwen3.5-0.8B-Q4_K_M.gguf"
    let sizeBytes: Int64                // Estimated size in bytes
    let description: String
    let recommended: Bool
    let minRAMGB: Int                   // Minimum RAM required
    let contextSize: Int                // Maximum context window in tokens
    var downloadState: LocalModelDownloadState
    
    /// Human-readable estimated size string (e.g., "3.86 GB")
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
    
    /// Whether this model can run on the current device
    var isCompatibleWithDevice: Bool {
        DeviceCapability.totalRAMGB >= minRAMGB
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
        // MARK: - Qwen 3.5 Series
        LocalModel(
            id: "qwen3.5-0.8b-q4",
            displayName: "Qwen3.5 0.8B",
            huggingFaceRepo: "unsloth/Qwen3.5-0.8B-GGUF",
            ggufFileName: "Qwen3.5-0.8B-Q4_K_M.gguf",
            sizeBytes: 533_000_000, // ~533MB
            description: "Tiny but capable. Great for quick responses on any device. Recommended for testing.",
            recommended: true,
            minRAMGB: 3,
            contextSize: 262_144, // 256K context
            downloadState: .notDownloaded
        ),
        LocalModel(
            id: "qwen3.5-2b-q4",
            displayName: "Qwen3.5 2B",
            huggingFaceRepo: "unsloth/Qwen3.5-2B-GGUF",
            ggufFileName: "Qwen3.5-2B-Q4_K_M.gguf",
            sizeBytes: 1_280_000_000, // ~1.28GB
            description: "Good balance of size and capability. Works well on most modern iPhones.",
            recommended: false,
            minRAMGB: 4,
            contextSize: 262_144, // 256K context
            downloadState: .notDownloaded
        ),
        LocalModel(
            id: "qwen3.5-4b-q4",
            displayName: "Qwen3.5 4B",
            huggingFaceRepo: "unsloth/Qwen3.5-4B-GGUF",
            ggufFileName: "Qwen3.5-4B-Q4_K_M.gguf",
            sizeBytes: 2_740_000_000, // ~2.74GB
            description: "Alibaba's strongest small reasoning model. Great for complex tasks. Requires 8GB+ RAM.",
            recommended: false,
            minRAMGB: 8,
            contextSize: 262_144, // 256K context
            downloadState: .notDownloaded
        ),

        // MARK: - Google Gemma 4 Series
        LocalModel(
            id: "gemma-4-e2b-q4",
            displayName: "Gemma 4 E2B",
            huggingFaceRepo: "unsloth/gemma-4-E2B-it-GGUF",
            ggufFileName: "gemma-4-E2B-it-Q4_K_M.gguf",
            sizeBytes: 3_110_000_000, // ~3.11GB
            description: "Google's Gemma 4 built for phones (2026). Fast with strong general knowledge. Requires 8GB+ RAM.",
            recommended: false,
            minRAMGB: 8,
            contextSize: 131_072, // 128K context
            downloadState: .notDownloaded
        ),
        LocalModel(
            id: "gemma-4-e4b-q4",
            displayName: "Gemma 4 E4B",
            huggingFaceRepo: "unsloth/gemma-4-E4B-it-GGUF",
            ggufFileName: "gemma-4-E4B-it-Q4_K_M.gguf",
            sizeBytes: 4_980_000_000, // ~4.98GB
            description: "The larger on-device Gemma 4. Noticeably smarter, but slower. Requires 12GB+ RAM.",
            recommended: false,
            minRAMGB: 12,
            contextSize: 131_072, // 128K context
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
            description: "Microsoft's Phi-4 Mini (2025). Excellent reasoning. Requires 6GB+ RAM.",
            recommended: false,
            minRAMGB: 6,
            contextSize: 16_384, // 16K context
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
    
    /// Total device RAM in GB, rounded up: iOS reports a bit less than the marketed
    /// amount (an 8 GB iPhone shows ~7.5), which rounding down would turn into 7
    static var totalRAMGB: Int {
        let totalRAM = Double(ProcessInfo.processInfo.physicalMemory)
        return Int((totalRAM / 1_073_741_824).rounded(.up))
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
}
