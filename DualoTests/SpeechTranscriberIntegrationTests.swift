//
//  SpeechTranscriberIntegrationTests.swift
//  DualoTests
//
//  Runs a recorded question (Fixtures/dictation-sample.wav, made with macOS `say`)
//  through SpeechAnalyzerTranscriber's real transcription path. Only the microphone
//  is left out. The first run may download the system's English speech model.
//
//  Device only: the Speech framework hangs in the Simulator (and so on CI).
//  See CLAUDE.md for running unit tests on a device.
//

import AVFoundation
import Foundation
import Speech
import Testing
@testable import Dualo

private final class BundleToken {}

private let isSimulator: Bool = {
    #if targetEnvironment(simulator)
    return true
    #else
    return false
    #endif
}()

@MainActor
@Suite(.timeLimit(.minutes(3)), .disabled(if: isSimulator, "The Speech framework hangs in the Simulator; run on a device"))
struct SpeechTranscriberIntegrationTests {

    @Test func transcribesARecordedQuestion() async throws {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "dictation-sample", withExtension: "wav"))
        let file = try AVAudioFile(forReading: url)
        let transcriber = SpeechAnalyzerTranscriber(locale: Locale(identifier: "en-US"))

        let (updates, feed) = try await transcriber.beginAnalysis(of: file.processingFormat)
        let collected = Task {
            var transcript = TranscriptAccumulator()
            var count = 0
            for try await update in updates {
                transcript.apply(update)
                count += 1
            }
            return (transcript.text, count)
        }

        // Feed the file in mic-sized chunks, as the input tap would
        while file.framePosition < file.length {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096))
            try file.read(into: buffer)
            feed(buffer)
        }
        await transcriber.finish()

        let (text, updateCount) = try await collected.value
        print("[Speech test] \(updateCount) updates -> \(text)")
        #expect(text.lowercased().contains("tallest mountain"), "Transcript: \(text)")
    }
}
