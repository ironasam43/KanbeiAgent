# KanbeiAgentCore 設計方針

最終更新：2026-05-07

---

## プロダクト概要

- **Package**: KanbeiAgentCore
- **種別**: Swift Package（Claude 搭載 AI エージェントを macOS / iOS アプリに提供）
- **ターゲット**: macOS 14.0+ / iOS 17.0+

## アーキテクチャ

- **パターン**: MVVM
- **Claude API**: tool_use + SSE ストリーミング
- **Agent loop**: send message → call tools → return results → repeat
- **Headless 層**: `AgentService`（SwiftUI 非依存）+ `AgentViewModel`（SwiftUI ラッパー）

## 主要コンポーネント

| ファイル | 役割 |
|---|---|
| `Services/AgentService.swift` | コア Agent ループ、`AsyncThrowingStream<AgentEvent, Error>` API |
| `Services/ClaudeAPIClient.swift` | Claude API HTTP クライアント（tool_use + SSE） |
| `ViewModels/AgentViewModel.swift` | SwiftUI `@Published` ラッパー |
| `Views/ChatView.swift` | ドロップイン Chat UI |
| `Tools/AgentTools.swift` | ツール実装（file_read, str_replace, bash …） |

## 配布形式

- SPM パッケージ（通常）
- xcframework（SPM 非対応プロジェクト向け）: `build_xcframework.sh` でビルド
