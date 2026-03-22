import Foundation

// MARK: - ツール実行エンジン

struct AgentTools {
  var workingDirectory: URL

  // MARK: - ツール定義一覧（Claude APIに渡す）

  static let definitions: [ToolDefinition] = [
    ToolDefinition(
      name: "file_read",
      description: "指定パスのファイルを読み込む",
      inputSchema: .init(
        type: "object",
        properties: [
          "path": .init(type: "string", description: "読み込むファイルの絶対パスまたは作業ディレクトリからの相対パス")
        ],
        required: ["path"]
      )
    ),
    ToolDefinition(
      name: "file_write",
      description: "指定パスにファイルを書き込む（上書き）",
      inputSchema: .init(
        type: "object",
        properties: [
          "path": .init(type: "string", description: "書き込むファイルのパス"),
          "content": .init(type: "string", description: "書き込む内容")
        ],
        required: ["path", "content"]
      )
    ),
    ToolDefinition(
      name: "bash",
      description: "シェルコマンドを実行する。作業ディレクトリで実行される。",
      inputSchema: .init(
        type: "object",
        properties: [
          "command": .init(type: "string", description: "実行するシェルコマンド")
        ],
        required: ["command"]
      )
    ),
    ToolDefinition(
      name: "list_files",
      description: "ディレクトリ内のファイル一覧を取得する",
      inputSchema: .init(
        type: "object",
        properties: [
          "path": .init(type: "string", description: "一覧を取得するディレクトリのパス。省略時は作業ディレクトリ。")
        ],
        required: []
      )
    ),
  ]

  // MARK: - ツール実行

  func execute(name: String, input: [String: Any]) async -> String {
    switch name {
    case "file_read":
      return fileRead(input: input)
    case "file_write":
      return fileWrite(input: input)
    case "bash":
      return await bash(input: input)
    case "list_files":
      return listFiles(input: input)
    default:
      return "エラー: 未知のツール '\(name)'"
    }
  }

  // MARK: - 各ツール実装

  private func fileRead(input: [String: Any]) -> String {
    guard let path = input["path"] as? String else { return "エラー: path が必要です" }
    let url = resolvedURL(path)
    do {
      return try String(contentsOf: url, encoding: .utf8)
    } catch {
      return "エラー: \(error.localizedDescription)"
    }
  }

  private func fileWrite(input: [String: Any]) -> String {
    guard let path = input["path"] as? String,
          let content = input["content"] as? String else {
      return "エラー: path と content が必要です"
    }
    let url = resolvedURL(path)
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try content.write(to: url, atomically: true, encoding: .utf8)
      return "書き込み完了: \(url.path)"
    } catch {
      return "エラー: \(error.localizedDescription)"
    }
  }

  private func bash(input: [String: Any]) async -> String {
    guard let command = input["command"] as? String else { return "エラー: command が必要です" }
    return await withCheckedContinuation { continuation in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/bin/zsh")
      process.arguments = ["-c", command]
      process.currentDirectoryURL = workingDirectory
      process.environment = ProcessInfo.processInfo.environment

      let outPipe = Pipe()
      let errPipe = Pipe()
      process.standardOutput = outPipe
      process.standardError = errPipe

      do {
        try process.run()
        process.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let result = [out, err].filter { !$0.isEmpty }.joined(separator: "\n")
        continuation.resume(returning: result.isEmpty ? "（出力なし）" : result)
      } catch {
        continuation.resume(returning: "エラー: \(error.localizedDescription)")
      }
    }
  }

  private func listFiles(input: [String: Any]) -> String {
    let path = input["path"] as? String
    let url = path.map { resolvedURL($0) } ?? workingDirectory
    do {
      let items = try FileManager.default.contentsOfDirectory(
        at: url, includingPropertiesForKeys: [.isDirectoryKey]
      )
      return items.map { item in
        let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        return isDir ? "\(item.lastPathComponent)/" : item.lastPathComponent
      }.sorted().joined(separator: "\n")
    } catch {
      return "エラー: \(error.localizedDescription)"
    }
  }

  // MARK: - ヘルパー

  private func resolvedURL(_ path: String) -> URL {
    if path.hasPrefix("/") {
      return URL(fileURLWithPath: path)
    }
    return workingDirectory.appendingPathComponent(path)
  }
}
