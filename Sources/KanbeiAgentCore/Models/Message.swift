import Foundation

// MARK: - チャットメッセージ（UI表示用）

public struct Message: Identifiable, Codable {
  public let id: UUID
  public let role: Role
  public var content: String
  public var isStreaming: Bool = false

  public init(id: UUID = UUID(), role: Role, content: String, isStreaming: Bool = false) {
    self.id = id
    self.role = role
    self.content = content
    self.isStreaming = isStreaming
  }

  public enum Role: String, Codable {
    case user, assistant, tool
  }
}

// MARK: - Claude API メッセージ形式

public struct APIMessage: Codable {
  public let role: String
  public var content: [APIContent]

  public static func user(_ text: String) -> APIMessage {
    APIMessage(role: "user", content: [.text(text)])
  }

  public static func userWithImages(_ text: String, images: [(base64: String, mediaType: String)]) -> APIMessage {
    var contents: [APIContent] = images.map { .image(base64: $0.base64, mediaType: $0.mediaType) }
    if !text.trimmingCharacters(in: .whitespaces).isEmpty {
      contents.append(.text(text))
    }
    return APIMessage(role: "user", content: contents)
  }

  public static func assistant(_ contents: [APIContent]) -> APIMessage {
    APIMessage(role: "assistant", content: contents)
  }
}

public struct APIContent: Codable {
  public let type: String
  public var text: String?
  public var id: String?
  public var name: String?
  public var input: AnyCodable?
  public var content: String?
  public var toolUseId: String?
  public var source: ImageSource?

  public enum CodingKeys: String, CodingKey {
    case type, text, id, name, input, source
    case toolUseId = "tool_use_id"
    case content
  }

  public init(
    type: String, text: String? = nil, id: String? = nil, name: String? = nil,
    input: AnyCodable? = nil, content: String? = nil, toolUseId: String? = nil,
    source: ImageSource? = nil
  ) {
    self.type = type; self.text = text; self.id = id; self.name = name
    self.input = input; self.content = content; self.toolUseId = toolUseId; self.source = source
  }

  public static func text(_ value: String) -> APIContent {
    APIContent(type: "text", text: value)
  }

  public static func image(base64: String, mediaType: String) -> APIContent {
    APIContent(type: "image", source: ImageSource(type: "base64", mediaType: mediaType, data: base64))
  }
}

public struct ImageSource: Codable {
  public let type: String
  public let mediaType: String
  public let data: String

  public enum CodingKeys: String, CodingKey {
    case type
    case mediaType = "media_type"
    case data
  }

  public init(type: String, mediaType: String, data: String) {
    self.type = type; self.mediaType = mediaType; self.data = data
  }
}

// MARK: - ツール定義

public struct ToolDefinition: Codable {
  public let name: String
  public let description: String
  public let inputSchema: InputSchema

  public enum CodingKeys: String, CodingKey {
    case name, description
    case inputSchema = "input_schema"
  }

  public struct InputSchema: Codable {
    public let type: String
    public let properties: [String: Property]
    public let required: [String]

    public struct Property: Codable {
      public let type: String
      public let description: String
    }
  }
}

// MARK: - Codable Any

public struct AnyCodable: Codable {
  public let value: Any

  public init(_ value: Any) { self.value = value }

  public init(from decoder: Decoder) throws {
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

  public func encode(to encoder: Encoder) throws {
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
