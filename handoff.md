# KanbeiAgentCore（Public）引き継ぎメモ

> 最終更新：2026-05-26

## プロダクト概要

Claude API を使った macOS / iOS 向け Swift Package（KanbeiAgentCore）。
tool_use + SSE ストリーミングによるエージェントループを提供する。
Public 版として OSS 公開を想定。

## リポジトリ

- GitHub: https://github.com/ironasam43/KanbeiAgent（Public 版）

## 主な機能

- Claude API 統合（tool_use + SSE ストリーミング）
- 自律エージェントループ（最大 50 反復・5 リトライ）
- ビルトインツール: `file_read` / `str_replace` / `file_write` / `list_files` / `grep` / `glob` / `bash`（macOS only）
- Bash コマンド承認 UI（macOS only）
- スクリーンショット・ファイル/画像添付（macOS only）
- ローカライズ（英語・日本語）

## 主要コンポーネント

| ファイル | 役割 |
|---|---|
| `Services/AgentService.swift` | エージェントループのコア（`AsyncThrowingStream<AgentEvent, Error>`） |
| `Services/ClaudeAPIClient.swift` | Claude API HTTP クライアント |
| `ViewModels/AgentViewModel.swift` | SwiftUI `@Published` ラッパー |
| `Views/ChatView.swift` | ドロップイン Chat UI |
| `Tools/AgentTools.swift` | ツール実装 |

## xcframework ビルド

```sh
./build_xcframework.sh
```
出力: `build/KanbeiAgentCore.xcframework`

## KanbeiDevPrivate との関係

- KanbeiDevPrivate: 開発用（非公開・未整理の実験的変更も含む）
- KanbeiDevPublic: 公開用（Public 向けに整理した安定版）

## 現在の状態

- ✅ 基本エージェントループ実装済み
- 変更履歴は `docs/history.md` を参照（現時点では初期状態）

## 未解決・TODO

- [ ] KanbeiDevPrivate との差分管理方針の確立
- [ ] 最初の実装変更時に `docs/history.md` に記録を開始する
