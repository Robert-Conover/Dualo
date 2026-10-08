//
//  VoiceInputButton.swift
//  Dualo
//
//  Mic button for a message composer. Tap to dictate, tap again to stop; the
//  transcript is added after whatever was already typed.
//

import SwiftUI

struct VoiceInputButton: View {
    @ObservedObject var voiceInput: VoiceInputController
    @Binding var text: String
    @FocusState.Binding var isInputFocused: Bool
    /// Prefix for the accessibility identifier, e.g. "home" → "homeMicButton"
    let identifierPrefix: String

    @State private var textBeforeDictation = ""

    var body: some View {
        Button(action: toggle) {
            ZStack {
                switch voiceInput.state {
                case .idle:
                    Image(systemName: "mic")
                        .foregroundStyle(.secondary)
                case .starting:
                    ProgressView()
                        .controlSize(.small)
                case .listening, .finishing:
                    Image(systemName: "waveform")
                        .foregroundStyle(.red)
                        .symbolEffect(.variableColor.iterative, isActive: voiceInput.state == .listening)
                }
            }
            .font(.body.weight(.medium))
            .frame(minWidth: 26, minHeight: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(voiceInput.isActive ? "Stop Dictation" : "Dictate")
        .accessibilityIdentifier("\(identifierPrefix)MicButton")
        .onChange(of: voiceInput.transcript) { _, transcript in
            // The transcript only changes during dictation, including the final result that
            // can land as it ends (so don't check isActive). Cancelling stops it changing.
            text = VoiceInputController.compose(base: textBeforeDictation, transcript: transcript)
        }
        .onChange(of: isInputFocused) { _, focused in
            // Typing while dictating would be overwritten by the next result, so typing wins
            if focused { voiceInput.finish() }
        }
        .onDisappear {
            voiceInput.cancel()
        }
        .alert("Dictation", isPresented: Binding(
            get: { voiceInput.errorMessage != nil },
            set: { if !$0 { voiceInput.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(voiceInput.errorMessage ?? "")
        }
    }

    private func toggle() {
        HapticFeedback.light()
        if voiceInput.isActive {
            voiceInput.finish()
        } else {
            textBeforeDictation = text
            isInputFocused = false
            voiceInput.start()
        }
    }
}
