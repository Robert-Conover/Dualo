# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Codex) when working with code in this repository.

## Build & Run

Open `Dualo.xcodeproj` in Xcode, select a simulator or device, and build (Cmd+R). iOS 26+ required.

**Build (CLI):**
```bash
xcodebuild build -project Dualo.xcodeproj -scheme Dualo -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Run tests:**
```bash
xcodebuild test -project Dualo.xcodeproj -scheme Dualo -destination 'platform=iOS Simulator,name=iPhone 16'
```
Tests use Swift Testing (`import Testing`, `@Test`). `DualoTests` covers pure logic (API key validation, HTTP error mapping, `<think>` handling, streaming throttle) and `ChatViewModel`'s send/stream/stop/retry flow against fake services; add `-only-testing:DualoTests` to skip the slow `DualoUITests`. Swap the simulator name for one installed locally (`xcrun simctl list devices available`).

LLM.swift is pinned to an exact version via SPM in the Xcode project.

## Architecture

Dualo is a SwiftUI iOS chat app supporting OpenAI cloud models and on-device GGUF models via [LLM.swift](https://github.com/eastriverlee/LLM.swift).

### Data Flow

```
HomeView/SimpleChatView
        ↓
   ChatViewModel (owns streaming state, delegates to ConversationManager)
        ↓
   APIService (cloud) or GGUFService (local)
        ↓
   ConversationManager (file-based persistence, singleton)
```

### Key Singletons

- `APIService.shared` - Cloud API calls with SSE streaming via `URLSession.bytes(for:)`
- `GGUFService.shared` - On-device LLM inference, manages model loading/context
- `ConversationManager.shared` - Conversation persistence (JSON files in Documents/Conversations/)
- `LocalModelManager.shared` - GGUF model downloads from Hugging Face
- `KeychainService.shared` - Secure API key storage
- `ContextTracker.shared` - Context-window usage tracking (injected as an `environmentObject` in `DualoApp`)

### Provider Abstraction

The `APIProvider` enum (`.openai`, `.local`) unifies the cloud and on-device backends. Each `Conversation` stores its own `provider` and `model` so users can switch models per-chat.

Anthropic support was removed; `APIProvider`'s custom decoder maps legacy `"Anthropic"` values to `.openai`. Keep this when editing the enum or saved configs will fail to load.

### Streaming Implementation

Cloud providers use true SSE streaming with `URLSession.bytes(for:)`. Local models stream tokens via `LLM.swift`'s callback. Both use `AsyncThrowingStream<String, Error>` for uniform consumption in `ChatViewModel`.

`ChatViewModel` throttles both UI updates (50ms) and disk persistence (500ms / 100 chars) during streaming to avoid excessive redraws and I/O; `StreamingThrottle` makes those decisions. `sendMessage` and `retryMessage` share one streaming path (`startStreaming`).

### Context Management

`GGUFService` tracks `currentConversationId` and resets the LLM's KV cache when switching conversations. It strips `<think>...</think>` blocks from history to save context space. Separately, `MessageContentRenderer` extracts `<think>` blocks (including unclosed ones mid-stream) for display, so changes to the reasoning format must update both. `ThinkingBlockTests` covers both sides.

### File Structure

- `Models/` - Data models (Conversation, Message, APIConfiguration, LocalModel)
- `Services/` - Business logic: the singletons above plus supporting services (`APIKeyValidator`, `ChatExportService`, `ContextTracker`, `HTTPErrorHandler`, `ImagePickerService`, `KeychainQueryBuilder`, `MessageContentRenderer`, `ModelUtilities`, `NetworkError`) and `MessageFormatters/` (protocol + `OpenAIMessageFormatter`)
- `ViewModels/` - ChatViewModel (streaming, message state, per-chat model switching) and `StreamingThrottle`
- `Views/` - SwiftUI views, organized into `Chat/`, `Components/`, and `Settings/` subfolders (plus `HomeView`, `MainTabView`, `SimpleChatView`, `ConversationsSheetView` at the root)
- `Protocols/` - `ServiceProtocols.swift` — `ConversationManaging` and `ContextTracking`, which (with `APIServiceProtocol` in `APIService.swift`) let tests inject fakes via `ChatViewModel`'s custom init; views use `.shared` directly
- `Utilities/` - `HapticFeedback`
- `Extensions/` - Theme colors, view modifiers, compatibility shims

### Constants

All magic numbers and strings live in `Constants.swift` via `AppConstants` and `StringConstants` enums.
