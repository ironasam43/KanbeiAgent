import Foundation
import Combine
import SwiftUI

@MainActor
class AgentViewModel: ObservableObject {
  @Published var messages: [Message] = []
  @Published var isRunning = false
  @Published var errorMessage: String?
  @Published var scrollTrigger = 0
  @Published var workingDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  @Published var pendingBashCommand: PendingBashCommand?

  struct PendingBashCommand: Identifiable {
    let id = UUID()
    let command: String
    let continuation: CheckedContinuation<Bool, Never>
  }

  private static let dangerousPatterns: [String] = [
    "rm ", "sudo ", "dd ", "mkfs", "chmod ", "chown ", "kill ", "pkill ",
    "shutdown", "reboot", "mv /", "truncate", "shred", "> /"
  ]

  private func isDangerous(_ command: String) -> Bool {
    Self.dangerousPatterns.contains { command.contains($0) }
  }

  func confirmBash(approved: Bool) {
    guard let pending = pendingBashCommand else { return }
    pendingBashCommand = nil
    pending.continuation.resume(returning: approved)
  }

  @AppStorage("claudeApiKey") private var apiKey = ""
  @AppStorage("claudeModel") private var claudeModel = "claude-sonnet-4-6"

  private func apiClient(useHaiku: Bool = false) -> ClaudeAPIClient {
    let model = useHaiku ? "claude-haiku-4-5-20251001" : claudeModel
    return ClaudeAPIClient(apiKey: apiKey, model: model, maxTokens: useHaiku ? 2048 : 4096)
  }
  private var tools: AgentTools { AgentTools(workingDirectory: workingDirectory) }

  // API送信用の会話履歴
  private var history: [APIMessage] = []

  private var systemPrompt: String {
    """
    あなたは優秀なソフトウェアエンジニアのAIエージェントです。

    【最重要】ツールを使う前にテキストで計画・説明・差分まとめを書いてはいけません。
    まず即座にツールを呼び出し、作業が完了してから結果をテキストで報告してください。

    - ファイルを読んだら、次のレスポンスで即座に書き込みを開始すること
    - 「実行します」「書き換えます」などの宣言テキストを出力した場合、同じレスポンス内で必ずツールも呼び出すこと
    - 同じツールを同じ引数で2回以上呼ばない
    - 不必要な確認や追加調査は行わない
    - タスクが完了したら必ずテキストで結果を伝えて終了する

    作業ディレクトリ: \(workingDirectory.path)
    """
  }

  // MARK: - 永続化

  private static var historyFileURL: URL {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = support.appendingPathComponent("KanbeiAgent")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("history.json")
  }

  private struct SavedHistory: Codable {
    var messages: [Message]
    var history: [APIMessage]
    var workingDirectoryPath: String?
  }

  private func saveHistory() {
    // toolログ（実行中/完了）と空のassistantは捨て、userと内容のあるassistantだけ保存
    let toSave = messages.compactMap { msg -> Message? in
      if msg.role == .tool { return nil }
      if msg.role == .assistant && msg.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
      var m = msg
      m.isStreaming = false
      return m
    }
    let saved = SavedHistory(
      messages: toSave,
      history: history,
      workingDirectoryPath: workingDirectory.path
    )
    guard let data = try? JSONEncoder().encode(saved) else { return }
    try? data.write(to: Self.historyFileURL)
  }

  func loadHistory() {
    guard let data = try? Data(contentsOf: Self.historyFileURL),
          let saved = try? JSONDecoder().decode(SavedHistory.self, from: data) else { return }
    messages = saved.messages
    history = sanitizeHistory(saved.history)
    if let path = saved.workingDirectoryPath {
      workingDirectory = URL(fileURLWithPath: path)
    }
  }

  /// 孤立したtool_use（対応するtool_resultがない）を末尾から除去する
  private func sanitizeHistory(_ h: [APIMessage]) -> [APIMessage] {
    var result = h
    while let last = result.last, last.role == "assistant",
          last.content.contains(where: { $0.type == "tool_use" }) {
      result.removeLast()
    }
    return result
  }

