//
//  ThinkingTagStream.swift
//  Dualo
//
//  Merges LLM.swift's separate reasoning and answer streams into one string,
//  wrapping reasoning in <think> tags (the format MessageContentRenderer displays).
//

import Foundation
import Synchronization

/// LLM.swift delivers reasoning and answer deltas from two concurrent tasks, and its
/// reasoning stream only ends when generation does, so the closing tag is written
/// when the first answer text arrives. Calls are serialized by a lock.
final class ThinkingTagStream: Sendable {
    private enum Phase { case answering, thinking }

    private let phase = Mutex(Phase.answering)
    private let emit: @Sendable (String) -> Void

    init(emit: @escaping @Sendable (String) -> Void) {
        self.emit = emit
    }

    func thinking(_ text: String) {
        phase.withLock { phase in
            if phase == .answering {
                phase = .thinking
                emit("<think>" + text)
            } else {
                emit(text)
            }
        }
    }

    func answer(_ text: String) {
        phase.withLock { phase in
            if phase == .thinking {
                phase = .answering
                emit("</think>" + text)
            } else {
                emit(text)
            }
        }
    }

    /// Closes an open thinking block, e.g. when a reply is stopped mid-thought.
    func finish() {
        phase.withLock { phase in
            if phase == .thinking {
                phase = .answering
                emit("</think>")
            }
        }
    }
}
