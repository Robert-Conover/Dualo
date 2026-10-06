//
//  UITestSupport.swift
//  Dualo
//
//  Debug-only hooks for DualoUITests. Launching with `-UITestStubAPI` swaps the
//  cloud API for StubAPIService so chat flows can run without an API key.
//

#if DEBUG
import Foundation

enum UITestSupport {
    static let stubAPIArgument = "-UITestStubAPI"

    static var isStubbingAPI: Bool {
        ProcessInfo.processInfo.arguments.contains(stubAPIArgument)
    }

    /// Stands in for a stored key so the composer and send paths treat the stub as configured.
    static func stubConfiguration(provider: APIProvider = .openai, model: String? = nil) -> APIConfiguration {
        APIConfiguration(provider: provider, apiKey: "sk-uitest-stub", model: model)
    }
}

/// Streams a canned reply one word at a time. Message text controls its behavior:
/// - `[fail]`: the first attempt fails; a retry succeeds
/// - `[slow]`: waits 3 seconds before the first word
/// - `[drip]`: streams slowly (~6 seconds), leaving time to stop mid-reply
/// - `[long]`: replies with enough lines to scroll
@MainActor
final class StubAPIService: APIServiceProtocol {
    static let reply = "This is a stubbed reply streamed word by word for UI tests. It ends with STUB-END"

    private var failedOnce: Set<String> = []

    func sendMessage(_ message: String, history: [Message], config: APIConfiguration, attachments: [MessageAttachment], conversationId: UUID?) async throws -> String {
        Self.reply
    }

    func streamMessage(_ message: String, history: [Message], config: APIConfiguration, attachments: [MessageAttachment], conversationId: UUID?) -> AsyncThrowingStream<String, Error> {
        let shouldFail = message.contains("[fail]") && failedOnce.insert(message).inserted
        let wordDelay: Duration = message.contains("[drip]") ? .milliseconds(400) : .milliseconds(150)
        let firstWordDelay: Duration = message.contains("[slow]") ? .seconds(3) : wordDelay
        let words: [String]
        if message.contains("[long]") {
            words = (1...60).map { "Line \($0)\n\n" } + ["STUB-END"]
        } else {
            words = Self.reply.split(separator: " ").map { String($0) + " " }
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                if shouldFail {
                    try? await Task.sleep(for: .milliseconds(300))
                    continuation.finish(throwing: NetworkError.networkUnavailable)
                    return
                }
                for (index, word) in words.enumerated() {
                    try? await Task.sleep(for: index == 0 ? firstWordDelay : wordDelay)
                    if Task.isCancelled { break }
                    continuation.yield(word)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func fetchAvailableModels(for provider: APIProvider, apiKey: String) async throws -> [String] {
        provider.availableModels
    }

    func stopStreaming() {}
}
#endif
