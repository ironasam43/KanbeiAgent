import Foundation

// MARK: - チャットメッセージ（UI表示用）

struct Message: Identifiable {
  let id = UUID()
  let role: Role
  var content: String
  var isStreaming: Bool = false

  enum Role {
    case user, assistant, tool
  }
}

// MARK: - Claude API メッセージ形式

struct APIMessage: Codable {
  let role: String
  var content: [APIContent]

  static func user(_ text: String) -> APIMessage {
    APIMessage(role: "user", content: [.text(text)])
  }

  static func assistant(_ contents: [APIContent]) -> APIMessage {
    APIMessage(role: "assistant", content: contents)
  }

  static func toolResult(toolUseId: String, content: String) -> APIMessage {
    APIMessage(role: "user", content: [
      APIContent(type: "tool_result", toolUseId: toolUseId, content: content)
    ])
  }
}

struct APIContent: Codable {
  let type: String
  var text: String?
  var id: String?          // tool_use の id
  var name: String?        // tool_use の name
  var input: AnyCodable?   // tool_use の input
  var toolUseId: String?   // tool_result の tool_use_id
  var content: String?     // tool_result の content

  enum CodingKeys: String, CodingKey {
    case type, text, id, name, input
    case toolUseId = "tool_use_id"
    case content
  }

  static func text(_ value: String) -> APIContent {
    APIContent(type: "text", text: value)
  }
}

// MARK: - ツール定義

struct ToolDefinition: Codable {
  let name: String
  let description: String
  let inputSchema: InputSchema

  enum CodingKeys: String, CodingKey {
    case name, description
    case inputSchema = "input_schema"
  }

  struct InputSchema: Codable {
    let type: String
    let properties: [String: Property]
    let required: [String]

    struct Property: Codable {
      let type: String
      let description: String
    }
  }
}

// MARK: - Codable Any

struct AnyCodable: Codable {
  let value: Any

  init(_ value: Any) { self.value = value }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let dict = try? container.decode([String: AnyCodable].self) {
      value = dict.mapValues { $0.value }
    } else if let arr = try? container.decode([AnyCodable].self) {
      value = arr.map { $0.value }
    } else if let str = try? container.decode(String.self) {
      value = str
    } else if let num = try? container.decode(Double.self) {
      value = num
    } else if let bool = try? container.decode(Bool.self) {
      value = bool
    } else {
      value = ""
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch value {
    case let dict as [String: Any]:
      try container.encode(dict.mapValues { AnyCodable($0) })
    case let arr as [Any]:
      try container.encode(arr.map { AnyCodable($0) })
    case let str as String:
      try container.encode(str)
    case let num as Double:
      try container.encode(num)
    case let bool as Bool:
      try container.encode(bool)
    default:
      try container.encode("")
    }
  }
}
