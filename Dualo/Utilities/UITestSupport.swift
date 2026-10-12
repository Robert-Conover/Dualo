//
//  UITestSupport.swift
//  Dualo
//
//  Debug-only hooks for DualoUITests. Launching with `-UITestStubAPI` swaps the
//  cloud API for StubAPIService so chat flows can run without an API key, and
//  dictation for StubVoiceTranscriber so it needs no microphone.
//  Local models still run for real. Stubbed launches keep API settings in a keychain of
//  their own, cleared at each launch. Adding `-UITestFirstLaunch` starts the app as if
//  freshly installed: no API settings or downloaded models, and a download that only
//  pretends, then finds the model already on the simulator. Stubbed launches have
//  OpenAI already allowed unless `-UITestAskCloudConsent` is added.
//

#if DEBUG
import Foundation

enum UITestSupport {
    static let stubAPIArgument = "-UITestStubAPI"

    static var isStubbingAPI: Bool {
        ProcessInfo.processInfo.arguments.contains(stubAPIArgument)
    }

    static let firstLaunchArgument = "-UITestFirstLaunch"

    static var isSimulatingFirstLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains(firstLaunchArgument)
    }

    static let askCloudConsentArgument = "-UITestAskCloudConsent"

    /// Stubbed launches start with OpenAI already allowed, so chat tests aren't stopped by
    /// the consent sheet. Adding `-UITestAskCloudConsent` starts with it not yet asked.
    static func prepareCloudConsent() {
        guard isStubbingAPI else { return }
        let allowed = !ProcessInfo.processInfo.arguments.contains(askCloudConsentArgument)
        UserDefaults.standard.set(allowed, forKey: CloudConsent.key)
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
/// A message sent again (retried, edited unchanged or regenerated) gets "Take 2. " and so on
/// before its reply, so tests can tell the new reply from the old one.
@MainActor
final class StubAPIService: APIServiceProtocol {
    static let reply = "This is a stubbed reply streamed word by word for UI tests. It ends with STUB-END"

    private var failedOnce: Set<String> = []
    private var sendCounts: [String: Int] = [:]

    func sendMessage(_ message: String, history: [Message], config: APIConfiguration, attachments: [MessageAttachment], conversationId: UUID?) async throws -> String {
        Self.reply
    }

    func streamMessage(_ message: String, history: [Message], config: APIConfiguration, attachments: [MessageAttachment], conversationId: UUID?) -> AsyncThrowingStream<String, Error> {
        // Only the cloud API is stubbed; local models run for real
        if config.provider == .local {
            return APIService.shared.streamMessage(message, history: history, config: config, attachments: attachments, conversationId: conversationId)
        }

        let shouldFail = message.contains("[fail]") && failedOnce.insert(message).inserted
        sendCounts[message, default: 0] += 1
        let take = sendCounts[message, default: 1]
        let wordDelay: Duration = message.contains("[drip]") ? .milliseconds(400) : .milliseconds(150)
        let firstWordDelay: Duration = message.contains("[slow]") ? .seconds(3) : wordDelay
        var words: [String]
        if message.contains("[long]") {
            words = (1...60).map { "Line \($0)\n\n" } + ["STUB-END"]
        } else {
            words = Self.reply.split(separator: " ").map { String($0) + " " }
        }
        if take > 1 {
            words.insert("Take \(take). ", at: 0)
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

    func stopStreaming() {
        APIService.shared.stopStreaming()
    }

    func suggestTitle(forChatStartingWith message: String, config: APIConfiguration) async -> String? {
        await APIService.shared.suggestTitle(forChatStartingWith: message, config: config)
    }
}

/// "Hears" a fixed phrase, a few words at a time, then waits to be stopped.
@MainActor
final class StubVoiceTranscriber: VoiceTranscribing {
    static let phrase = "Hello from voice input"

    private var continuation: AsyncThrowingStream<TranscriptionUpdate, Error>.Continuation?
    private var heardTask: Task<Void, Never>?

    func start() async throws -> AsyncThrowingStream<TranscriptionUpdate, Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: TranscriptionUpdate.self)
        self.continuation = continuation
        let words = Self.phrase.split(separator: " ")
        heardTask = Task {
            for count in 1...words.count {
                try? await Task.sleep(for: .milliseconds(250))
                if Task.isCancelled { return }
                continuation.yield(TranscriptionUpdate(text: words.prefix(count).joined(separator: " "), isFinal: false))
            }
        }
        return stream
    }

    func finish() async {
        heardTask?.cancel()
        continuation?.yield(TranscriptionUpdate(text: Self.phrase + ".", isFinal: true))
        continuation?.finish()
        continuation = nil
    }

    func cancel() async {
        heardTask?.cancel()
        continuation?.finish()
        continuation = nil
    }
}
#endif