  // MARK: - メッセージ送信

  func send(_ userInput: String) async {
    await sendWithImages(userInput, images: [])
  }

  func sendWithImages(_ userInput: String, images: [(base64: String, mediaType: String)]) async {
    let trimmed = userInput.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty || !images.isEmpty else { return }
    guard !apiKey.isEmpty else {
      errorMessage = "設定でClaude API Keyを入力してください"
      return
    }

    // UI用メッセージ（テキストのみ表示、画像は枚数をサフィックスで表示）
    let displayText = images.isEmpty
      ? trimmed
      : trimmed + (trimmed.isEmpty ? "" : "\n") + "📎 画像 \(images.count)枚"
    messages.append(Message(role: .user, content: displayText))

    // API用 history
    if images.isEmpty {
      history.append(.user(trimmed))
    } else {
      history.append(.userWithImages(trimmed, images: images))
    }

    // Assistantのストリーミング枠を追加
    let assistantIndex = messages.count
    messages.append(Message(role: .assistant, content: "", isStreaming: true))

    isRunning = true
    errorMessage = nil

    do {
      try await runAgentLoop(assistantIndex: assistantIndex)
    } catch {
      errorMessage = error.localizedDescription
      scrollTrigger += 1
    }

    // ループ内で追加されたすべてのassistantメッセージのisStreamingを解除
    for i in messages.indices where messages[i].isStreaming {
      messages[i].isStreaming = false
    }
    isRunning = false
    scrollTrigger += 1
    saveHistory()
  }

  // MARK: - 履歴の最適化

  // 直近N回のユーザー発話ターンのみAPIに送る（tool_use/tool_resultペアは崩さない）
  private var smartTruncatedHistory: [APIMessage] {
    let keepTurns = 5
    let userTextIndices = history.indices.filter {
      history[$0].role == "user" && history[$0].content.first?.type == "text"
    }
    guard userTextIndices.count > keepTurns else { return history }
    let keepFrom = userTextIndices[userTextIndices.count - keepTurns]
    return Array(history[keepFrom...])
  }

  // MARK: - リトライ付きAPI呼び出し

  private func sendWithRetry(
    assistantIndex: Int,
    useHaiku: Bool = false,
    onText: @escaping (String) -> Void,
    onToolUse: @escaping (String, String, [String: Any]) async -> String
  ) async throws -> [APIContent] {
    let maxRetries = 5
    for attempt in 0..<maxRetries {
      do {
        let result = try await apiClient(useHaiku: useHaiku).sendMessages(
          smartTruncatedHistory, tools: AgentTools.definitions,
          systemPrompt: systemPrompt,
          onText: onText, onToolUse: onToolUse
        )
        return result.contents
      } catch ClaudeError.httpError(429, _) {
        if attempt < maxRetries - 1 {
          let wait = 30 * (1 << attempt) // 30s → 60s → 120s → 240s
          errorMessage = "レート制限中… \(wait)秒後に自動リトライします (\(attempt + 1)/\(maxRetries - 1))"
          scrollTrigger += 1
          try await Task.sleep(for: .seconds(wait))
          errorMessage = nil
        } else {
          throw ClaudeError.httpError(429, "リトライ上限に達しました。しばらく待ってから再送してください。")
        }
      }
    }
    fatalError("unreachable")
  }

  // MARK: - Agentループ

