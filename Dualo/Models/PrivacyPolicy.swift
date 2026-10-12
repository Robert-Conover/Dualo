//
//  PrivacyPolicy.swift
//  Dualo
//
//  The privacy policy shown in Settings. The same text is published at
//  dualo.conov.io/privacy from site/privacy.html, and PrivacyPolicyTests checks
//  that the two match, so change both together.
//

import Foundation

enum PrivacyPolicy {
    static let effectiveDate = "October 11, 2026"
    static let contactEmail = "dualo@conov.io"
    static let webURL = URL(string: "https://dualo.conov.io/privacy")!

    struct Section: Identifiable {
        let title: String
        /// Markdown, for links
        let paragraphs: [String]

        var id: String { title }
    }

    static let sections: [Section] = [
        Section(title: "The short version", paragraphs: [
            "Dualo doesn't collect any data about you. There's no account, no analytics, no advertising and no tracking. Your chats are saved only on your device. A chat is sent to OpenAI only when it uses an OpenAI model, and only after you've allowed it."
        ]),
        Section(title: "On-device models", paragraphs: [
            "Chats with an on-device model are processed entirely on your device and never leave it.",
            "To download a model, Dualo fetches the model file from [Hugging Face](https://huggingface.co). Like any website, Hugging Face can see the request, including your IP address. No chat data is sent with it."
        ]),
        Section(title: "OpenAI models", paragraphs: [
            "Cloud models are optional and use your own OpenAI API key. When you send a message in a chat that uses an OpenAI model, Dualo sends it to OpenAI together with the earlier messages in that chat, any photos attached to them, and your custom instructions.",
            "Dualo asks for your permission before the first message is sent to OpenAI. You can withdraw it anytime in Settings, and Dualo will ask again before sending anything else.",
            "OpenAI handles this data under its own [privacy policy](https://openai.com/policies/privacy-policy) and your agreement with OpenAI. It goes straight from your device to OpenAI. The developer of Dualo never receives it."
        ]),
        Section(title: "What's stored on your device", paragraphs: [
            "Your chats, attached photos, custom instructions and settings are stored by the app on your device, and your API key is stored in the iOS Keychain. To make on-device chats faster, Dualo also keeps a temporary copy of what the model has read for a few recent chats.",
            "Deleting a chat deletes it and its temporary copy. Deleting the app deletes your chats and settings. If you back up your device, your chats are included in the backup, under Apple's terms."
        ]),
        Section(title: "Voice input", paragraphs: [
            "Dictation uses Apple's speech recognition on your device. Audio isn't recorded, saved or sent anywhere."
        ]),
        Section(title: "Sharing chats", paragraphs: [
            "When you export a chat, it goes only where you choose to share it."
        ]),
        Section(title: "Children", paragraphs: [
            "Dualo isn't directed at children under 13 and doesn't knowingly collect information from them."
        ]),
        Section(title: "Changes to this policy", paragraphs: [
            "If this policy changes, the new version will be posted at [dualo.conov.io/privacy](https://dualo.conov.io/privacy) and in the app, with a new effective date."
        ]),
        Section(title: "Contact", paragraphs: [
            "Questions about privacy? Email [dualo@conov.io](mailto:dualo@conov.io)."
        ])
    ]
}
