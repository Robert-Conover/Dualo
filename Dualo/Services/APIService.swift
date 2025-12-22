//
//  APIService.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import Foundation

protocol APIServiceProtocol {
    func sendMessage(_ message: String, history: [Message], config: APIConfiguration, attachments: [MessageAttachment], conversationId: UUID?) async throws -> String
    func streamMessage(_ message: String, history: [Message], config: APIConfiguration, attachments: [MessageAttachment], conversationId: UUID?) -> AsyncThrowingStream<String, Error>
    func fetchAvailableModels(for provider: APIProvider, apiKey: String) async throws -> [String]
}

class APIService: APIServiceProtocol {
    static let shared = APIService()
    
    private let session: URLSession
    private var currentStreamingTask: Task<Void, Never>?
    
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = AppConstants.Network.defaultTimeoutInterval
        configuration.timeoutIntervalForResource = AppConstants.Network.resourceTimeoutInterval
        self.session = URLSession(configuration: configuration)
    }
    
    func sendMessage(_ message: String, history: [Message], config: APIConfiguration, attachments: [MessageAttachment] = [], conversationId: UUID? = nil) async throws -> String {
        switch config.provider {
        case .anthropic:
            return try await sendAnthropicMessage(message, history: history, config: config, attachments: attachments)
        case .openai:
            return try await sendOpenAIMessage(message, history: history, config: config, attachments: attachments)
        case .local:
            guard let conversationId = conversationId else {
                throw NetworkError.invalidRequest("Conversation ID is required for local models")
            }
            return try await GGUFService.shared.sendMessage(message, history: history, conversationId: conversationId)
        }
    }
    
    func streamMessage(_ message: String, history: [Message], config: APIConfiguration, attachments: [MessageAttachment] = [], conversationId: UUID? = nil) -> AsyncThrowingStream<String, Error> {
        // For local models, wrap GGUFService call in a Task to handle @MainActor isolation
        if config.provider == .local {
            guard let conversationId = conversationId else {
                return AsyncThrowingStream { continuation in
                    continuation.finish(throwing: NetworkError.invalidRequest("Conversation ID is required for local models"))
                }
            }
            let convId = conversationId // Capture for sendable closure
            return AsyncThrowingStream { continuation in
                Task { @MainActor in
                    let stream = GGUFService.shared.streamMessage(message, history: history, conversationId: convId)
                    do {
                        for try await chunk in stream {
                            continuation.yield(chunk)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
        
        // Cancel any existing streaming task for cloud providers
        currentStreamingTask?.cancel()
        
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    switch config.provider {
                    case .anthropic:
                        try await streamAnthropicMessage(message, history: history, config: config, attachments: attachments, continuation: continuation)
                    case .openai:
                        try await streamOpenAIMessage(message, history: history, config: config, attachments: attachments, continuation: continuation)
                    case .local:
                        // Handled above, should not reach here
                        break
                    }
                } catch {
                    if !Task.isCancelled {
                        continuation.finish(throwing: error)
                    }
                }
            }
            
            self.currentStreamingTask = task

            continuation.onTermination = { @Sendable termination in
                switch termination {
                case .cancelled:
                    task.cancel()
                default:
                    break
                }
            }
        }
    }
    
    func stopStreaming() {
        currentStreamingTask?.cancel()
        currentStreamingTask = nil
        
        // Also stop any local model generation
        // This is safe to call even if not generating - it's a no-op
        Task { @MainActor in
            GGUFService.shared.stopGeneration()
        }
    }
    
    func fetchAvailableModels(for provider: APIProvider, apiKey: String) async throws -> [String] {
        switch provider {
        case .anthropic:
            return try await fetchAnthropicModels(apiKey: apiKey)
        case .openai:
            return try await fetchOpenAIModels(apiKey: apiKey)
        case .local:
            // Local models are managed by LocalModelManager (MainActor isolated)
            return await MainActor.run {
                LocalModelManager.shared.downloadedModels.map { $0.id }
            }
        }
    }
    
    private func sendAnthropicMessage(_ message: String, history: [Message], config: APIConfiguration, attachments: [MessageAttachment] = []) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(AppConstants.API.anthropicVersionHeader, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let messages = formatMessagesForAnthropic(currentMessage: message, history: history, attachments: attachments)

        let requestBody: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "max_tokens": AppConstants.API.defaultMaxTokens
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            throw NetworkError.invalidAPIKey
        } else if httpResponse.statusCode == 429 {
            throw NetworkError.rateLimitExceeded
        } else if httpResponse.statusCode >= 400 {
            // Enhanced error handling with provider error details for Anthropic
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorData["error"] as? [String: Any] {
                
                let message = error["message"] as? String ?? "Unknown error"
                let type = error["type"] as? String
                
                var detailedMessage = message
                if let type = type {
                    detailedMessage += " (Type: \(type))"
                }
                
                throw NetworkError.serverError(detailedMessage)
            }
            throw NetworkError.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw NetworkError.decodingError
        }
        
        return text
    }
    
    private func sendOpenAIMessage(_ message: String, history: [Message], config: APIConfiguration, attachments: [MessageAttachment] = []) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let messages = formatMessagesForOpenAI(currentMessage: message, history: history, attachments: attachments)
        
        var requestBody: [String: Any] = [
            "model": config.model,
            "messages": messages
        ]
        
        // Configure parameters based on model type
        if config.model.hasPrefix("gpt-5") {
            // GPT-5 specific parameters
            requestBody["reasoning_effort"] = AppConstants.API.gpt5ReasoningEffort
            requestBody["max_completion_tokens"] = AppConstants.API.gpt5MaxTokens  // GPT-5 uses max_completion_tokens
            // Note: GPT-5 doesn't support temperature parameter
        } else {
            // GPT-4 and other models
            requestBody["temperature"] = AppConstants.API.defaultTemperature
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            throw NetworkError.invalidAPIKey
        } else if httpResponse.statusCode == 429 {
            throw NetworkError.rateLimitExceeded
        } else if httpResponse.statusCode >= 400 {
            // Enhanced error handling with provider error details
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorData["error"] as? [String: Any] {
                
                let message = error["message"] as? String ?? "Unknown error"
                let type = error["type"] as? String
                let code = error["code"] as? String
                
                var detailedMessage = message
                if let type = type {
                    detailedMessage += " (Type: \(type))"
                }
                if let code = code {
                    detailedMessage += " (Code: \(code))"
                }
                
                throw NetworkError.serverError(detailedMessage)
            }
            throw NetworkError.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NetworkError.decodingError
        }
        
        return content
    }
    
    private func formatMessagesForAnthropic(currentMessage: String, history: [Message], attachments: [MessageAttachment] = []) -> [[String: Any]] {
        var messages: [[String: Any]] = []

        // Format history messages (may include attachments)
        for msg in history {
            if msg.hasAttachments {
                var content: [[String: Any]] = []

                // Add image blocks first for Anthropic
                for attachment in msg.attachments {
                    content.append([
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": attachment.mediaType,
                            "data": attachment.data
                        ]
                    ])
                }

                // Add text content
                if !msg.content.isEmpty {
                    content.append([
                        "type": "text",
                        "text": msg.content
                    ])
                }

                messages.append([
                    "role": msg.role,
                    "content": content
                ])
            } else {
                // Simple text message
                messages.append([
                    "role": msg.role,
                    "content": msg.content
                ])
            }
        }

        // Format current message with any new attachments
        if !attachments.isEmpty {
            var content: [[String: Any]] = []

            for attachment in attachments {
                content.append([
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": attachment.mediaType,
                        "data": attachment.data
                    ]
                ])
            }

            if !currentMessage.isEmpty {
                content.append([
                    "type": "text",
                    "text": currentMessage
                ])
            } else {
                content.append([
                    "type": "text",
                    "text": "What's in this image?"
                ])
            }

            messages.append([
                "role": "user",
                "content": content
            ])
        } else {
            messages.append([
                "role": "user",
                "content": currentMessage
            ])
        }

        return messages
    }
    
    private func formatMessagesForOpenAI(currentMessage: String, history: [Message], attachments: [MessageAttachment] = []) -> [[String: Any]] {
        var messages: [[String: Any]] = []

        // Format history messages
        for msg in history {
            if msg.hasAttachments {
                var content: [[String: Any]] = []

                // Text first for OpenAI
                if !msg.content.isEmpty {
                    content.append([
                        "type": "text",
                        "text": msg.content
                    ])
                }

                // Add image blocks
                for attachment in msg.attachments {
                    content.append([
                        "type": "image_url",
                        "image_url": [
                            "url": "data:\(attachment.mediaType);base64,\(attachment.data)"
                        ]
                    ])
                }

                messages.append([
                    "role": msg.role,
                    "content": content
                ])
            } else {
                messages.append([
                    "role": msg.role,
                    "content": msg.content
                ])
            }
        }

        // Format current message
        if !attachments.isEmpty {
            var content: [[String: Any]] = []

            // Text first for OpenAI
            if !currentMessage.isEmpty {
                content.append([
                    "type": "text",
                    "text": currentMessage
                ])
            } else {
                content.append([
                    "type": "text",
                    "text": "What's in this image?"
                ])
            }

            for attachment in attachments {
                content.append([
                    "type": "image_url",
                    "image_url": [
                        "url": "data:\(attachment.mediaType);base64,\(attachment.data)"
                    ]
                ])
            }

            messages.append([
                "role": "user",
                "content": content
            ])
        } else {
            messages.append([
                "role": "user",
                "content": currentMessage
            ])
        }

        return messages
    }
    
    private func fetchAnthropicModels(apiKey: String) async throws -> [String] {
        guard let url = URL(string: "https://api.anthropic.com/v1/models") else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(AppConstants.API.anthropicVersionHeader, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            throw NetworkError.invalidAPIKey
        } else if httpResponse.statusCode == 429 {
            throw NetworkError.rateLimitExceeded
        } else if httpResponse.statusCode >= 400 {
            // Enhanced error handling for Anthropic models fetch
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorData["error"] as? [String: Any] {
                
                let message = error["message"] as? String ?? "Unknown error"
                let type = error["type"] as? String
                
                var detailedMessage = message
                if let type = type {
                    detailedMessage += " (Type: \(type))"
                }
                
                throw NetworkError.serverError(detailedMessage)
            }
            throw NetworkError.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let data = json["data"] as? [[String: Any]] else {
            return APIProvider.anthropic.availableModels
        }
        
        let modelIds = data.compactMap { $0["id"] as? String }
            .filter { $0.contains("claude") }
            .sorted()
        
        return modelIds.isEmpty ? APIProvider.anthropic.availableModels : modelIds
    }
    
    private func fetchOpenAIModels(apiKey: String) async throws -> [String] {
        guard let url = URL(string: "https://api.openai.com/v1/models") else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            throw NetworkError.invalidAPIKey
        } else if httpResponse.statusCode == 429 {
            throw NetworkError.rateLimitExceeded
        } else if httpResponse.statusCode >= 400 {
            // Enhanced error handling for OpenAI models fetch
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorData["error"] as? [String: Any] {
                
                let message = error["message"] as? String ?? "Unknown error"
                let type = error["type"] as? String
                let code = error["code"] as? String
                
                var detailedMessage = message
                if let type = type {
                    detailedMessage += " (Type: \(type))"
                }
                if let code = code {
                    detailedMessage += " (Code: \(code))"
                }
                
                throw NetworkError.serverError(detailedMessage)
            }
            throw NetworkError.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let data = json["data"] as? [[String: Any]] else {
            return APIProvider.openai.availableModels
        }
        
        let modelIds = data.compactMap { $0["id"] as? String }
            .filter { $0.contains("gpt") || $0.contains("o1") }
            .sorted()
        
        return modelIds.isEmpty ? APIProvider.openai.availableModels : modelIds
    }
    
    // MARK: - True Incremental Streaming Implementations
    
    private func streamOpenAIMessage(_ message: String, history: [Message], config: APIConfiguration, attachments: [MessageAttachment] = [], continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            continuation.finish(throwing: NetworkError.invalidURL)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let messages = formatMessagesForOpenAI(currentMessage: message, history: history, attachments: attachments)
        
        var requestBody: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "stream": true
        ]
        
        // Configure parameters based on model type
        if config.model.hasPrefix("gpt-5") {
            requestBody["reasoning_effort"] = AppConstants.API.gpt5ReasoningEffort
            requestBody["max_completion_tokens"] = AppConstants.API.gpt5MaxTokens
        } else {
            requestBody["temperature"] = AppConstants.API.defaultTemperature
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // Use bytes(for:) for true incremental streaming
        let (bytes, response) = try await session.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            continuation.finish(throwing: NetworkError.invalidResponse)
            return
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                continuation.finish(throwing: NetworkError.invalidAPIKey)
            } else if httpResponse.statusCode == 429 {
                continuation.finish(throwing: NetworkError.rateLimitExceeded)
            } else {
                continuation.finish(throwing: NetworkError.serverError("HTTP \(httpResponse.statusCode)"))
            }
            return
        }
        
        // Process SSE stream using proper UTF-8 line decoding
        // Using .lines handles multi-byte UTF-8 characters correctly (fixes mojibake with curly quotes)
        for try await line in bytes.lines {
            if Task.isCancelled {
                continuation.finish()
                return
            }
            
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard trimmedLine.hasPrefix("data: ") else { continue }
            
            let jsonString = String(trimmedLine.dropFirst(6))
            
            if jsonString == "[DONE]" {
                continuation.finish()
                return
            }
            
            guard let jsonData = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let delta = firstChoice["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                continue
            }
            
            // Yield each chunk immediately as it arrives
            continuation.yield(content)
        }
        
        continuation.finish()
    }
    
    private func streamAnthropicMessage(_ message: String, history: [Message], config: APIConfiguration, attachments: [MessageAttachment] = [], continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            continuation.finish(throwing: NetworkError.invalidURL)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(AppConstants.API.anthropicVersionHeader, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let messages = formatMessagesForAnthropic(currentMessage: message, history: history, attachments: attachments)
        
        let requestBody: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "max_tokens": AppConstants.API.defaultMaxTokens,
            "stream": true
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // Use bytes(for:) for true incremental streaming
        let (bytes, response) = try await session.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            continuation.finish(throwing: NetworkError.invalidResponse)
            return
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                continuation.finish(throwing: NetworkError.invalidAPIKey)
            } else if httpResponse.statusCode == 429 {
                continuation.finish(throwing: NetworkError.rateLimitExceeded)
            } else {
                continuation.finish(throwing: NetworkError.serverError("HTTP \(httpResponse.statusCode)"))
            }
            return
        }
        
        // Process SSE stream using proper UTF-8 line decoding
        // Using .lines handles multi-byte UTF-8 characters correctly (fixes mojibake with curly quotes)
        for try await line in bytes.lines {
            if Task.isCancelled {
                continuation.finish()
                return
            }
            
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard trimmedLine.hasPrefix("data: ") else { continue }
            
            let jsonString = String(trimmedLine.dropFirst(6))
            
            guard let jsonData = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let type = json["type"] as? String else {
                continue
            }
            
            switch type {
            case "content_block_delta":
                if let delta = json["delta"] as? [String: Any],
                   let text = delta["text"] as? String {
                    // Yield each chunk immediately as it arrives
                    continuation.yield(text)
                }
            case "message_stop":
                continuation.finish()
                return
            case "error":
                if let error = json["error"] as? [String: Any],
                   let errorMessage = error["message"] as? String {
                    continuation.finish(throwing: NetworkError.serverError(errorMessage))
                } else {
                    continuation.finish(throwing: NetworkError.serverError("Unknown streaming error"))
                }
                return
            default:
                break // Ignore other event types like message_start, content_block_start
            }
        }
        
        continuation.finish()
    }
}