//
//  ThinkingBlockTests.swift
//  DualoTests
//
//  `MessageContentRenderer` (display) and `GGUFService` (history cleanup) each
//  handle <think> blocks separately; these tests pin down both so they stay in sync.
//

import Testing
@testable import Dualo

struct MessageContentRendererThinkingTests {

    private func thinkingContents(_ blocks: [MessageContentRenderer.ContentType]) -> [String] {
        blocks.compactMap {
            if case .thinkingBlock(let content, _) = $0 { return content }
            return nil
        }
    }

    private func textContents(_ blocks: [MessageContentRenderer.ContentType]) -> [String] {
        blocks.compactMap {
            if case .text(let text, _) = $0 {
                return String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        }
    }

    @Test func closedThinkingBlockIsSeparatedFromAnswer() {
        let blocks = MessageContentRenderer.parse("<think>\nAdd them up.\n</think>\nThe answer is 4.")

        #expect(thinkingContents(blocks) == ["Add them up."])
        #expect(textContents(blocks) == ["The answer is 4."])
    }

    @Test func unclosedThinkingBlockMidStreamIsAllThinking() {
        let blocks = MessageContentRenderer.parse("<think>\nStill working it ou")

        #expect(thinkingContents(blocks) == ["Still working it ou"])
        #expect(textContents(blocks).isEmpty)
    }

    @Test func emptyThinkingBlockIsDropped() {
        let blocks = MessageContentRenderer.parse("<think>\n\n</think>The answer is 4.")

        #expect(thinkingContents(blocks).isEmpty)
        #expect(textContents(blocks) == ["The answer is 4."])
    }

    @Test func multipleThinkingBlocksAreAllExtracted() {
        let blocks = MessageContentRenderer.parse("<think>First</think>Middle text.<think>Second</think>The end.")

        #expect(thinkingContents(blocks) == ["First", "Second"])
        #expect(textContents(blocks) == ["Middle text.", "The end."])
    }

    @Test func plainMessageHasNoThinking() {
        let blocks = MessageContentRenderer.parse("Hello there.")

        #expect(thinkingContents(blocks).isEmpty)
        #expect(textContents(blocks) == ["Hello there."])
    }

    @Test func blockIDsAreUnique() {
        let blocks = MessageContentRenderer.parse("<think>A</think>Some text.\n```swift\nlet x = 1\n```\nMore text.")

        #expect(Set(blocks.map(\.id)).count == blocks.count)
    }

    @Test func fencedCodeBlockKeepsLanguage() {
        let blocks = MessageContentRenderer.parse("Here you go:\n```swift\nlet x = 1\n```")

        let code = blocks.compactMap { block -> (String, String?)? in
            if case .codeBlock(let code, let language, _) = block { return (code, language) }
            return nil
        }
        #expect(code.count == 1)
        #expect(code.first?.0 == "let x = 1")
        #expect(code.first?.1 == "swift")
    }
}

struct GGUFServiceThinkingTests {

    @Test func closedThinkingBlockIsStripped() {
        let stripped = GGUFService.stripThinkingBlocks(from: "<think>\nAdd them up.\n</think>\nThe answer is 4.")
        #expect(stripped == "The answer is 4.")
    }

    @Test func multipleThinkingBlocksAreStripped() {
        let stripped = GGUFService.stripThinkingBlocks(from: "<think>First</think>Middle.<think>Second</think> End.")
        #expect(stripped == "Middle. End.")
    }

    @Test func plainMessageIsUnchanged() {
        #expect(GGUFService.stripThinkingBlocks(from: "Hello there.") == "Hello there.")
    }

    /// A reply stopped mid-thought is saved with an unclosed <think>. The renderer
    /// shows it all as thinking, so it shouldn't leak into the model's history either.
    @Test func unclosedThinkingBlockIsStripped() {
        let stripped = GGUFService.stripThinkingBlocks(from: "<think>\nStill working it ou")
        #expect(stripped.isEmpty)
    }

    @Test func answerBeforeUnclosedThinkingIsKept() {
        let stripped = GGUFService.stripThinkingBlocks(from: "Partial answer.<think>More thoughts")
        #expect(stripped == "Partial answer.")
    }
}
