# KanbeiAgent

Claude API（tool_use + SSEストリーミング）を使ったmacOSネイティブエージェントアプリ。
コアライブラリ `KanbeiAgentCore` は Swift Package として公開しており、他のアプリから参照できます。

## KanbeiAgentCore - Swift Package

### 対応環境

- macOS 14.0 (Sonoma) 以上
- Swift 5.9 以上

### Xcode からの追加方法

1. Xcode で対象プロジェクトを開く
2. `File` → `Add Package Dependencies...`
3. 検索欄に以下のURLを入力:
   ```
   https://github.com/ironasam43/KanbeiAgent
   ```
4. バージョンを選択して `Add Package` をクリック

### Package.swift での追加方法

```swift
dependencies: [
    .package(url: "https://github.com/ironasam43/KanbeiAgent", from: "1.0.0")
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "KanbeiAgentCore", package: "KanbeiAgent")
        ]
    )
]
```

### 使い方

```swift
import KanbeiAgentCore

// コンテキストを実装
struct MyAgentContext: KanbeiAgentContext {
    let workingDirectoryURL: URL
    let historyFileName: String = "history"
    let systemPromptAddendum: String = ""
}

// ChatViewを表示
ChatView(context: MyAgentContext(
    workingDirectoryURL: FileManager.default.homeDirectoryForCurrentUser
))
```

### 必要な環境変数

| 変数名 | 説明 |
|--------|------|
| `ANTHROPIC_API_KEY` | Claude APIキー（必須） |

## スタンドアロンアプリ

`ios/KanbeiAgent.xcodeproj` をXcodeで開いてビルド・実行できます。

## ライセンス

MIT
