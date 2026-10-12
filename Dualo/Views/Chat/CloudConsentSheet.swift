//
//  CloudConsentSheet.swift
//  Dualo
//
//  Asks before the first message goes to OpenAI, saying what's sent and who
//  handles it. Closing the sheet counts as declining.
//

import SwiftUI

struct CloudConsentSheet: View {
    let onAnswer: (_ allowed: Bool) -> Void

    private static let openAIPrivacyURL = URL(string: "https://openai.com/policies/privacy-policy")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("This chat uses an OpenAI model. To get a reply, Dualo sends OpenAI:")

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Your message and the chat so far", systemImage: "text.bubble")
                        Label("Photos you attach", systemImage: "photo")
                        Label("Your custom instructions", systemImage: "text.quote")
                    }
                    .font(.body.weight(.medium))

                    Text("It's sent with your API key, and OpenAI's privacy policy covers how it's used. Chats with on-device models stay on this device.")
                        .foregroundStyle(.secondary)

                    Text("You can change this anytime in Settings.")
                        .foregroundStyle(.secondary)

                    Link("OpenAI Privacy Policy", destination: Self.openAIPrivacyURL)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .safeAreaBar(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        HapticFeedback.light()
                        onAnswer(true)
                    } label: {
                        Text("Allow")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("cloudConsentAllowButton")

                    Button("Not Now") {
                        onAnswer(false)
                    }
                    .controlSize(.large)
                    .accessibilityIdentifier("cloudConsentDeclineButton")
                }
                .padding()
            }
            .navigationTitle("Send to OpenAI?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) {
                        onAnswer(false)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    Text("Chat")
        .sheet(isPresented: .constant(true)) {
            CloudConsentSheet { _ in }
        }
}
