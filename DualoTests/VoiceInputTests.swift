//
//  VoiceInputTests.swift
//  DualoTests
//
//  Covers turning dictation results into composer text, and VoiceInputController's
//  start/finish/cancel flow against a fake transcriber.
//

import Foundation
import Testing
@testable import Dualo

@MainActor
private final class FakeTranscriber: VoiceTranscribing {
    var startError: Error?
    var finishCalls = 0
    var cancelCalls = 0
    private(set) var continuation: AsyncThrowingStream<TranscriptionUpdate, Error>.Continuation?

    func start() async throws -> AsyncThrowingStream<TranscriptionUpdate, Error> {
        if let startError { throw startError }
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: TranscriptionUpdate.self)
        self.continuation = continuation
        return stream
    }

    func hear(_ text: String, final isFinal: Bool = false) {
        continuation?.yield(TranscriptionUpdate(text: text, isFinal: isFinal))
    }

    func finish() async {
        finishCalls += 1
        continuation?.finish()
    }

    func cancel() async {
        cancelCalls += 1
        continuation?.finish()
    }
}

/// Lets the controller's tasks run until `condition` holds (or a second passes).
@MainActor
private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<100 where !condition() {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

struct TranscriptAccumulatorTests {

    @Test func partialResultsReplaceEachOther() {
        var transcript = TranscriptAccumulator()
        transcript.apply(TranscriptionUpdate(text: "what", isFinal: false))
        transcript.apply(TranscriptionUpdate(text: "what is the", isFinal: false))

        #expect(transcript.text == "what is the")
    }

    @Test func finalResultsAccumulateWithTheNextPartialAfterThem() {
        var transcript = TranscriptAccumulator()
        transcript.apply(TranscriptionUpdate(text: "What is the weather?", isFinal: true))
        transcript.apply(TranscriptionUpdate(text: " And tomor", isFinal: false))

        #expect(transcript.text == "What is the weather? And tomor")

        transcript.apply(TranscriptionUpdate(text: "And tomorrow?", isFinal: true))
        #expect(transcript.text == "What is the weather? And tomorrow?")
    }

    @Test(arguments: [
        ("", "hello", "hello"),
        ("  ", "hello", "hello"),
        ("Note:", "hello", "Note: hello"),
        ("Note: ", "hello", "Note: hello"),
        ("Typed", "", "Typed")
    ])
    func dictationIsAddedAfterTypedText(_ base: String, _ transcript: String, _ expected: String) {
        #expect(VoiceInputController.compose(base: base, transcript: transcript) == expected)
    }
}

@MainActor
struct VoiceInputControllerTests {

    private let transcriber = FakeTranscriber()
    private let controller: VoiceInputController

    init() {
        controller = VoiceInputController(transcriber: transcriber)
    }

    @Test func listensAndBuildsTheTranscript() async {
        controller.start()
        #expect(controller.state == .starting)
        await waitUntil { controller.state == .listening }

        transcriber.hear("Hello")
        transcriber.hear("Hello there")
        await waitUntil { controller.transcript == "Hello there" }
        #expect(controller.transcript == "Hello there")
    }

    @Test func finishingKeepsTheFinalWordingThenGoesIdle() async {
        controller.start()
        await waitUntil { controller.state == .listening }
        transcriber.hear("hello there")

        controller.finish()
        #expect(controller.state == .finishing)
        transcriber.hear("Hello there.", final: true)
        await waitUntil { controller.state == .idle }

        #expect(controller.transcript == "Hello there.")
        #expect(transcriber.finishCalls == 1)
    }

    @Test func cancellingIgnoresLaterResults() async {
        controller.start()
        await waitUntil { controller.state == .listening }
        transcriber.hear("Hello")
        await waitUntil { controller.transcript == "Hello" }

        controller.cancel()
        #expect(controller.state == .idle)
        transcriber.hear("Hello again", final: true)
        await waitUntil { transcriber.cancelCalls == 1 }

        #expect(controller.transcript == "Hello")
        #expect(controller.state == .idle)
    }

    @Test func restartingRightAfterCancellingListensAgain() async {
        controller.start()
        await waitUntil { controller.state == .listening }
        controller.cancel()
        controller.start()
        await waitUntil { controller.state == .listening }
        #expect(controller.state == .listening)

        transcriber.hear("Second try")
        await waitUntil { controller.transcript == "Second try" }
        #expect(controller.transcript == "Second try")
    }

    @Test func startFailureShowsTheErrorAndGoesIdle() async {
        transcriber.startError = VoiceInputError.microphoneDenied
        controller.start()
        await waitUntil { controller.state == .idle }

        #expect(controller.errorMessage == VoiceInputError.microphoneDenied.errorDescription)
    }

    @Test func startingAgainClearsTheLastTranscript() async {
        controller.start()
        await waitUntil { controller.state == .listening }
        transcriber.hear("First", final: true)
        await waitUntil { controller.transcript == "First" }
        controller.finish()
        await waitUntil { controller.state == .idle }

        controller.start()
        #expect(controller.transcript.isEmpty)
    }
}
