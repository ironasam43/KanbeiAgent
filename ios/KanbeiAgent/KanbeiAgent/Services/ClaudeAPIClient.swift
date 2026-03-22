import Foundation

// MARK: - Claude API クライアント（SSEストリーミング + tool_use対応）

class ClaudeAPIClient {
  private let apiKey: String
  private let model = "claude-sonnet-4-6"
  private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

  init(apiKey: String) {
    self.apiKey = apiKey
  }

  // MARK: - ストリーミングリクエスト

  /// メッセージを送信し、テキストをストリーミングで受け取る
  /// tool_use が来た場合はコールバックで通知し、呼び出し元がtool_resultを返す
  func sendMessages(
    _ messages: [APIMessage],
    tools: [ToolDefinition],
    onText: @escaping (String) -> Void,
    onToolUse: @escaping (String, String, [String: Any]) async -> String  // (id, name, input) -> result
  ) async throws -> [APIContent] {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

    let body: [String: Any] = [
      "model": model,
      "max_tokens": 8096,
      "stream": true,
      "tools": try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(tools)
      ),
      "messages": try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(messages)
      )
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (stream, response) = try await URLSession.shared.bytes(for: request)
    guard let http = response as? HTTPURLResponse else { throw ClaudeError.httpError(0, "") }
    guard (200..<300).contains(http.statusCode) else {
      var body = ""
      for try await line in stream.lines { body += line + "\n" }
      throw ClaudeError.httpError(http.statusCode, body)
    }

    // SSEパース
    var collectedContents: [APIContent] = []
    var currentToolId = ""
    var currentToolName = ""
    var currentToolInputJSON = ""

    for try await line in stream.lines {
      guard line.hasPrefix("data: ") else { continue }
      let jsonStr = String(line.dropFirst(6))
      guard jsonStr != "[DONE]",
            let data = jsonStr.data(using: .utf8),
            let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = event["type"] as? String
      else { continue }

      switch type {
      case "content_block_start":
        if let block = event["content_block"] as? [String: Any],
           let blockType = block["type"] as? String {
          if blockType == "tool_use" {
            currentToolId = block["id"] as? String ?? ""
            currentToolName = block["name"] as? String ?? ""
            currentToolInputJSON = ""
          }
        }

      case "content_block_delta":
        if let delta = event["delta"] as? [String: Any],
           let deltaType = delta["type"] as? String {
          if deltaType == "text_delta", let text = delta["text"] as? String {
            onText(text)
          } else if deltaType == "input_json_delta", let partial = delta["partial_json"] as? String {
            currentToolInputJSON += partial
          }
        }

      case "content_block_stop":
        if !currentToolName.isEmpty {
          // tool_useブロック完了 → 実行
          let input = (try? JSONSerialization.jsonObject(
            with: currentToolInputJSON.data(using: .utf8) ?? Data()
          ) as? [String: Any]) ?? [:]

          collectedContents.append(APIContent(
            type: "tool_use",
            id: currentToolId,
            name: currentToolName,
            input: AnyCodable(input)
          ))

          let result = await onToolUse(currentToolId, currentToolName, input)
          collectedContents.append(APIContent(
            type: "tool_result",
            content: result,
            toolUseId: currentToolId
          ))

          currentToolName = ""
          currentToolId = ""
        }

      case "message_stop":
        break

      default:
        break
      }
    }

    return collectedContents
  }
}

enum ClaudeError: LocalizedError {
  case httpError(Int, String)
  case parseError

  var errorDescription: String? {
    switch self {
    case .httpError(let code, let body): "Claude API エラー (HTTP \(code))\n\(body)"
    case .parseError: "レスポンスの解析に失敗しました"
    }
  }
}
