//
//  VoiceTranscriber.swift
//  Dualo
//
//  On-device speech-to-text for dictating messages, using the Speech framework's
//  SpeechAnalyzer with a DictationTranscriber (punctuated, with live partial results).
//

import AVFoundation
import OSLog
import Speech

/// A piece of transcribed speech. Partial (volatile) results are replaced by later ones
/// until a final result settles that stretch of audio.
struct TranscriptionUpdate: Equatable, Sendable {
    let text: String
    let isFinal: Bool
}

enum VoiceInputError: LocalizedError {
    case microphoneDenied
    case unsupportedLanguage
    case audioUnavailable

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Dualo doesn't have microphone access. You can turn it on in Settings > Apps > Dualo."
        case .unsupportedLanguage:
            return "Dictation isn't available for your device's language yet."
        case .audioUnavailable:
            return "Couldn't use the microphone. Try again in a moment."
        }
    }
}

@MainActor
protocol VoiceTranscribing: AnyObject {
    /// Starts listening. The stream yields updates until `finish()` or `cancel()`, then ends.
    func start() async throws -> AsyncThrowingStream<TranscriptionUpdate, Error>
    /// Stops listening; the stream ends once what was already heard is finalized.
    func finish() async
    /// Stops listening right away and drops anything not yet finalized.
    func cancel() async
}

@MainActor
final class SpeechAnalyzerTranscriber: VoiceTranscribing {
    private let locale: Locale
    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var audioInput: AsyncStream<AnalyzerInput>.Continuation?
    private var isRecording = false
    private var isSessionActive = false

    init(locale: Locale = .current) {
        self.locale = locale
    }

    func start() async throws -> AsyncThrowingStream<TranscriptionUpdate, Error> {
        guard await AVAudioApplication.requestRecordPermission() else {
            throw VoiceInputError.microphoneDenied
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            isSessionActive = true

            let micFormat = audioEngine.inputNode.outputFormat(forBus: 0)
            guard micFormat.sampleRate > 0 else { throw VoiceInputError.audioUnavailable }

            let (updates, feed) = try await beginAnalysis(of: micFormat)
            Self.installTap(on: audioEngine.inputNode, format: micFormat, feed: feed)
            isRecording = true
            audioEngine.prepare()
            try audioEngine.start()
            return updates
        } catch {
            await cancel()
            throw error
        }
    }

    /// Sets up the analyzer for audio in `format` and returns its updates plus a function
    /// that feeds it audio. `start()` feeds it the microphone; tests feed it a file.
    func beginAnalysis(of format: AVAudioFormat) async throws -> (AsyncThrowingStream<TranscriptionUpdate, Error>, @Sendable (AVAudioPCMBuffer) -> Void) {
        guard let supportedLocale = await DictationTranscriber.supportedLocale(equivalentTo: locale) else {
            throw VoiceInputError.unsupportedLanguage
        }
        let transcriber = DictationTranscriber(locale: supportedLocale, preset: .progressiveShortDictation)

        // The speech model is a system download, shared across apps; usually it's already there
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            Logger.voice.info("Downloading speech model for \(supportedLocale.identifier, privacy: .public)")
            try await request.downloadAndInstall()
        }

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: format) else {
            throw VoiceInputError.unsupportedLanguage
        }

        let (inputSequence, audioInput) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: analyzerFormat)
        try await analyzer.start(inputSequence: inputSequence)
        self.analyzer = analyzer
        self.audioInput = audioInput

        let updates = AsyncThrowingStream<TranscriptionUpdate, Error> { continuation in
            let task = Task {
                do {
                    for try await result in transcriber.results {
                        continuation.yield(TranscriptionUpdate(text: String(result.text.characters), isFinal: result.isFinal))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }

        let converter = format == analyzerFormat ? nil : AVAudioConverter(from: format, to: analyzerFormat)
        let feed: @Sendable (AVAudioPCMBuffer) -> Void = { buffer in
            if let converter {
                guard let converted = Self.convert(buffer, with: converter) else { return }
                audioInput.yield(AnalyzerInput(buffer: converted))
            } else {
                audioInput.yield(AnalyzerInput(buffer: buffer))
            }
        }
        return (updates, feed)
    }

    func finish() async {
        // Take the analyzer before awaiting, so a session started meanwhile isn't touched
        guard let analyzer = stop() else { return }
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            Logger.voice.error("Finishing transcription failed: \(String(describing: error), privacy: .public)")
            await analyzer.cancelAndFinishNow()
        }
    }

    func cancel() async {
        await stop()?.cancelAndFinishNow()
    }

    /// Stops the microphone and audio input, and hands back the analyzer to wind down.
    private func stop() -> SpeechAnalyzer? {
        if isRecording {
            isRecording = false
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        if isSessionActive {
            isSessionActive = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        audioInput?.finish()
        audioInput = nil
        defer { analyzer = nil }
        return analyzer
    }

    /// Kept nonisolated: the tap runs on the audio thread, not the main actor.
    nonisolated private static func installTap(on input: AVAudioInputNode, format: AVAudioFormat, feed: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            feed(buffer)
        }
    }

    /// Converts a buffer to the analyzer's format (usually a lower sample rate than the mic's).
    nonisolated private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return nil }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}
