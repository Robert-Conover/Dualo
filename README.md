<p align="center">
  <img src="Dualo/Assets.xcassets/AppIcon.appiconset/dualoLight-iOS-Default-1024x1024@1x.png" alt="Dualo app icon" width="164" height="164">
</p>

<h1 align="center">Dualo</h1>

<p align="center"><strong>One chat app for OpenAI in the cloud and GGUF models on-device.</strong></p>

<p align="center">
  Dualo is a native SwiftUI iOS app that lets you switch between cloud-hosted OpenAI models and fully local GGUF models without changing the core chat experience.
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-iOS%2026%2B-1f2937?style=flat-square">
  <img alt="SwiftUI" src="https://img.shields.io/badge/built%20with-SwiftUI-2563eb?style=flat-square">
  <img alt="Status" src="https://img.shields.io/badge/status-active%20development-d4a574?style=flat-square">
  <img alt="Models" src="https://img.shields.io/badge/models-OpenAI%20%2B%20GGUF-0f172a?style=flat-square">
</p>

## What It Is
Dualo is a native iPhone chat app built around a simple idea: cloud AI and local AI should feel like the same product.

Instead of splitting those workflows into separate tools, Dualo gives you one conversation UI with two backends:

- `OpenAI` for cloud-hosted models with live streaming
- `Local GGUF` for fully on-device inference through [`LLM.swift`](https://github.com/eastriverlee/LLM.swift)

Each conversation stores its own provider and model, so you can keep one chat on a cloud model and the next entirely offline.

## How It Works
1. Open `Settings` and add an OpenAI API key, or download a local GGUF model.
2. Start a new conversation and choose the provider and model you want to use.
3. Send a prompt and watch the reply stream live.
4. Attach images for cloud chats when you want multimodal input.
5. Revisit, rename, search, export, or delete saved conversations at any time.

## Core Capabilities
- `Per-chat provider selection` so each conversation can use OpenAI or a local model independently
- `Real streaming responses` using SSE for cloud models and token callbacks for GGUF models
- `On-device inference` with downloadable GGUF models from Hugging Face
- `Image attachments` for cloud conversations using photo library or camera input
- `Conversation management` with local persistence, pinned chats, search, rename, and deletion
- `Export tools` for PDF, Markdown, and plain text sharing
- `Markdown rendering` with code block formatting and copy support
- `Keychain-backed credentials` for secure API key storage

## Why It Feels Different
- Built around hybrid AI use instead of treating local inference as an afterthought
- Uses the same streaming chat flow for both cloud and on-device models
- Saves conversations locally with their provider and model configuration intact
- Keeps local model chats private by running them entirely on the device
- Ships as a native SwiftUI app instead of a wrapped web client

## Privacy And Data
- `Conversations` are stored locally as JSON files in the app's Documents directory
- `API keys` are saved in iOS Keychain
- `Cloud chats` send prompts, image attachments and custom instructions to OpenAI over HTTPS, after the app asks permission before the first message
- `Local chats` stay on-device when using GGUF models
- The [privacy policy](https://dualo.conov.io/privacy) is also in Settings; its web version and the support page are built from `site/`

## Requirements
- iOS 26 or later
- Xcode with the iOS 26 SDK
- An OpenAI API key for cloud usage
- Enough free storage and RAM for the local GGUF models you want to run

## Build From Source
```bash
git clone https://github.com/Robert-Conover/Dualo.git
cd Dualo
open Dualo.xcodeproj
```

Then select a simulator or device in Xcode and run the `Dualo` scheme.

## Run Tests
```bash
xcodebuild test -skipMacroValidation -project Dualo.xcodeproj -scheme Dualo -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Under The Hood
Dualo uses a simple split architecture:

`HomeView` / `SimpleChatView`  
↓  
`ChatViewModel`  
↓  
`APIService` or `GGUFService`  
↓  
`ConversationManager`

Key implementation details:

- `APIService` uses `URLSession.bytes(for:)` for incremental SSE streaming
- `GGUFService` streams local tokens via `LLM.swift`
- Both backends surface output through `AsyncThrowingStream<String, Error>`
- `ConversationManager` persists each chat as a JSON file
- `ChatViewModel` throttles UI and disk writes during streaming

## Current Status
Dualo is already functional end to end:

- Chat with OpenAI models
- Download and run GGUF models offline
- Stream replies in real time
- Attach images to cloud prompts
- Export conversations as PDF, Markdown, or text
- Store credentials securely in Keychain
- Manage multiple saved conversations locally

## License
This project is not yet licensed. All rights reserved.
