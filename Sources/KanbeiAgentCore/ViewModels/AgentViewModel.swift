import Foundation
import Combine
import SwiftUI

@MainActor
public class AgentViewModel: ObservableObject {
  @Published public var messages: [Message] = []
  @Published public var isRunning = false
  @Published public var errorMessage: String?
  @Published public var scrollTrigger = 0
  @Published public var workingDirectory: URL
  @Published public var pendingBashCommand: PendingBashCommand?

  private let historyFileURL: URL
  private let systemPrompt: String

  public init(context: any KanbeiAgentContext) {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = support.appendingPathComponent("KanbeiAgent")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    self.workingDirectory = context.workingDirectoryURL
    self.historyFileURL = dir.appendingPathComponent("\(context.historyFileName).json")

    let fileTree = AgentViewModel.buildFileTree(at: context.workingDirectoryURL)

    var prompt = """
      あなたは優秀なソフトウェアエンジニアのAIエージェントです。

      【最重要】ツールを使う前にテキストで計画・説明・差分まとめを書いてはいけません。
      まず即座にツールを呼び出し、作業が完了してから結果をテキストで報告してください。

      - ファイルを読んだら、次のレスポンスで即座に書き込みを開始すること
      - 「実行します」「書き換えます」などの宣言テキストを出力した場合、同じレスポンス内で必ずツールも呼び出すこと
      - 同じツールを同じ引数で2回以上呼ばない
      - ファイル構成は下記に記載済みなので、list_filesやglobで探索しないこと
      - 不必要な確認や追加調査は行わない
      - タスクが完了したら必ずテキストで結果を伝えて終了する

      作業ディレクトリ: \(context.workingDirectoryURL.path)
      """

    if !context.systemPromptAddendum.isEmpty {
      prompt += "\n\n\(context.systemPromptAddendum)"
    }

    if !fileTree.isEmpty {
      prompt += """

      ## プロジェクトのファイル構成
      以下のパスはすべて作業ディレクトリ（\(context.workingDirectoryURL.path)）からの相対パスです。

      \(fileTree)
      """
    }

    self.systemPrompt = prompt
  }

  private static func buildFileTree(at root: URL) -> String {
    let ignored: Set<String> = [".git", "DerivedData", ".build", "node_modules", "xcuserdata", ".DS_Store"]
    let allowedExtensions: Set<String> = ["swift", "md", "json", "yaml", "yml", "txt", "sh"]
    guard let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else { return "" }

    var paths: [String] = []
    for case let url as URL in enumerator {
      let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
      if isDir {
        if ignored.contains(url.lastPathComponent) { enumerator.skipDescendants() }
        continue
      }
      guard allowedExtensions.contains(url.pathExtension.lowercased()) else { continue }
      let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
      paths.append(relative)
      if paths.count >= 150 { break }
    }
    return paths.sorted().joined(separator: "\n")
  }

  public struct PendingBashCommand: Identifiable {
    public let id = UUID()
    public let command: String
    public let continuation: CheckedContinuation<Bool, Never>
  }

  private static let dangerousPatterns: [String] = [
    "rm ", "sudo ", "dd ", "mkfs", "chmod ", "chown ", "kill ", "pkill ",
    "shutdown", "reboot", "mv /", "truncate", "shred", "> /"
  ]

  private func isDangerous(_ command: String) -> Bool {
    Self.dangerousPatterns.contains { command.contains($0) }
  }

  public func confirmBash(approved: Bool) {
    guard let pending = pendingBashCommand else { return }
    pendingBashCommand = nil
    pending.continuation.resume(returning: approved)
  }

  public var currentTask: Task<Void, Never>?

  public func cancelGeneration() {
    currentTask?.cancel()
    currentTask = nil
  }

  @AppStorage("claudeApiKey") private var apiKey = ""
  @AppStorage("claudeModel") private var claudeModel = "claude-sonnet-4-6"

  private func apiClient(useHaiku: Bool = false) -> ClaudeAPIClient {
    let model = useHaiku ? "claude-haiku-4-5-20251001" : claudeModel
    return ClaudeAPIClient(apiKey: apiKey, model: model, maxTokens: useHaiku ? 2048 : 4096)
  }

  private var tools: AgentTools { AgentTools(workingDirectory: workingDirectory) }
  private var history: [APIMessage] = []

  // MARK: - 永続化

  private struct SavedHistory: Codable {
    var messages: [Message]
    var history: [APIMessage]
    var workingDirectoryPath: String?
  }

  private func saveHistory() {
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
    try? data.write(to: historyFileURL)
  }

  public func loadHistory() {
    guard let data = try? Data(contentsOf: historyFileURL),
          let saved = try? JSONDecoder().decode(SavedHistory.self, from: data) else { return }
    messages = saved.messages
    history = sanitizeHistory(saved.history)
    if let path = saved.workingDirectoryPath {
      workingDirectory = URL(fileURLWithPath: path)
    }
  }

  private func sanitizeHistory(_ h: [APIMessage]) -> [APIMessage] {
    var result = h
    while let last = result.last, last.role == "assistant",
          last.content.contains(where: { $0.type == "tool_use" }) {
      result.removeLast()
    }
    return result
  }

  // MARK: - メッセージ送信

