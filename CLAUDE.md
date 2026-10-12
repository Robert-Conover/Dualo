# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Codex) when working with code in this repository.

## Build & Run

Open `Dualo.xcodeproj` in Xcode, select a simulator or device, and build (Cmd+R). iOS 26+ required. The app is iPhone only (`TARGETED_DEVICE_FAMILY = 1`; on iPad it runs in a phone-sized window), since a version that supports iPad can't drop it in an update; add iPad once its layout has been built and tested. Builds declare `ITSAppUsesNonExemptEncryption = NO` (it only uses HTTPS and the Keychain), so uploads skip the export-compliance question.

**Build (CLI):**
```bash
xcodebuild build -skipMacroValidation -project Dualo.xcodeproj -scheme Dualo -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Run tests:**
```bash
xcodebuild test -skipMacroValidation -project Dualo.xcodeproj -scheme Dualo -destination 'platform=iOS Simulator,name=iPhone 16'
```
Tests use Swift Testing (`import Testing`, `@Test`). `DualoTests` covers pure logic (API key validation, retired-model migration, HTTP error mapping, `<think>` handling, streaming throttle) and `ChatViewModel`'s send/stream/stop/retry/edit/regenerate flow against fake services; add `-only-testing:DualoTests` to skip the slow `DualoUITests`. `ChatFlowUITests` drives the chat screen (send, stop, retry, scroll, rename, export) by launching with `-UITestStubAPI`, which swaps in the DEBUG-only `StubAPIService` (`Utilities/UITestSupport.swift`) so no API key is needed (stubbed launches keep API settings in a keychain of their own, cleared at each launch); markers like `[fail]`, `[slow]`, `[drip]` and `[long]` in the message control the stub, and a message sent again gets a reply starting "Take 2." so tests can tell regenerated replies apart. `FirstLaunchUITests` add `-UITestFirstLaunch`, which starts the app with no API settings or downloaded models and a download that only pretends, then finds the model already on the simulator. `GGUFServiceIntegrationTests`, `LocalModelUITests` and `FirstLaunchUITests` run the real Qwen3.5 0.8B model and are skipped unless its GGUF is in the app's `Documents/Models` (see the integration tests' file header for setup). When it is, run them with `-parallel-testing-enabled NO`: in parallel clones the local-model UI tests time out. Both switch off any custom instructions left saved in the app, and the integration tests use greedy sampling (`GGUFService.useGreedySampling`), so the model gives the same replies on every run. `SpeechTranscriberIntegrationTests` transcribes a recorded clip with the real Speech framework; it only runs on a device, because the framework hangs in the Simulator. To run unit tests on the iPhone, pass `DEVELOPMENT_TEAM=A8F4R7QRHC` (the test targets have no team) and use a temporary scheme in `xcuserdata` that tests only `DualoTests`: the autocreated scheme also builds the UI-test runner, which can't be provisioned without an Xcode account. Delete the scheme afterwards, since any scheme file stops Xcode autocreating `Dualo`. Swap the simulator name for one installed locally (`xcrun simctl list devices available`).

**CI:** `.github/workflows/ci.yml` runs `DualoTests` on GitHub's `macos-26` runner (Xcode 26.6) for PRs to `main`. The repo is private and macOS minutes use the free allowance 10x faster, so CI skips the UI tests and doesn't run on pushes; run `DualoUITests` locally before merging UI changes. Keep the project buildable with Xcode 26 until the runner gets Xcode 27.

LLM.swift is vendored at `Packages/LLM.swift` (v3.0.3, referenced as a local package) with fixes marked `Dualo patch` in `Sources/LLM/LLM.swift`: clearing the KV cache with `llama_memory_clear`, and, since hybrid models can't trim their cache, going back to a saved checkpoint (or re-reading from the start) when a prompt differs from the cache. Without the first two, hybrid models like Qwen3.5 crash llama.cpp on the second message. `LLMCore.saveSession`/`loadSession` (with `LLM` wrappers that wait for a pending reset) are patches too, as is `LLMCore.lastReadTokenCount`, for the tests. Re-apply them if you update the package. Its `@Generatable` macro needs a one-time "Trust & Enable" in Xcode; CLI builds pass `-skipMacroValidation`.

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

`ChatViewModel` throttles both UI updates (50ms) and disk persistence (500ms / 100 chars) during streaming to avoid excessive redraws and I/O; `StreamingThrottle` makes those decisions. `sendMessage`, `retryMessage` and `regenerateReply` share one streaming path (`startStreaming`). Only the last user message can be edited and only the last reply regenerated; both remove the old turns, and a local model picks that up with the next message, since it always reads the chat from the app.

### Context Management

`GGUFService` formats chats with the template embedded in each GGUF file (falling back to ChatML when there isn't one). Every message hands the model the chat's history from the app: as many of the newest messages as fit in its 4K context with a quarter left for the reply, counted with the model's own tokenizer (`ModelMemoryBudget`, `GGUFService.planMemory`). Older ones drop out, a quarter of the room at a time so the chat's start doesn't move with every message, and `GGUFService.memory` records where, so the chat shows a divider (`ModelMemoryDivider`) and the context pill switches to "Forgetting oldest"; `ChatViewModel` refreshes it after each reply, edit and model load so the divider is there before the next message. A message too long to fit at all fails with `GGUFServiceError.messageTooLong` instead of an empty reply. When switching conversations, `GGUFService` saves what the model has read of the chat it leaves and picks up the next one where it was saved (`ChatMemoryStore`, in Caches, for the 3 most recently saved chats, each up to about 80 MB), or starts it from scratch; it also saves when the app goes to the background, so a relaunched app picks up too. The saved memory records where the chat's start was, so it starts there again. Deleting a chat deletes its saved memory, and `clearConversationContext` drops it so the next message is read from the start. After a reply in a local chat that still has the title the app made from its first words (`Conversation.hasPlaceholderTitle`), `ChatViewModel` has the model name the chat once (`APIServiceProtocol.suggestTitle`, `GGUFService.suggestTitle`); cloud chats keep their first-words title. Naming queues behind the reply, saves the chat's memory first and leaves the model on no chat, so the next message picks the chat up from what was saved; it picks the most likely words (temperature 0), since a sampled title from a small model can wander off topic, and `cleanTitle` trims labels, quotes and markdown. A title the user sets while the model is naming the chat wins. LLM.swift reuses the cache for whatever prefix of the prompt still matches. Qwen3.5's template renders a past reply without the empty thinking block its generation prompt had, and the hybrid model can't roll back the few tokens that differ, so the patched `prepareContext` saves the model's recurrent state (about 20 MB) at the start and end of each new message and picks up from there: the next message, a regenerated reply or an edited last message reads only what changed. Replies use `thinking: .suppressed`, because LLM.swift otherwise forces reasoning on and small models can think for minutes on a phone. Any reasoning a model still produces streams separately from the answer, and `ThinkingTagStream` merges them back into one string with `<think>` tags. It strips `<think>...</think>` blocks from history to save context space (`GGUFService.memoryEntries`). The system prompt is a short base prompt plus the user's custom instructions (`CustomInstructions`, edited in Settings and read on every send, so a change applies mid-chat); cloud requests send the instructions as a `developer` message. Separately, `MessageContentRenderer` extracts `<think>` blocks (including unclosed ones mid-stream) for display, so changes to the reasoning format must update both. `ThinkingBlockTests` covers both sides. For local models, `ChatInputBar` shows a live token counter while a reply streams and the last reply's stats (`GGUFService.lastGenerationStats`, tagged with its chat so other chats don't show them) until the next one starts; the Generation Stats toggle in Settings (`AppConstants.LocalModels.showGenerationStatsKey`) switches both off.

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

### First Launch

With no API key and no downloaded model, Home shows `ModelSetupCard` in place of the prompt suggestions: it downloads the recommended model (Qwen3.5 0.8B) with progress and Cancel, or opens Settings for an API key. Once a model is downloaded and none is chosen, Home chooses and loads it, and closing Settings reloads the API settings, so either way the composer works straight away. Cloud AI stays optional, so a reviewer or anyone without a key can use the app.

### Model Downloads

`ModelDownloader` downloads models in a background `URLSession`, so a download keeps going when the user leaves Dualo, and when the system has closed the app iOS relaunches it in the background to hand over the file (`AppDelegate`, `handleEventsForBackgroundURLSession`). The file is moved into `Documents/Models` inside the delegate call, since the system deletes it afterwards; each task's description (`DownloadTag`) records its model and destination, so a relaunched app can tell its downloads apart, and on launch `LocalModelManager.restoreDownloads` shows the ones still running. The session retries dropped connections by itself, continuing where it stopped; a download that fails for good (or is cancelled because the user swiped the app away) keeps its resume data (`ResumeDataStore`), so Try Again carries on from there. A download on cellular data or a hotspot asks first (`cellularDownloadAlert`, `LocalModelManager.isOnExpensiveNetwork`). `Documents/Models` is excluded from iCloud backups, since models can be downloaded again. `-UITestCellular` makes the app act as if on cellular data, and `-UITestModelDownloadBaseURL <url>` downloads from another server, for trying cut-off downloads against a local one. The Simulator doesn't cancel background downloads when an app is swiped away, so that case only happens on a device.

### Privacy

Apple wants permission before personal data goes to a third-party AI service, so the first message to an OpenAI model waits for the user to allow it (`CloudConsent`, `ChatViewModel.mayContact`, `CloudConsentSheet`). Sending, retrying and regenerating all ask; a declined message stays in the chat as failed, so Retry asks again. Allowing is remembered until it's switched off in Settings (Send Chats to OpenAI). Stubbed UI-test launches start with it allowed, under a key of their own; add `-UITestAskCloudConsent` to start with it not yet asked. The privacy policy is in Settings (`PrivacyPolicy`, `PrivacyPolicyView`) and on the web at dualo.conov.io/privacy, served from `site/` on `main` by a Cloudflare Worker with static assets (`wrangler.jsonc`; with `/support`, the App Store support URL). `PrivacyPolicyTests` checks `site/privacy.html` says the same as `PrivacyPolicy.swift`, so change both together, and update the policy whenever what leaves the device changes. `PrivacyInfo.xcprivacy` declares the required-reason APIs the app uses (UserDefaults, file timestamps, free disk space) and the data sent to OpenAI; add to it when the app starts using another one.

### UI

The app uses iOS 26's Liquid Glass through the native APIs wherever they exist. Toolbar items are plain buttons and menus, because the toolbar draws their glass (adding `.glassEffect` inside one draws a second layer). Sheets use a navigation bar with `Button(role: .close)`, `.searchable` and `ContentUnavailableView`, on the system sheet background. Both composers are `safeAreaBar`s, so content scrolls under them and they ride on top of the keyboard as it moves; don't position them from keyboard notifications, whose animation falls behind the keyboard. Choices that belong to a button, like the composers' + (`AttachmentMenu`), are a `Menu`: a `confirmationDialog` opens from whatever view it's attached to, which for a screen-level modifier is the top of the screen. Keep `.glassEffect` for custom floating pieces like the composers and status pills, and `.buttonStyle(.glass)` for standalone buttons. Text follows Dynamic Type: use text styles (`.body`, `.caption`, `.system(.footnote, design: .monospaced)`) rather than `.system(size:)`, size icon tiles and other fixed frames with `@ScaledMetric`, and switch side-by-side rows to stacked ones when `dynamicTypeSize.isAccessibilitySize` (see `ConversationsSheetView`'s `rowLayout`).

### Constants

All magic numbers and strings live in `Constants.swift` via `AppConstants` and `StringConstants` enums.
