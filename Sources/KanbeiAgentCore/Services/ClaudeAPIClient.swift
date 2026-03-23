import Foundation

// MARK: - Claude API クライアント（SSEストリーミング + tool_use対応）

public class ClaudeAPIClient {
  private let apiKey: String
  private let model: String
  private let maxTokens: Int
  private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

  public init(apiKey: String, model: String = "claude-sonnet-4-6", maxTokens: Int = 4096) {
    self.apiKey = apiKey
    self.model = model
    self.maxTokens = maxTokens
  }

  public func sendMessages(
    _ messages: [APIMessage],
    tools: [ToolDefinition],
    systemPrompt: String,
    onText: @escaping (String) -> Void,
    onToolUse: @escaping (String, String, [String: Any]) async -> String
  ) async throws -> (contents: [APIContent], usage: APIUsage) {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    request.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")

    let systemArray: [[String: Any]] = [[
      "type": "text",
      "text": systemPrompt,
      "cache_control": ["type": "ephemeral"]
    ]]

    var toolsJSON = (try? JSONSerialization.jsonObject(
      with: JSONEncoder().encode(tools)
    ) as? [[String: Any]]) ?? []
    if !toolsJSON.isEmpty {
      toolsJSON[toolsJSON.count - 1]["cache_control"] = ["type": "ephemeral"]
    }

    let body: [String: Any] = [
      "model": model,
      "max_tokens": maxTokens,
      "stream": true,
      "system": systemArray,
      "tools": toolsJSON,
      "messages": try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(messages)
      )
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (stream, response): (URLSession.AsyncBytes, URLResponse)
    do {
      (stream, response) = try await URLSession.shared.bytes(for: request)
    } catch let urlError as URLError {
      switch urlError.code {
      case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost:
        throw ClaudeError.noNetwork
      case .timedOut:
        throw ClaudeError.timeout
      default:
        throw ClaudeError.networkError(urlError.localizedDescription)
      }
    }
    guard let http = response as? HTTPURLResponse else { throw ClaudeError.networkError("無効なレスポンス") }
    guard (200..<300).contains(http.statusCode) else {
      var body = ""
      for try await line in stream.lines { body += line + "\n" }
      switch http.statusCode {
      case 401: throw ClaudeError.unauthorized
      case 403: throw ClaudeError.forbidden
      case 429: throw ClaudeError.httpError(429, body)
      case 500..<600: throw ClaudeError.serverError(http.statusCode)
      default: throw ClaudeError.httpError(http.statusCode, body)
      }
    }

    var collectedContents: [APIContent] = []
    var currentToolId = ""
    var currentToolName = ""
    var currentToolInputJSON = ""
    var inputTokens = 0
    var outputTokens = 0

    for try await line in stream.lines {
      guard line.hasPrefix("data: ") else { continue }
      let jsonStr = String(line.dropFirst(6))
      guard jsonStr != "[DONE]",
            let data = jsonStr.data(using: .utf8),
            let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = event["type"] as? String
      else { continue }

      switch type {
      case "message_start":
        if let message = event["message"] as? [String: Any],
           let usage = message["usage"] as? [String: Any] {
          inputTokens += usage["input_tokens"] as? Int ?? 0
        }

      case "message_delta":
        if let usage = event["usage"] as? [String: Any] {
          outputTokens += usage["output_tokens"] as? Int ?? 0
        }

      case "content_block_start":
        if let block = event["content_block"] as? [String: Any],
           let blockType = block["type"] as? String, blockType == "tool_use" {
          currentToolId = block["id"] as? String ?? ""
          currentToolName = block["name"] as? String ?? ""
          currentToolInputJSON = ""
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
          let input = (try? JSONSerialization.jsonObject(
            with: currentToolInputJSON.data(using: .utf8) ?? Data()
          ) as? [String: Any]) ?? [:]

          collectedContents.append(APIContent(
            type: "tool_use", id: currentToolId, name: currentToolName, input: AnyCodable(input)
          ))
          let result = await onToolUse(currentToolId, currentToolName, input)
          collectedContents.append(APIContent(
            type: "tool_result", content: result, toolUseId: currentToolId
          ))
          currentToolName = ""
          currentToolId = ""
        }

      default:
        break
      }
    }

    let usage = APIUsage(inputTokens: inputTokens, outputTokens: outputTokens)
    return (contents: collectedContents, usage: usage)
  }
}

public enum ClaudeError: LocalizedError {
  case httpError(Int, String)
  case parseError
  case unauthorized
  case forbidden
  case noNetwork
  case timeout
  case networkError(String)
  case serverError(Int)

  public var errorDescription: String? {
    switch self {
    case .unauthorized:
      return "APIキーが無効です。設定を確認してください。"
    case .forbidden:
      return "このAPIキーにはアクセス権限がありません。"
    case .noNetwork:
      return "ネットワークに接続できません。接続を確認してください。"
    case .timeout:
      return "リクエストがタイムアウトしました。再度お試しください。"
    case .networkError(let msg):
      return "通信エラー: \(msg)"
    case .serverError(let code):
      return "Claude APIサーバーエラー (HTTP \(code))。しばらく待ってから再試行してください。"
    case .httpError(let code, let body):
      return "Claude API エラー (HTTP \(code))\n\(body)"
    case .parseError:
      return "レスポンスの解析に失敗しました。"
    }
  }
}
