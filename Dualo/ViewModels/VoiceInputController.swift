//
//  VoiceInputController.swift
//  Dualo
//
//  Drives dictation for a message composer: start/stop state, and the running
//  transcript built from the transcriber's partial and final results.
//

import Foundation
import OSLog

/// Builds the transcript from updates: final results accumulate, and the latest
/// partial result stands in for the speech after them until it's finalized.
struct TranscriptAccumulator {
    private var finalized: [String] = []
    private var volatile = ""

    var text: String {
        (finalized + [volatile])
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    mutating func apply(_ update: TranscriptionUpdate) {
        let text = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if update.isFinal {
            if !text.isEmpty { finalized.append(text) }
            volatile = ""
        } else {
            volatile = text
        }
    }
}

@MainActor
final class VoiceInputController: ObservableObject {
    enum State {
        case idle
        /// Asking for the microphone or loading the speech model
        case starting
        case listening
        /// Stopped listening; the last words are being finalized
        case finishing
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript = ""
    @Published var errorMessage: String?

    var isActive: Bool { state != .idle }

    private let transcriber: VoiceTranscribing
    private var accumulator = TranscriptAccumulator()
    private var session: Task<Void, Never>?

    init(transcriber: VoiceTranscribing? = nil) {
        self.transcriber = transcriber ?? Self.makeDefaultTranscriber()
    }

    private static func makeDefaultTranscriber() -> VoiceTranscribing {
        #if DEBUG
        if UITestSupport.isStubbingAPI {
            return StubVoiceTranscriber()
        }
        #endif
        return SpeechAnalyzerTranscriber()
    }

    /// The composer's text with the transcript added after what was there before dictating.
    nonisolated static func compose(base: String, transcript: String) -> String {
        guard !transcript.isEmpty else { return base }
        guard !base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return transcript }
        return base.last?.isWhitespace == true ? base + transcript : base + " " + transcript
    }

    func start() {
        guard state == .idle else { return }
        state = .starting
        accumulator = TranscriptAccumulator()
        transcript = ""

        let previous = session
        session = Task {
            // A session cancelled while still starting up winds down first; they share the microphone
            await previous?.value
            do {
                guard !Task.isCancelled else { return }
                let updates = try await transcriber.start()
                guard state == .starting, !Task.isCancelled else {
                    // Cancelled while the microphone or model was getting ready
                    await transcriber.cancel()
                    return
                }
                state = .listening
                for try await update in updates {
                    guard !Task.isCancelled else { break }
                    accumulator.apply(update)
                    transcript = accumulator.text
                }
            } catch {
                if !Task.isCancelled {
                    Logger.voice.error("Dictation failed: \(String(describing: error), privacy: .public)")
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? "Dictation stopped unexpectedly. Try again."
                }
            }
            if !Task.isCancelled {
                state = .idle
            }
        }
    }

    /// Stops listening and keeps the final wording of what was said.
    func finish() {
        switch state {
        case .listening:
            state = .finishing
            Task { await transcriber.finish() }
        case .starting:
            cancel()
        case .idle, .finishing:
            break
        }
    }

    /// Stops right away. Results that arrive later are ignored, so the composer can be cleared.
    func cancel() {
        guard state != .idle else { return }
        session?.cancel() // Kept, so the next start waits for it to wind down
        state = .idle
        Task { await transcriber.cancel() }
    }
}
