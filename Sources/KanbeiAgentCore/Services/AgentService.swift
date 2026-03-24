//
//  AgentService.swift
//  KanbeiAgentCore
//

import Foundation

/// Headless agent service with no UI framework dependencies.
/// Use send(_:images:apiKey:model:) to get an AsyncThrowingStream<AgentEvent, Error>
/// and drive any UI by consuming events from the stream.
///
/// Note: Designed for single-concurrent-use. Do not call send() again while
/// a previous stream is still being consumed.
public class AgentService {

  // MARK: - Public

  public let workingDirectory: URL

  #if os(macOS)
  /// Called when a potentially dangerous bash command needs approval.
  /// Return true to allow execution, false to cancel.
  public var bashApprovalHandler: ((String) async -> Bool)?
  #endif

  public init(context: any KanbeiAgentContext) {
    self.workingDirectory = context.workingDirectoryURL

    let fileTree = AgentService.buildFileTree(at: context.workingDirectoryURL)
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

  /// Send a user message and receive a stream of AgentEvents.
  /// The stream finishes when the agent loop ends or an error occurs.
  /// Cancelling the consuming Task will cancel the agent loop via onTermination.
  public func send(
    _ userInput: String,
    images: [(base64: String, mediaType: String)] = [],
    apiKey: String,
    model: String = "claude-sonnet-4-6"
  ) -> AsyncThrowingStream<AgentEvent, Error> {
    AsyncThrowingStream { [weak self] continuation in
      guard let self else { continuation.finish(); return }
      let task = Task {
        do {
          try await self.runLoop(
            userInput: userInput, images: images,
            apiKey: apiKey, model: model,
            continuation: continuation
          )
        } catch is CancellationError {
          // Silently finish; consumer handles the "stopped" state
        } catch {
          continuation.yield(.error(error.localizedDescription))
        }
        continuation.finish()
      }
      continuation.onTermination = { @Sendable _ in task.cancel() }
    }
  }

  public func clearHistory() {
    history.removeAll()
  }

  /// Returns raw API history for persistence.
  public func exportHistory() -> [APIMessage] { history }

  /// Restores API history (e.g. loaded from disk). Strips incomplete tool-use turns.
  public func importHistory(_ h: [APIMessage]) {
    history = sanitizeHistory(h)
  }

  // MARK: - Private state

  private let systemPrompt: String
  private var history: [APIMessage] = []
  private var currentAssistantText = ""  // accumulates text within one API call

  // MARK: - Agent loop

  private func runLoop(
    userInput: String,
    images: [(base64: String, mediaType: String)],
    apiKey: String,
    model: String,
    continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
  ) async throws {
    let trimmed = userInput.trimmingCharacters(in: .whitespaces)
    if images.isEmpty {
      history.append(.user(trimmed))
    } else {
      history.append(.userWithImages(trimmed, images: images))
    }

    continuation.yield(.assistantTurnStarted)

    let tools = AgentTools(workingDirectory: workingDirectory)
    let maxIterations = 50
    var iteration = 0

    while iteration < maxIterations {
      try Task.checkCancellation()
      iteration += 1
      currentAssistantText = ""

      let collectedContents = try await sendWithRetry(
        apiKey: apiKey,
        model: model,
        useHaiku: iteration > 1,
        continuation: continuation,
        onText: { [weak self] text in
          self?.currentAssistantText += text
          continuation.yield(.text(text))
        },
        onToolUse: { [weak self] id, name, input async -> String in
          guard let self else { return "Error" }

          #if os(macOS)
          if name == "bash", let cmd = input["command"] as? String, self.isDangerous(cmd) {
            let approved = await self.bashApprovalHandler?(cmd) ?? false
            guard approved else {
              return String(localized: "bash.approval.cancelled", bundle: .localizedModule)
            }
          }
          #endif

          continuation.yield(.toolRunning(name: name))
          let result = await tools.execute(name: name, input: input)
          let isError = result.hasPrefix("エラー:") || result.hasPrefix("Error:")
            || result.contains("error:") || result.contains("No such file")
          if isError {
            continuation.yield(.toolFailed(name: name, preview: String(result.prefix(120))))
          } else {
            continuation.yield(.toolCompleted(name: name))
          }
          return result
        }
      )

      let toolUseContents = collectedContents.filter { $0.type == "tool_use" }
      let toolResultContents = collectedContents.filter { $0.type == "tool_result" }

      if toolUseContents.isEmpty {
        if !currentAssistantText.isEmpty {
          history.append(.assistant([.text(currentAssistantText)]))
        }
        if looksLikeUnfinishedPlan(currentAssistantText) && iteration < maxIterations - 1 {
          history.append(.user(String(localized: "agent.continue_prompt", bundle: .localizedModule)))
          continuation.yield(.assistantTurnStarted)
        } else {
          break
        }
      } else {
        var assistantContents: [APIContent] = []
        if !currentAssistantText.isEmpty { assistantContents.append(.text(currentAssistantText)) }
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

        continuation.yield(.assistantTurnStarted)
      }
    }

    if iteration >= maxIterations {
      continuation.yield(.maxIterationsReached(maxIterations))
    }
    continuation.yield(.finished)
  }

  // MARK: - API call with retry

  private func sendWithRetry(
    apiKey: String,
    model: String,
    useHaiku: Bool,
    continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation,
    onText: @escaping (String) -> Void,
    onToolUse: @escaping (String, String, [String: Any]) async -> String
  ) async throws -> [APIContent] {
    let maxRetries = 5
    let client = ClaudeAPIClient(
      apiKey: apiKey,
      model: useHaiku ? "claude-haiku-4-5-20251001" : model,
      maxTokens: useHaiku ? 2048 : 4096
    )
    for attempt in 0..<maxRetries {
      do {
        let result = try await client.sendMessages(
          smartTruncatedHistory, tools: AgentTools.definitions,
          systemPrompt: systemPrompt,
          onText: onText, onToolUse: onToolUse
        )
        await TokenUsageStore.shared.record(usage: result.usage)
        return result.contents
      } catch ClaudeError.httpError(429, _) {
        if attempt < maxRetries - 1 {
          let wait = 30 * (1 << attempt)
          continuation.yield(.rateLimitWaiting(seconds: wait, attempt: attempt + 1, maxAttempts: maxRetries - 1))
          try await Task.sleep(for: .seconds(wait))
        } else {
          throw ClaudeError.httpError(429, String(localized: "agent.rate_limit_exceeded", bundle: .localizedModule))
        }
      }
    }
    fatalError("unreachable")
  }

  // MARK: - Helpers

  private var smartTruncatedHistory: [APIMessage] {
    let keepTurns = 5
    let userTextIndices = history.indices.filter {
      history[$0].role == "user" && history[$0].content.first?.type == "text"
    }
    guard userTextIndices.count > keepTurns else { return history }
    let keepFrom = userTextIndices[userTextIndices.count - keepTurns]
    return Array(history[keepFrom...])
  }

  private func sanitizeHistory(_ h: [APIMessage]) -> [APIMessage] {
    var result = h
    while let last = result.last, last.role == "assistant",
          last.content.contains(where: { $0.type == "tool_use" }) {
      result.removeLast()
    }
    return result
  }

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

  #if os(macOS)
  private static let dangerousPatterns: [String] = [
    "rm ", "sudo ", "dd ", "mkfs", "chmod ", "chown ", "kill ", "pkill ",
    "shutdown", "reboot", "mv /", "truncate", "shred", "> /"
  ]

  private func isDangerous(_ command: String) -> Bool {
    Self.dangerousPatterns.contains { command.contains($0) }
  }
  #endif

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
}
