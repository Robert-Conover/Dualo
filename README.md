Dualo — iOS Chat App
====================

Dualo is a native SwiftUI chat app that lets you talk to **OpenAI cloud models** and **run GGUF models fully on-device** (via llama.cpp through `LLM.swift`).

## Features

- **OpenAI + local model selection**: Per-chat model selection with streaming responses.
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
- **Cloud usage**: An OpenAI API key
- **Local usage**: Sufficient device **RAM** + **storage** for the chosen GGUF model (the app includes the `com.apple.developer.kernel.increased-memory-limit` entitlement)

## Getting started

### Build & run

1. Open `Dualo.xcodeproj` in Xcode
2. Select a simulator or device
3. Build & run (Cmd+R)

### Configure Cloud AI

Settings is a single scrollable page with grouped sections.

1. Open **Settings** (gear icon)
2. Scroll to the **Cloud AI** section
3. Enter your OpenAI API key (it's saved automatically to Keychain after a short debounce)
4. Tap **Test Connection** to verify your setup
5. Pick a model per-chat from the model picker on the Home screen

Get API keys:
- **OpenAI**: `https://platform.openai.com`

### Configure On-Device (GGUF)

1. Open **Settings**
2. In the **On-Device Models** section, tap **Manage models** (or **See all N models**) to open **Local Models**
3. Download a model (large downloads; Wi‑Fi recommended)
4. Back on the Home screen, select the downloaded model from the chat model picker under **Local Models**

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
- **Cloud**: Messages (and attached images) are sent to OpenAI over HTTPS.
- **Local**: Prompts/responses remain on-device.

## Project structure (high level)

```
Dualo/
├── DualoApp.swift                 # App entry point
├── Constants.swift                # App-wide constants / strings
├── DI/
│   └── DependencyContainer.swift  # Dependency injection container (main-actor)
├── Protocols/
│   └── ServiceProtocols.swift     # Service protocols for DI / testing
├── Models/
│   ├── APIConfiguration.swift     # Provider configs (OpenAI/Local)
│   ├── Conversation.swift         # Conversation model (provider + model per chat)
│   ├── Message.swift              # Message model + image attachments
│   └── LocalModel.swift           # GGUF catalog + template types
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
│       ├── MessageFormatterProtocol.swift
│       └── OpenAIMessageFormatter.swift
├── ViewModels/
│   └── ChatViewModel.swift        # Send/stream/stop + persistence throttling
├── Views/
│   ├── HomeView.swift             # Home screen + model picker + composer
│   ├── MainTabView.swift          # Tab-based navigation
│   ├── SimpleChatView.swift       # Chat UI + per-chat model switching + export
│   ├── ConversationsSheetView.swift # Search/rename/delete conversations
│   ├── Chat/
│   │   ├── ChatInputBar.swift     # Message input + attachments
│   │   ├── CodeBlockView.swift    # Monospace code blocks + copy
│   │   ├── MessageBubbleView.swift # Bubble rendering + attachments
│   │   ├── MessageContentView.swift # Markdown + code blocks
│   │   ├── MessageListView.swift  # Scrollable message list
│   │   └── ThinkingBlockView.swift # AI thinking/reasoning display
│   ├── Components/
│   │   ├── ContextUsageIndicator.swift      # Context window usage UI
│   │   ├── ImageAttachmentView.swift        # Inline + fullscreen image viewer
│   │   ├── LocalModelStreamingIndicator.swift # Local model streaming status
│   │   └── ToastView.swift                  # Toast notification popups
│   └── Settings/
│       ├── SettingsView.swift            # Unified settings page (Cloud + On-Device sections)
│       ├── SettingsRow.swift             # Shared settings row components
│       ├── APIKeyInputView.swift         # OpenAI API key entry + validation
│       ├── TestConnectionButtonView.swift # Cloud connection test UI
│       ├── ResourcesCardView.swift       # Provider resource links
│       └── LocalModelsView.swift         # Local model download management UI
├── Utilities/
│   └── HapticFeedback.swift       # Haptic feedback utilities
└── Extensions/
    ├── Color+Theme.swift
    ├── Compatibility+Extensions.swift
    └── View+Extensions.swift
```

## Built-in model lists

### Cloud (curated defaults)

OpenAI:
- `gpt-5.2` (default)
- `gpt-5-mini`
- `gpt-5-nano`
- `o3`
- `o4-mini`
- `gpt-4.1`

### Local (GGUF)

Local models are defined in `Dualo/Models/LocalModel.swift` and downloaded directly from Hugging Face (GGUF files). The catalog includes small/mobile-friendly options like Qwen, Gemma, Llama, Phi, and Mistral variants.

## Troubleshooting

- **“Please configure your API settings first”**: Open Settings → Cloud AI, set an API key, and pick a model.
- **Image requests fail**: Ensure the chosen cloud model supports vision/image input.
- **Local model won’t load / crashes**: Pick a smaller GGUF model (device RAM matters), and ensure enough free storage.
- **Downloads fail**: Check connectivity and try again; Hugging Face hosting may throttle large downloads.
- **Rate limiting**: Wait and retry, or check your provider plan limits.

## License

This project appears intended for educational/personal use. Review OpenAI terms before using in production.
