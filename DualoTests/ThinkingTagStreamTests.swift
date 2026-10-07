//
//  ThinkingTagStreamTests.swift
//  DualoTests
//
//  Checks that local model reasoning reaches the chat in the <think> format
//  MessageContentRenderer expects.
//

import Foundation
import Synchronization
import Testing
@testable import Dualo

struct ThinkingTagStreamTests {

    private final class Output: Sendable {
        private let text = Mutex("")
        var value: String { text.withLock { $0 } }
        func append(_ chunk: String) { text.withLock { $0 += chunk } }
    }

    private func makeStream() -> (ThinkingTagStream, Output) {
        let output = Output()
        return (ThinkingTagStream { output.append($0) }, output)
    }

    @Test func reasoningIsWrappedBeforeTheAnswer() {
        let (stream, output) = makeStream()
        stream.thinking("Two plus ")
        stream.thinking("two.")
        stream.answer("It's ")
        stream.answer("4.")
        stream.finish()

        #expect(output.value == "<think>Two plus two.</think>It's 4.")
    }

    @Test func answerWithoutReasoningHasNoTags() {
        let (stream, output) = makeStream()
        stream.answer("Hello")
        stream.finish()

        #expect(output.value == "Hello")
    }

    @Test func stoppingMidThoughtClosesTheBlockOnce() {
        let (stream, output) = makeStream()
        stream.thinking("Hmm")
        stream.finish()
        stream.finish()

        #expect(output.value == "<think>Hmm</think>")
    }

    @Test func rendererShowsReasoningAndAnswerSeparately() {
        let (stream, output) = makeStream()
        stream.thinking("Let me think")
        stream.answer("Done")

        let blocks = MessageContentRenderer.parse(output.value)
        let thinking = blocks.compactMap { block -> String? in
            if case .thinkingBlock(let content, _) = block { return content }
            return nil
        }
        #expect(thinking.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } == ["Let me think"])
        #expect(blocks.count == 2)
    }
}
