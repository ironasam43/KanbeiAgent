# CLAUDE.md (KanbeiAgentCore)

See the root CLAUDE.md for workspace-wide conventions.

## Product Overview

- **Package**: KanbeiAgentCore
- **Summary**: A Swift Package that provides a Claude-powered AI agent for macOS and iOS apps.
- **Repository**: https://github.com/ironasam43/KanbeiAgent

## Tech Stack

- **Language**: Swift
- **UI framework**: SwiftUI (views only; core logic has no SwiftUI dependency)
- **Target OS**: macOS 14.0+ / iOS 17.0+
- **Xcode projects**: `SampleApp/SampleApp.xcodeproj`, `SampleAppIOS/SampleAppIOS.xcodeproj`

## Architecture

- **Pattern**: MVVM
- **Claude API**: tool_use + SSE streaming
- **Agent loop**: send message → call tools → return results → repeat
- **Headless layer**: `AgentService` (no SwiftUI) + `AgentViewModel` (SwiftUI wrapper)

## Key Components

| File | Role |
|------|------|
| `Services/AgentService.swift` | Core agent loop, `AsyncThrowingStream<AgentEvent, Error>` API |
| `Services/AgentEvent.swift` | Typed events emitted by AgentService |
| `Services/ClaudeAPIClient.swift` | Claude API HTTP client (tool_use + SSE) |
| `ViewModels/AgentViewModel.swift` | SwiftUI `@Published` wrapper around AgentService |
| `Views/ChatView.swift` | Drop-in chat UI |
| `Tools/AgentTools.swift` | Tool implementations (file_read, str_replace, bash, …) |

## xcframework Distribution

The package is also distributed as a static xcframework for projects that cannot use SPM directly.

Build script: `build_xcframework.sh`
Output: `build/KanbeiAgentCore.xcframework`
Platforms: macOS (arm64+x86_64), iOS (arm64), iOS Simulator (arm64+x86_64)

## Instructions for Claude

- Follow SwiftUI and Swift concurrency best practices
- Keep `AgentService` free of SwiftUI imports
- Use `#if os(macOS)` guards for macOS-only features (bash, screenshots)
- Confirm approach before making large changes
