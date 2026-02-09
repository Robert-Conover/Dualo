Dualo — iOS Chat App
====================

Dualo is a native SwiftUI chat app that lets you talk to **cloud models** (Anthropic + OpenAI) and **run GGUF models fully on-device** (via llama.cpp through `LLM.swift`).

## Features

- **Cloud providers (Anthropic + OpenAI)**: Per-chat provider + model selection, with streaming responses.
- **On-device local models (GGUF)**: Download small GGUF models from Hugging Face and run them offline for full privacy.
- **Image attachments (Cloud)**: Attach photos from the library or camera (multiple images supported) and send them with your prompt.
- **Conversation management**: Multiple chats, rename/delete, search, and automatic persistence.
- **Export**: Share conversations as **PDF**, **Markdown**, or **plain text**.
- **Markdown rendering**: Renders links, emphasis, inline code, and fenced code blocks (with a copy button).
- **Stop generation**: Cancel streaming mid-response.
- **Secure credentials**: Cloud API keys are stored in iOS Keychain.

## Tech stack

- **Language/UI**: Swift, SwiftUI
- **Concurrency**: Swift Concurrency (`async`/`await`, `AsyncThrowingStream`) + Combine (light usage)
- **Networking**: `URLSession` + true incremental SSE streaming (`URLSession.bytes(for:)`)
- **On-device LLM**: [`LLM.swift`](https://github.com/eastriverlee/LLM.swift) (llama.cpp) for GGUF inference
- **Storage**: JSON files in the app’s Documents directory (one file per conversation)
- **Security**: Keychain (`Security.framework`) for API keys
- **Media**: PhotosUI + UIKit (`PHPickerViewController`, `UIImagePickerController`) for attachments
- **Export/Share**: `UIGraphicsPDFRenderer` + `UIActivityViewController`

## Requirements

- **iOS**: 26+ (uses modern SwiftUI APIs such as `NavigationStack` and `glassEffect`)
- **Xcode**: A version that includes the iOS 26 SDK
- **Cloud usage**: An API key for Anthropic and/or OpenAI
- **Local usage**: Sufficient device **RAM** + **storage** for the chosen GGUF model (the app includes the `com.apple.developer.kernel.increased-memory-limit` entitlement)

## Getting started

### Build & run

1. Open `Dualo.xcodeproj` in Xcode
2. Select a simulator or device
3. Build & run (Cmd+R)

### Configure Cloud AI (Anthropic/OpenAI)

1. Open **Settings** (gear icon)
2. Choose **Cloud AI**
3. Pick **Anthropic** or **OpenAI**, then enter your API key
4. Select a default model
5. Use **Test Connection** to verify your setup

Get API keys:
- **Anthropic**: `https://console.anthropic.com`
- **OpenAI**: `https://platform.openai.com`

### Configure On-Device (GGUF)

1. Open **Settings**
2. Choose **On-Device**
3. Tap **Manage** to open **Local Models**
4. Download a model (large downloads; Wi‑Fi recommended)
5. Back in the chat model picker, select the downloaded model under **Local Models**

Notes:
- Local inference is **offline**. (No messages leave the device.)
- Image attachments are currently only used for **cloud** providers.

### Send images (Cloud)

In the composer, tap **+** to attach images:
- **Photo Library**
- **Take Photo**

Images are uploaded as base64 to the selected provider using that provider’s multimodal message format. Make sure your chosen model supports vision/image input.

## Data & privacy

- **Conversations**: Stored locally as JSON files under the app’s Documents directory (`Documents/Conversations/…`).
- **API keys**: Stored in **Keychain** (never committed to source).
- **Cloud**: Messages (and attached images) are sent to Anthropic/OpenAI over HTTPS.
- **Local**: Prompts/responses remain on-device.

## Project structure (high level)

```
Dualo/
├── DualoApp.swift                 # App entry point
├── Constants.swift                # App-wide constants / strings
├── DI/
│   └── DependencyContainer.swift  # Dependency injection container
├── Models/
│   ├── APIConfiguration.swift     # Provider configs (Anthropic/OpenAI/Local)
│   ├── Conversation.swift         # Conversation model (provider + model per chat)
│   ├── Message.swift              # Message model + image attachments
│   └── LocalModel.swift           # GGUF catalog + template types
├── Protocols/
│   └── ServiceProtocols.swift     # Service protocol definitions
├── Services/
│   ├── APIService.swift           # Cloud API calls + SSE streaming (+ image payloads)
│   ├── ChatExportService.swift    # PDF/Markdown/Text export
│   ├── ContextTracker.swift       # Context window usage tracking
│   ├── ConversationManager.swift  # File-based persistence + migrations
│   ├── GGUFService.swift          # Local inference via LLM.swift
│   ├── HTTPErrorHandler.swift     # HTTP error parsing + handling
│   ├── ImagePickerService.swift   # Photo library + camera access
│   ├── KeychainQueryBuilder.swift # Keychain query construction
│   ├── KeychainService.swift      # Keychain storage (per-provider configs)
│   ├── LocalModelManager.swift    # Download/delete local GGUF models
│   ├── MessageContentRenderer.swift # Markdown parsing + code block detection
│   ├── ModelUtilities.swift       # Model-related utility functions
│   ├── NetworkError.swift         # Network error types
│   └── MessageFormatters/
│       ├── AnthropicMessageFormatter.swift
│       ├── MessageFormatterProtocol.swift
│       └── OpenAIMessageFormatter.swift
├── Utilities/
│   └── HapticFeedback.swift       # Haptic feedback utilities
├── ViewModels/
│   └── ChatViewModel.swift        # Send/stream/stop + persistence throttling
├── Views/
│   ├── Chat/
│   │   ├── ChatInputBar.swift     # Message input + attachments
│   │   └── MessageListView.swift  # Scrollable message list
│   ├── CodeBlockView.swift        # Monospace code blocks + copy
│   ├── Components/
│   │   ├── ContextUsageIndicator.swift   # Context window usage UI
│   │   ├── ImageAttachmentView.swift     # Inline + fullscreen image viewer
│   │   └── LocalModelStreamingIndicator.swift # Local model streaming status
│   ├── ConversationsSheetView.swift # Search/rename/delete conversations
│   ├── HomeView.swift             # Home screen + model picker + composer
│   ├── LocalModelsView.swift      # Local model download management UI
│   ├── MainTabView.swift          # Tab-based navigation
│   ├── MessageBubbleView.swift    # Bubble rendering + attachments
│   ├── MessageContentView.swift   # Markdown + code blocks
│   ├── Settings/
│   │   ├── APIKeyInputView.swift
│   │   ├── ModelSelectionCardView.swift
│   │   ├── OnDeviceSettingsView.swift
│   │   ├── ProviderCardView.swift
│   │   ├── ResourcesCardView.swift
│   │   ├── SettingsModeToggle.swift
│   │   └── TestConnectionButtonView.swift
│   ├── SettingsView.swift         # Cloud + On-device settings
│   ├── SimpleChatView.swift       # Chat UI + per-chat model switching + export
│   ├── ThinkingBlockView.swift    # AI thinking/reasoning display
│   └── ToastView.swift            # Toast notification popups
└── Extensions/
    ├── Color+Theme.swift
    ├── Compatibility+Extensions.swift
    └── View+Extensions.swift
```

## Built-in model lists

### Cloud (curated defaults)

Anthropic:
- `claude-3-opus-20240229`
- `claude-3-sonnet-20240229` (default)
- `claude-3-haiku-20240307`

OpenAI:
- `gpt-4-turbo-preview` (default)
- `gpt-4o`
- `gpt-5`
- `gpt-5-mini`
- `gpt-5-nano`

### Local (GGUF)

Local models are defined in `Dualo/Models/LocalModel.swift` and downloaded directly from Hugging Face (GGUF files). The catalog includes small/mobile-friendly options like Qwen, Gemma, Llama, Phi, and Mistral variants.

## Troubleshooting

- **“Please configure your API settings first”**: Open Settings → Cloud AI, set an API key, and pick a model.
- **Image requests fail**: Ensure the chosen cloud model supports vision/image input.
- **Local model won’t load / crashes**: Pick a smaller GGUF model (device RAM matters), and ensure enough free storage.
- **Downloads fail**: Check connectivity and try again; Hugging Face hosting may throttle large downloads.
- **Rate limiting**: Wait and retry, or check your provider plan limits.

## License

This project appears intended for educational/personal use. Review Anthropic/OpenAI terms before using in production.