  private func runAgentLoop(assistantIndex startIndex: Int) async throws {
    var assistantIndex = startIndex
    let maxIterations = 50
    var iteration = 0

    while iteration < maxIterations {
      iteration += 1
      let collectedContents = try await sendWithRetry(
        assistantIndex: assistantIndex,
        useHaiku: iteration > 1,
        onText: { [weak self] text in
          guard let self else { return }
          self.messages[assistantIndex].content += text
        },
        onToolUse: { [weak self] id, name, input async -> String in
          guard let self else { return "エラー" }

          // 危険なbashコマンドは確認ダイアログを出す
          if name == "bash", let cmd = input["command"] as? String, self.isDangerous(cmd) {
            let approved = await withCheckedContinuation { continuation in
              Task { @MainActor in
                self.pendingBashCommand = PendingBashCommand(command: cmd, continuation: continuation)
              }
            }
            guard approved else { return "ユーザーによってキャンセルされました" }
          }

          let toolMsg = "[\(name)] 実行中..."
          await MainActor.run {
            self.messages.append(Message(role: .tool, content: toolMsg))
          }
          let result = await self.tools.execute(name: name, input: input)
          await MainActor.run {
            self.messages[self.messages.count - 1].content = "[\(name)] 完了"
          }
          return result
        }
      )

      // tool_useがあった場合はhistoryに追加して再度送信
      let toolUseContents = collectedContents.filter { $0.type == "tool_use" }
      let toolResultContents = collectedContents.filter { $0.type == "tool_result" }

      if toolUseContents.isEmpty {
        let assistantContent = messages[assistantIndex].content
        if !assistantContent.isEmpty {
          history.append(.assistant([.text(assistantContent)]))
        }

        // テキストのみで終わった場合でも、「まだやっていない」系の発言なら続行を促す
        if looksLikeUnfinishedPlan(assistantContent) && iteration < maxIterations - 1 {
          history.append(.user("説明は不要です。今すぐfile_write・str_replace・bashなどのツールを呼び出してください。まず1つ目のファイルから始めてください。"))
          messages.append(Message(role: .assistant, content: "", isStreaming: true))
          assistantIndex = messages.count - 1
        } else {
          break
        }
      } else {
        // ツール結果をhistoryに追加して続行（空テキストは除外）
        var assistantContents: [APIContent] = []
        let assistantText = messages[assistantIndex].content
        if !assistantText.isEmpty {
          assistantContents.append(.text(assistantText))
        }
        assistantContents.append(contentsOf: toolUseContents)
        history.append(.assistant(assistantContents))

        // 複数のtool_resultは1つのuserメッセージにまとめる（API仕様）
        let toolResultAPIContents = toolResultContents.compactMap { result -> APIContent? in
          guard let toolUseId = result.toolUseId else { return nil }
          let raw = result.content?.isEmpty == false ? result.content! : "(empty)"
          let content = raw.count > 10_000 ? String(raw.prefix(10_000)) + "\n...(truncated)" : raw
          return APIContent(type: "tool_result", content: content, toolUseId: toolUseId)
        }
        if !toolResultAPIContents.isEmpty {
          history.append(APIMessage(role: "user", content: toolResultAPIContents))
        }

        // 次のAssistant枠を追加
        messages.append(Message(role: .assistant, content: "", isStreaming: true))
        assistantIndex = messages.count - 1
      }
    }

    if iteration >= maxIterations {
      messages[assistantIndex].content += "\n\n⚠️ ツール呼び出しの上限（\(maxIterations)回）に達しました。"
      messages[assistantIndex].isStreaming = false
    }
  }

  // MARK: - ヘルパー

  /// テキストのみで終わったレスポンスが「計画・宣言だけで未実行」かどうかを判定する
  private func looksLikeUnfinishedPlan(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    // 完了を示すキーワードがあれば「実行済み」と判断
    let completionWords = ["完了しました", "書き換えました", "修正しました", "終わりました", "以上です", "できました"]
    if completionWords.contains(where: { text.contains($0) }) { return false }
    // 計画・宣言パターン
    let intentionWords = [
      "今すぐ実行", "書き換えます", "実行します", "書き込みます", "修正します",
      "行います", "適用します", "開始します", "進めます"
    ]
    let hasFutureAction = intentionWords.contains { text.contains($0) }
    // 差分まとめ・計画テキストパターン
    let isPlanOnly = text.contains("差分まとめ") || text.contains("差分:") ||
                     text.contains("以下のファイルを") || text.contains("以下を変更")
    return hasFutureAction || isPlanOnly
  }

  // MARK: - 会話リセット

  func clearHistory() {
    messages.removeAll()
    history.removeAll()
    errorMessage = nil
    saveHistory()
  }
}
