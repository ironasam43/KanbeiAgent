import Foundation
import Combine
import SwiftUI

@MainActor
class AgentViewModel: ObservableObject {
  @Published var messages: [Message] = []
  @Published var isRunning = false
  @Published var errorMessage: String?
  @Published var workingDirectory: URL = FileManager.default.homeDirectoryForCurrentUser

  @AppStorage("claudeApiKey") private var apiKey = ""
  @AppStorage("claudeModel") private var claudeModel = "claude-sonnet-4-6"

  private var apiClient: ClaudeAPIClient { ClaudeAPIClient(apiKey: apiKey, model: claudeModel) }
  private var tools: AgentTools { AgentTools(workingDirectory: workingDirectory) }

  // API送信用の会話履歴
  private var history: [APIMessage] = []

  // MARK: - メッセージ送信

  func send(_ userInput: String) async {
    guard !userInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    guard !apiKey.isEmpty else {
      errorMessage = "設定でClaude API Keyを入力してください"
      return
    }

    // UI追加
    messages.append(Message(role: .user, content: userInput))
    history.append(.user(userInput))

    // Assistantのストリーミング枠を追加
    var assistantIndex = messages.count
    messages.append(Message(role: .assistant, content: "", isStreaming: true))

    isRunning = true
    errorMessage = nil

    do {
      try await runAgentLoop(assistantIndex: assistantIndex)
    } catch {
      errorMessage = error.localizedDescription
    }

    messages[assistantIndex].isStreaming = false
    isRunning = false
  }

  // MARK: - Agentループ

  private func runAgentLoop(assistantIndex startIndex: Int) async throws {
    var assistantIndex = startIndex
    var toolsUsed = false

    while true {
      let collectedContents = try await apiClient.sendMessages(
        history,
        tools: AgentTools.definitions,
        onText: { [weak self] text in
          guard let self else { return }
          self.messages[assistantIndex].content += text
        },
        onToolUse: { [weak self] id, name, input async -> String in
          guard let self else { return "エラー" }
          // ツール実行をUIに表示
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
        // ツール呼び出しなし → 終了
        let assistantContent = messages[assistantIndex].content
        if !assistantContent.isEmpty {
          history.append(.assistant([.text(assistantContent)]))
        }
        break
      } else {
        // ツール結果をhistoryに追加して続行（空テキストは除外）
        var assistantContents: [APIContent] = []
        let assistantText = messages[assistantIndex].content
        if !assistantText.isEmpty {
          assistantContents.append(.text(assistantText))
        }
        assistantContents.append(contentsOf: toolUseContents)
        history.append(.assistant(assistantContents))

        for result in toolResultContents {
          if let toolUseId = result.toolUseId {
            let content = result.content?.isEmpty == false ? result.content! : "(empty)"
            history.append(.toolResult(toolUseId: toolUseId, content: content))
          }
        }

        // 次のAssistant枠を追加
        messages.append(Message(role: .assistant, content: "", isStreaming: true))
        assistantIndex = messages.count - 1
        toolsUsed = true
      }
    }
  }

  // MARK: - 会話リセット

  func clearHistory() {
    messages.removeAll()
    history.removeAll()
    errorMessage = nil
  }
}
