# CLAUDE.md（KanbeiAgent）

ルートの CLAUDE.md も参照してください。

## プロダクト概要

- **プロダクト名**：KanbeiAgent
- **概要**：Claude Code（VS Code extension）相当の機能を持つmacOSネイティブエージェント。将来的にDevDeckへの組み込みを想定。
- **対象ユーザー**：Claude Codeを使って開発する個人開発者
- **リポジトリ**：https://github.com/ironasam43/KanbeiAgent

## 技術スタック

- **言語**：Swift
- **UIフレームワーク**：SwiftUI
- **対象OS**：macOS 14.0（Sonoma）以上
- **Xcodeプロジェクト**：`ios/KanbeiAgent.xcodeproj`

## アーキテクチャ

- **パターン**：MVVM
- **Claude API**：tool_use + SSEストリーミング
- **Agentループ**：メッセージ送信 → ツール呼び出し → 結果返却 → 繰り返し

## 主要コンポーネント（予定）

### Phase 1（MVP）
1. Claude APIクライアント（tool_use + ストリーミング）
2. Agentループ
3. 基本ツール実装（FileRead / FileWrite / BashExec）
4. チャットUI

### Phase 2
5. Grep / Glob / Git操作ツール
6. 会話履歴の保存
7. 作業ディレクトリの指定UI

### Phase 3
8. DevDeckへの組み込みインターフェース

## ツール仕様

```
FileRead(path: String) -> String
FileWrite(path: String, content: String) -> Void
BashExec(command: String, workingDir: String) -> String
Grep(pattern: String, path: String) -> [String]
Glob(pattern: String, path: String) -> [String]
```

## Claudeへの指示

- 提案は日本語で返してください
- 大きな変更の前には必ず方針を確認してください
- セキュリティに注意（BashExecは危険なコマンドを実行しないよう考慮）
- SwiftUIのベストプラクティスに従ってください
