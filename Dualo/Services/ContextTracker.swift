//
//  ContextTracker.swift
//  Dualo
//
//  Tracks context window usage across all AI providers (Cloud & Local)
//

import Foundation
import SwiftUI

// MARK: - Context Usage Info

struct ContextUsageInfo {
    let estimatedTokens: Int
    let contextLimit: Int
    let provider: APIProvider
    let modelName: String
    
    var usagePercentage: Double {
        guard contextLimit > 0 else { return 0 }
        return min(Double(estimatedTokens) / Double(contextLimit) * 100, 100)
    }
    
    var isNearLimit: Bool {
        usagePercentage >= 80
    }
    
    var isAtLimit: Bool {
        usagePercentage >= 95
    }
    
    var formattedUsage: String {
        let tokensK = Double(estimatedTokens) / 1000.0
        let limitK = Double(contextLimit) / 1000.0
        
        if estimatedTokens < 1000 {
            return "\(estimatedTokens) / \(formatContextLimit(contextLimit))"
        } else {
            return String(format: "%.1fK / %.0fK", tokensK, limitK)
        }
    }
    
    var compactUsage: String {
        String(format: "%.0f%%", usagePercentage)
    }
    
    private func formatContextLimit(_ limit: Int) -> String {
        if limit >= 1000 {
            return "\(limit / 1000)K"
        }
        return "\(limit)"
    }
}

// MARK: - Context Tracker

@MainActor
class ContextTracker: ObservableObject, ContextTracking {
    static let shared = ContextTracker()
    
    // MARK: - Published Properties
    
    @Published private(set) var estimatedTokens: Int = 0
    @Published private(set) var contextLimit: Int = 0
    @Published private(set) var currentProvider: APIProvider = .anthropic
    @Published private(set) var currentModel: String = ""
    
    // MARK: - Token Estimation Constants
    
    /// Average characters per token (conservative estimate)
    /// English text averages ~4 chars/token, but code/special chars can be less
    private let charsPerToken: Double = 3.5
    
    /// Overhead tokens for system prompts, formatting, etc.
    private let systemOverhead: Int = 100
    
    // MARK: - Computed Properties
    
    var usageInfo: ContextUsageInfo {
        ContextUsageInfo(
            estimatedTokens: estimatedTokens,
            contextLimit: contextLimit,
            provider: currentProvider,
            modelName: currentModel
        )
    }
    
    var usagePercentage: Double {
        usageInfo.usagePercentage
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Configure the tracker for a specific model and provider
    func configure(model: String, provider: APIProvider, localModelManager: LocalModelManager? = nil) {
        currentModel = model
        currentProvider = provider
        
        // Get context limit based on provider
        switch provider {
        case .anthropic, .openai:
            contextLimit = APIProvider.contextSize(for: model, provider: provider)
        case .local:
            // Look up local model context size
            if let manager = localModelManager ?? LocalModelManager.shared as LocalModelManager?,
               let localModel = manager.availableModels.first(where: { $0.id == model }) {
                contextLimit = localModel.contextSize
            } else {
                contextLimit = 4096 // Conservative default for unknown local models
            }
        }
        
        print("📊 ContextTracker configured: \(model) (\(provider.displayName)) - \(contextLimit) tokens")
    }
    
    /// Update token estimate based on conversation messages
    func updateFromMessages(_ messages: [Message]) {
        var totalTokens = systemOverhead
        
        for message in messages {
            // Estimate tokens from message content
            let contentTokens = estimateTokens(for: message.content)
            totalTokens += contentTokens
            
            // Add overhead for role markers, formatting
            totalTokens += 4 // Approximate overhead per message
        }
        
        estimatedTokens = totalTokens
    }
    
    /// Add tokens from a streaming response (call during generation)
    func addStreamingTokens(_ count: Int) {
        estimatedTokens += count
    }
    
    /// Reset token count (e.g., when starting a new conversation)
    func reset() {
        estimatedTokens = 0
    }
    
    /// Estimate tokens for a piece of text
    func estimateTokens(for text: String) -> Int {
        // Simple character-based estimation
        // More accurate would be to use a tokenizer, but this works well enough
        let charCount = text.count
        return max(1, Int(Double(charCount) / charsPerToken))
    }
    
    // MARK: - Convenience Methods
    
    /// Check if we're approaching the context limit
    var isNearLimit: Bool {
        usageInfo.isNearLimit
    }
    
    /// Check if we've essentially hit the limit
    var isAtLimit: Bool {
        usageInfo.isAtLimit
    }
}

