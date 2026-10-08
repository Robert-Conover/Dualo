# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Codex) when working with code in this repository.

## Build & Run

Open `Dualo.xcodeproj` in Xcode, select a simulator or device, and build (Cmd+R). iOS 26+ required.

**Build (CLI):**
```bash
xcodebuild build -skipMacroValidation -project Dualo.xcodeproj -scheme Dualo -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Run tests:**
```bash
xcodebuild test -skipMacroValidation -project Dualo.xcodeproj -scheme Dualo -destination 'platform=iOS Simulator,name=iPhone 16'
```
Tests use Swift Testing (`import Testing`, `@Test`). `DualoTests` covers pure logic (API key validation, retired-model migration, HTTP error mapping, `<think>` handling, streaming throttle) and `ChatViewModel`'s send/stream/stop/retry/edit/regenerate flow against fake services; add `-only-testing:DualoTests` to skip the slow `DualoUITests`. `ChatFlowUITests` drives the chat screen (send, stop, retry, scroll, rename, export) by launching with `-UITestStubAPI`, which swaps in the DEBUG-only `StubAPIService` (`Utilities/UITestSupport.swift`) so no API key is needed; markers like `[fail]`, `[slow]`, `[drip]` and `[long]` in the message control the stub, and a message sent again gets a reply starting "Take 2." so tests can tell regenerated replies apart. `GGUFServiceIntegrationTests` and `LocalModelUITests` run the real Qwen3.5 0.8B model and are skipped unless its GGUF is in the app's `Documents/Models` (see the integration tests' file header for setup). When it is, run them with `-parallel-testing-enabled NO`: in parallel clones the local-model UI tests time out. Both switch off any custom instructions left saved in the app, and the integration tests use greedy sampling (`GGUFService.useGreedySampling`), so the model gives the same replies on every run. `SpeechTranscriberIntegrationTests` transcribes a recorded clip with the real Speech framework; it only runs on a device, because the framework hangs in the Simulator. To run unit tests on the iPhone, pass `DEVELOPMENT_TEAM=A8F4R7QRHC` (the test targets have no team) and use a temporary scheme in `xcuserdata` that tests only `DualoTests`: the autocreated scheme also builds the UI-test runner, which can't be provisioned without an Xcode account. Delete the scheme afterwards, since any scheme file stops Xcode autocreating `Dualo`. Swap the simulator name for one installed locally (`xcrun simctl list devices available`).

**CI:** `.github/workflows/ci.yml` runs `DualoTests` on GitHub's `macos-26` runner (Xcode 26.6) for PRs to `main`. The repo is private and macOS minutes use the free allowance 10x faster, so CI skips the UI tests and doesn't run on pushes; run `DualoUITests` locally before merging UI changes. Keep the project buildable with Xcode 26 until the runner gets Xcode 27.

LLM.swift is vendored at `Packages/LLM.swift` (v3.0.3, referenced as a local package) with two small fixes marked `Dualo patch` in `Sources/LLM/LLM.swift`: clearing the KV cache with `llama_memory_clear`, and falling back to a full re-read when trimming the cache fails. Without them, hybrid models like Qwen3.5 crash llama.cpp on the second message. Re-apply them if you update the package. Its `@Generatable` macro needs a one-time "Trust & Enable" in Xcode; CLI builds pass `-skipMacroValidation`.

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

`ChatViewModel` throttles both UI updates (50ms) and disk persistence (500ms / 100 chars) during streaming to avoid excessive redraws and I/O; `StreamingThrottle` makes those decisions. `sendMessage`, `retryMessage` and `regenerateReply` share one streaming path (`startStreaming`). Only the last user message can be edited and only the last reply regenerated; both remove the old turns, and a local model then reloads the chat's history with the next message (`GGUFService.reloadHistoryOnNextMessage`), since it still holds those turns.

### Context Management

`GGUFService` formats chats with the template embedded in each GGUF file (falling back to ChatML when there isn't one). It tracks `currentConversationId` and resets the LLM's KV cache when switching conversations; within a conversation LLM.swift reuses the cache so only the new message is evaluated. Replies use `thinking: .suppressed`, because LLM.swift otherwise forces reasoning on and small models can think for minutes on a phone. Any reasoning a model still produces streams separately from the answer, and `ThinkingTagStream` merges them back into one string with `<think>` tags. It strips `<think>...</think>` blocks from history to save context space. The system prompt is a short base prompt plus the user's custom instructions (`CustomInstructions`, edited in Settings and read on every send, so a change applies mid-chat); cloud requests send the instructions as a `developer` message. Separately, `MessageContentRenderer` extracts `<think>` blocks (including unclosed ones mid-stream) for display, so changes to the reasoning format must update both. `ThinkingBlockTests` covers both sides.

### File Structure

- `Models/` - Data models (Conversation, Message, APIConfiguration, LocalModel)
- `Services/` - Business logic: the singletons above plus supporting services (`APIKeyValidator`, `ChatExportService`, `ContextTracker`, `HTTPErrorHandler`, `ImagePickerService`, `KeychainQueryBuilder`, `MessageContentRenderer`, `ModelUtilities`, `NetworkError`) and `MessageFormatters/` (protocol + `OpenAIMessageFormatter`)
- `ViewModels/` - ChatViewModel (streaming, message state, per-chat model switching) and `StreamingThrottle`
- `Views/` - SwiftUI views, organized into `Chat/`, `Components/`, and `Settings/` subfolders (plus `HomeView`, `MainTabView`, `SimpleChatView`, `ConversationsSheetView` at the root)
- `Protocols/` - `ServiceProtocols.swift` — `ConversationManaging` and `ContextTracking`, which (with `APIServiceProtocol` in `APIService.swift`) let tests inject fakes via `ChatViewModel`'s custom init; views use `.shared` directly
- `Utilities/` - `HapticFeedback`
- `Extensions/` - Theme colors, view modifiers, compatibility shims

### Voice Input

The mic button in both composers (`VoiceInputButton`) dictates with the Speech framework's `SpeechAnalyzer` and a `DictationTranscriber`, entirely on device. `SpeechAnalyzerTranscriber` feeds it microphone audio converted with `AVAudioConverter` (`AnalyzerInputConverter` is iOS 27 only), and `VoiceInputController` merges its partial and final results into a transcript that's added after any typed text. Sending cancels dictation so late results can't refill the cleared composer. Under `-UITestStubAPI`, `StubVoiceTranscriber` stands in for the microphone.

### UI

The app uses iOS 26's Liquid Glass through the native APIs wherever they exist. Toolbar items are plain buttons and menus, because the toolbar draws their glass (adding `.glassEffect` inside one draws a second layer). Sheets use a navigation bar with `Button(role: .close)`, `.searchable` and `ContentUnavailableView`, on the system sheet background. Both composers are `safeAreaBar`s, so content scrolls under them and they ride on top of the keyboard as it moves; don't position them from keyboard notifications, whose animation falls behind the keyboard. Choices that belong to a button, like the composers' + (`AttachmentMenu`), are a `Menu`: a `confirmationDialog` opens from whatever view it's attached to, which for a screen-level modifier is the top of the screen. Keep `.glassEffect` for custom floating pieces like the composers and status pills, and `.buttonStyle(.glass)` for standalone buttons. Text follows Dynamic Type: use text styles (`.body`, `.caption`, `.system(.footnote, design: .monospaced)`) rather than `.system(size:)`, size icon tiles and other fixed frames with `@ScaledMetric`, and switch side-by-side rows to stacked ones when `dynamicTypeSize.isAccessibilitySize` (see `ConversationsSheetView`'s `rowLayout`).

### Constants

All magic numbers and strings live in `Constants.swift` via `AppConstants` and `StringConstants` enums.
