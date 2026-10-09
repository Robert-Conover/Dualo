//
//  APIService.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import Foundation

@MainActor
protocol APIServiceProtocol {
    func sendMessage(_ message: String, history: [Message], config: APIConfiguration, attachments: [MessageAttachment], conversationId: UUID?) async throws -> String
    func streamMessage(_ message: String, history: [Message], config: APIConfiguration, attachments: [MessageAttachment], conversationId: UUID?) -> AsyncThrowingStream<String, Error>
    func fetchAvailableModels(for provider: APIProvider, apiKey: String) async throws -> [String]
    func stopStreaming()
    /// A short title for a chat that starts with `message`, or nil if the provider doesn't write one
    func suggestTitle(forChatStartingWith message: String, config: APIConfiguration) async -> String?
}

@MainActor
class APIService: APIServiceProtocol {
    static let shared = APIService()

    private let session: URLSession
    private var currentStreamingTask: Task<Void, Never>?
    private let openAIFormatter = OpenAIMessageFormatter()

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = AppConstants.Network.defaultTimeoutInterval
        configuration.timeoutIntervalForResource = AppConstants.Network.resourceTimeoutInterval
        self.session = URLSession(configuration: configuration)
    }

    func sendMessage(_ message: String, history: [Message], config: APIConfiguration, attachments: [MessageAttachment] = [], conversationId: UUID? = nil) async throws -> String {
        switch config.provider {
        case .openai:
            return try await sendOpenAIMessage(message, history: history, config: config, attachments: attachments)
        case .local:
            guard let conversationId else {
                throw NetworkError.invalidRequest("Conversation ID is required for local models")
            }
            return try await GGUFService.shared.sendMessage(message, history: history, conversationId: conversationId)
        }
    }

    func streamMessage(_ message: String, history: [Message], config: APIConfiguration, attachments: [MessageAttachment] = [], conversationId: UUID? = nil) -> AsyncThrowingStream<String, Error> {
        if config.provider == .local {
            guard let conversationId else {
                let (stream, continuation) = AsyncThrowingStream.makeStream(of: String.self)
                continuation.finish(throwing: NetworkError.invalidRequest("Conversation ID is required for local models"))
                return stream
            }

            let (stream, continuation) = AsyncThrowingStream.makeStream(of: String.self)
            let innerTask = Task {
                let innerStream = GGUFService.shared.streamMessage(message, history: history, conversationId: conversationId)
                do {
                    for try await chunk in innerStream {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            currentStreamingTask = innerTask
            continuation.onTermination = { @Sendable _ in
                innerTask.cancel()
                Task { @MainActor in
                    GGUFService.shared.stopGeneration()
                }
            }
            return stream
        }

        currentStreamingTask?.cancel()

        let (stream, continuation) = AsyncThrowingStream.makeStream(of: String.self)
        let task = Task {
            do {
                try await self.streamOpenAIMessage(
                    message,
                    history: history,
                    config: config,
                    attachments: attachments,
                    continuation: continuation
                )
            } catch {
                if !Task.isCancelled {
                    continuation.finish(throwing: error)
                }
            }
        }

        currentStreamingTask = task
        continuation.onTermination = { @Sendable _ in task.cancel() }
        return stream
    }

    func stopStreaming() {
        currentStreamingTask?.cancel()
        currentStreamingTask = nil

        Task { @MainActor in
            GGUFService.shared.stopGeneration()
        }
    }

    /// Local models name their chats; cloud chats keep the title made from their first words
    func suggestTitle(forChatStartingWith message: String, config: APIConfiguration) async -> String? {
        guard config.provider == .local else { return nil }
        return await GGUFService.shared.suggestTitle(forChatStartingWith: message)
    }

    func fetchAvailableModels(for provider: APIProvider, apiKey: String) async throws -> [String] {
        switch provider {
        case .openai:
            return try await fetchOpenAIModels(apiKey: apiKey)
        case .local:
            return await MainActor.run {
                LocalModelManager.shared.downloadedModels.map { $0.id }
            }
        }
    }

    private func sendOpenAIMessage(_ message: String, history: [Message], config: APIConfiguration, attachments: [MessageAttachment] = []) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let messages = openAIFormatter.formatMessages(
            currentMessage: message,
            history: history,
            attachments: attachments,
            instructions: CustomInstructions.current
        )

        var requestBody: [String: Any] = [
            "model": config.model,
            "messages": messages
        ]

        if isReasoningModel(config.model) {
            requestBody["reasoning_effort"] = AppConstants.API.reasoningModelEffort
            requestBody["max_completion_tokens"] = AppConstants.API.reasoningModelMaxTokens
        } else {
            requestBody["temperature"] = AppConstants.API.defaultTemperature
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        try HTTPErrorHandler.handleResponse(httpResponse, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NetworkError.decodingError
        }

        return content
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

        try HTTPErrorHandler.handleResponse(httpResponse, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let data = json["data"] as? [[String: Any]] else {
            return APIProvider.openai.availableModels
        }

        let modelIds = data.compactMap { $0["id"] as? String }
            .filter { $0.hasPrefix("gpt-") || $0.hasPrefix("o") }
            .sorted()

        return modelIds.isEmpty ? APIProvider.openai.availableModels : modelIds
    }

    private func isReasoningModel(_ model: String) -> Bool {
        model.hasPrefix("gpt-6")
    }

    // MARK: - True Incremental Streaming Implementations

    private func streamOpenAIMessage(
        _ message: String,
        history: [Message],
        config: APIConfiguration,
        attachments: [MessageAttachment] = [],
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            continuation.finish(throwing: NetworkError.invalidURL)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let messages = openAIFormatter.formatMessages(
            currentMessage: message,
            history: history,
            attachments: attachments,
            instructions: CustomInstructions.current
        )

        var requestBody: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "stream": true
        ]

        if isReasoningModel(config.model) {
            requestBody["reasoning_effort"] = AppConstants.API.reasoningModelEffort
            requestBody["max_completion_tokens"] = AppConstants.API.reasoningModelMaxTokens
        } else {
            requestBody["temperature"] = AppConstants.API.defaultTemperature
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            continuation.finish(throwing: NetworkError.invalidResponse)
            return
        }

        guard httpResponse.statusCode == 200 else {
            var errorData = Data()
            do {
                for try await byte in bytes {
                    errorData.append(byte)
                    if errorData.count > 10_000 { break }
                }
            } catch {
                if httpResponse.statusCode == 401 {
                    continuation.finish(throwing: NetworkError.invalidAPIKey)
                } else if httpResponse.statusCode == 429 {
                    continuation.finish(throwing: NetworkError.rateLimitExceeded)
                } else {
                    continuation.finish(throwing: NetworkError.serverError("HTTP \(httpResponse.statusCode)"))
                }
                return
            }

            do {
                try HTTPErrorHandler.handleResponse(httpResponse, data: errorData)
            } catch {
                continuation.finish(throwing: error)
            }
            return
        }

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

            continuation.yield(content)
        }

        continuation.finish()
    }
}
