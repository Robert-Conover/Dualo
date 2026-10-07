//
//  CustomInstructionsView.swift
//  Dualo
//
//  Edits the custom instructions every chat follows.
//

import SwiftUI

struct CustomInstructionsView: View {
    @AppStorage(CustomInstructions.key) private var instructions = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        List {
            Section {
                TextField(
                    "e.g. Keep answers short. I'm a software engineer, so skip the basics.",
                    text: $instructions,
                    axis: .vertical
                )
                .lineLimit(6...)
                .focused($isEditing)
                .accessibilityIdentifier("customInstructionsField")
                .onChange(of: instructions) { _, newValue in
                    if newValue.count > CustomInstructions.maxLength {
                        instructions = String(newValue.prefix(CustomInstructions.maxLength))
                    }
                }
            } header: {
                Text("How should Dualo respond?")
            } footer: {
                HStack(alignment: .top) {
                    Text("Every chat follows these, on cloud and on-device models.")
                    Spacer()
                    Text("\(instructions.count)/\(CustomInstructions.maxLength)")
                        .monospacedDigit()
                }
            }

            if !instructions.isEmpty {
                Section {
                    Button("Clear Instructions", role: .destructive) {
                        instructions = ""
                        HapticFeedback.light()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Custom Instructions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isEditing = false }
                }
            }
        }
        .onDisappear {
            // Drop stray whitespace so an all-blank entry reads as "Off"
            instructions = CustomInstructions.normalized(instructions)
        }
    }
}

#Preview {
    NavigationStack {
        CustomInstructionsView()
    }
}