  public func send(_ userInput: String) {
    let images: [(base64: String, mediaType: String)] = []
    currentTask = Task { await sendWithImages(userInput, images: images) }
  }

  public func sendWithImages(_ userInput: String, images: [(base64: String, mediaType: String)]) async {
    let trimmed = userInput.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty || !images.isEmpty else { return }
    guard !apiKey.isEmpty else {
      errorMessage = "設定でClaude API Keyを入力してください"
      return
    }

    let displayText = images.isEmpty
      ? trimmed
      : trimmed + (trimmed.isEmpty ? "" : "\n") + "📎 画像 \(images.count)枚"
    messages.append(Message(role: .user, content: displayText))

    if images.isEmpty {
      history.append(.user(trimmed))
    } else {
      history.append(.userWithImages(trimmed, images: images))
    }

    let assistantIndex = messages.count
    messages.append(Message(role: .assistant, content: "", isStreaming: true))

    isRunning = true
    errorMessage = nil

    do {
      try await runAgentLoop(assistantIndex: assistantIndex)
    } catch is CancellationError {
      messages[assistantIndex].content += messages[assistantIndex].content.isEmpty
        ? "⏹ 生成を停止しました"
        : "\n\n⏹ 生成を停止しました"
    } catch {
      errorMessage = error.localizedDescription
      scrollTrigger += 1
    }

    for i in messages.indices where messages[i].isStreaming {
      messages[i].isStreaming = false
    }
    isRunning = false
    currentTask = nil
    scrollTrigger += 1
    saveHistory()
  }

  // MARK: - 履歴の最適化

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
        await TokenUsageStore.shared.record(usage: result.usage)
        return result.contents
      } catch ClaudeError.httpError(429, _) {
        if attempt < maxRetries - 1 {
          let wait = 30 * (1 << attempt)
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
      try Task.checkCancellation()
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

          if name == "bash", let cmd = input["command"] as? String, self.isDangerous(cmd) {
            let approved = await withCheckedContinuation { continuation in
              Task { @MainActor in
                self.pendingBashCommand = PendingBashCommand(command: cmd, continuation: continuation)
              }
            }
            guard approved else { return "ユーザーによってキャンセルされました" }
          }

          let toolMsg = "[\(name)] 実行中..."
          await MainActor.run { self.messages.append(Message(role: .tool, content: toolMsg)) }
          let result = await self.tools.execute(name: name, input: input)
          let isError = result.hasPrefix("エラー:") || result.hasPrefix("Error:") || result.contains("error:") || result.contains("No such file")
          let doneMsg = isError ? "[\(name)] ⚠️ \(result.prefix(120))" : "[\(name)] 完了"
          await MainActor.run { self.messages[self.messages.count - 1].content = doneMsg }
          return result
        }
      )

      let toolUseContents = collectedContents.filter { $0.type == "tool_use" }
      let toolResultContents = collectedContents.filter { $0.type == "tool_result" }

      if toolUseContents.isEmpty {
        let assistantContent = messages[assistantIndex].content
        if !assistantContent.isEmpty {
          history.append(.assistant([.text(assistantContent)]))
        }
        if looksLikeUnfinishedPlan(assistantContent) && iteration < maxIterations - 1 {
          history.append(.user("説明は不要です。今すぐfile_write・str_replace・bashなどのツールを呼び出してください。まず1つ目のファイルから始めてください。"))
          messages.append(Message(role: .assistant, content: "", isStreaming: true))
          assistantIndex = messages.count - 1
        } else {
          break
        }
      } else {
        var assistantContents: [APIContent] = []
        let assistantText = messages[assistantIndex].content
        if !assistantText.isEmpty { assistantContents.append(.text(assistantText)) }
        assistantContents.append(contentsOf: toolUseContents)
        history.append(.assistant(assistantContents))

        let toolResultAPIContents = toolResultContents.compactMap { result -> APIContent? in
          guard let toolUseId = result.toolUseId else { return nil }
          let raw = result.content?.isEmpty == false ? result.content! : "(empty)"
          let content = raw.count > 10_000 ? String(raw.prefix(10_000)) + "\n...(truncated)" : raw
          return APIContent(type: "tool_result", content: content, toolUseId: toolUseId)
        }
        if !toolResultAPIContents.isEmpty {
          history.append(APIMessage(role: "user", content: toolResultAPIContents))
        }

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

  private func looksLikeUnfinishedPlan(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    let completionWords = ["完了しました", "書き換えました", "修正しました", "終わりました", "以上です", "できました"]
    if completionWords.contains(where: { text.contains($0) }) { return false }
    let intentionWords = [
      "今すぐ実行", "書き換えます", "実行します", "書き込みます", "修正します",
      "行います", "適用します", "開始します", "進めます"
    ]
    let hasFutureAction = intentionWords.contains { text.contains($0) }
    let isPlanOnly = text.contains("差分まとめ") || text.contains("差分:") ||
                     text.contains("以下のファイルを") || text.contains("以下を変更")
    return hasFutureAction || isPlanOnly
  }

  // MARK: - 会話リセット

  public func clearHistory() {
    messages.removeAll()
    history.removeAll()
    errorMessage = nil
    saveHistory()
  }
}
