# KanbeiAgentCore

A Swift Package that provides an agentic Claude API client with tool use and SSE streaming. Designed to be embedded in macOS and iOS apps.

## Features

- Claude API integration with tool use and SSE streaming
- Autonomous agent loop (up to 50 iterations, 5 retries)
- Built-in tools: `file_read`, `str_replace`, `file_write`, `list_files`, `grep`, `glob`, `bash` (macOS only)
- Bash command approval UI (macOS only)
- Screenshot and file/image attachment support (macOS only)
- Quick prompts
- Conversation history save/export
- Token usage tracking
- Localization (English / Japanese)
- Cross-platform: macOS 14+ / iOS 17+

## Headless API

`AgentService` provides a SwiftUI-free API for use in UIKit, AppKit, or CLI apps:

```swift
let service = AgentService(context: yourContext)

for try await event in service.send("Refactor this file", apiKey: apiKey) {
    switch event {
    case .text(let chunk):     print(chunk, terminator: "")
    case .toolRunning(let n):  print("\n[tool] \(n)...")
    case .finished:            print("\nDone.")
    default: break
    }
}
```

## Requirements

- Xcode 16+
- macOS 14.0+ / iOS 17.0+
- Anthropic API key

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ironasam43/KanbeiAgent", from: "1.0.0")
]
```

Or add via Xcode: **File → Add Package Dependencies** and enter the repository URL.

## Sample Apps

- `SampleApp/` — macOS sample app (SwiftUI, local SPM reference)
- `SampleAppIOS/` — iOS sample app (SwiftUI, local SPM reference)

## Story

This software was built in just two days through agile development between ironasam43 and Claude.

## Support

If you find this project useful, your support is appreciated:

- One-time: https://buy.stripe.com/9B600l2WWdHIg3d5R957W01
- Annual: https://buy.stripe.com/7sYaEZ7dcfPQ8AL6Vd57W00

## License

MIT
