import Foundation

// MARK: - ツール実行エンジン

public struct AgentTools {
  public var workingDirectory: URL

  public init(workingDirectory: URL) {
    self.workingDirectory = workingDirectory
  }

  // MARK: - ツール定義一覧（Claude APIに渡す）

  public static let definitions: [ToolDefinition] = [
    ToolDefinition(
      name: "file_read",
      description: "指定パスのファイルを読み込む。offset/limitで行範囲を指定できる（大きなファイルは必要部分だけ読むこと）",
      inputSchema: .init(
        type: "object",
        properties: [
          "path": .init(type: "string", description: "読み込むファイルの絶対パスまたは作業ディレクトリからの相対パス"),
          "offset": .init(type: "integer", description: "読み始める行番号（1始まり）。省略時は先頭から"),
          "limit": .init(type: "integer", description: "読む行数の上限。省略時は全行")
        ],
        required: ["path"]
      )
    ),
    ToolDefinition(
      name: "str_replace",
      description: "ファイル内の特定テキストを別のテキストに置換する。ファイル全体の書き直しより効率的。old_strは必ずファイル内に一意に存在する文字列を指定すること。",
      inputSchema: .init(
        type: "object",
        properties: [
          "path": .init(type: "string", description: "編集するファイルのパス"),
          "old_str": .init(type: "string", description: "置換前のテキスト（ファイル内で一意に存在する文字列）"),
          "new_str": .init(type: "string", description: "置換後のテキスト")
        ],
        required: ["path", "old_str", "new_str"]
      )
    ),
    ToolDefinition(
      name: "file_write",
      description: "指定パスにファイルを書き込む（上書き）。部分編集はstr_replaceを使うこと。",
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
    ToolDefinition(
      name: "grep",
      description: "ファイル内容を正規表現で検索する。マッチした行をファイルパスと行番号付きで返す。",
      inputSchema: .init(
        type: "object",
        properties: [
          "pattern": .init(type: "string", description: "検索する正規表現パターン"),
          "path": .init(type: "string", description: "検索対象のディレクトリまたはファイルパス。省略時は作業ディレクトリ。"),
          "glob": .init(type: "string", description: "対象ファイルを絞るglobパターン（例: *.swift）。省略時は全ファイル。")
        ],
        required: ["pattern"]
      )
    ),
    ToolDefinition(
      name: "glob",
      description: "globパターンでファイルパスを検索する",
      inputSchema: .init(
        type: "object",
        properties: [
          "pattern": .init(type: "string", description: "globパターン（例: **/*.swift, src/**/*.ts）"),
          "path": .init(type: "string", description: "検索のベースディレクトリ。省略時は作業ディレクトリ。")
        ],
        required: ["pattern"]
      )
    ),
  ]

  // MARK: - ツール実行

  public func execute(name: String, input: [String: Any]) async -> String {
    switch name {
    case "file_read":
      return fileRead(input: input)
    case "str_replace":
      return strReplace(input: input)
    case "file_write":
      return fileWrite(input: input)
    case "bash":
      return await bash(input: input)
    case "list_files":
      return listFiles(input: input)
    case "grep":
      return grep(input: input)
    case "glob":
      return glob(input: input)
    default:
      return "エラー: 未知のツール '\(name)'"
    }
  }

  // MARK: - 各ツール実装

  private func fileRead(input: [String: Any]) -> String {
    guard let path = input["path"] as? String else { return "エラー: path が必要です" }
    let url = resolvedURL(path)
    do {
      let content = try String(contentsOf: url, encoding: .utf8)
      let lines = content.components(separatedBy: "\n")
      let offset = (input["offset"] as? Int).map { max(0, $0 - 1) } ?? 0
      let limit = input["limit"] as? Int
      let sliced = limit.map { Array(lines.dropFirst(offset).prefix($0)) } ?? Array(lines.dropFirst(offset))
      let startLine = offset + 1
      let numbered = sliced.enumerated().map { "\(startLine + $0.offset): \($0.element)" }
      return numbered.joined(separator: "\n")
    } catch {
      return "エラー: \(error.localizedDescription)"
    }
  }

  private func strReplace(input: [String: Any]) -> String {
    guard let path = input["path"] as? String,
          let oldStr = input["old_str"] as? String,
          let newStr = input["new_str"] as? String else {
      return "エラー: path, old_str, new_str が必要です"
    }
    let url = resolvedURL(path)
    do {
      let content = try String(contentsOf: url, encoding: .utf8)
      let count = content.components(separatedBy: oldStr).count - 1
      if count == 0 { return "エラー: old_str がファイル内に見つかりません" }
      if count > 1 { return "エラー: old_str がファイル内に\(count)箇所あります。一意に特定できる文字列を指定してください" }
      let replaced = content.replacingOccurrences(of: oldStr, with: newStr)
      try replaced.write(to: url, atomically: true, encoding: .utf8)
      return "置換完了: \(url.lastPathComponent)"
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
    let result = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/bin/zsh")
      process.arguments = ["-c", command]
      process.currentDirectoryURL = workingDirectory
      var env = ProcessInfo.processInfo.environment
      if let token = UserDefaults.standard.string(forKey: "githubToken"), !token.isEmpty {
        env["GITHUB_TOKEN"] = token
      }
      process.environment = env

      let outPipe = Pipe()
      let errPipe = Pipe()
      process.standardOutput = outPipe
      process.standardError = errPipe

      let syncQueue = DispatchQueue(label: "com.kanbei.bash.resume")
      var resumed = false

      @Sendable func tryResume(_ value: String) {
        syncQueue.sync {
          guard !resumed else { return }
          resumed = true
          continuation.resume(returning: value)
        }
      }

      process.terminationHandler = { _ in
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let output = [out, err].filter { !$0.isEmpty }.joined(separator: "\n")
        tryResume(output.isEmpty ? "（出力なし）" : output)
      }

      do {
        try process.run()
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
          guard process.isRunning else { return }
          process.terminate()
          tryResume("エラー: タイムアウト（30秒）でコマンドを強制終了しました")
        }
      } catch {
        tryResume("エラー: \(error.localizedDescription)")
      }
    }
    appendBashLog(command: command, result: result)
    return result
  }

  private func appendBashLog(command: String, result: String) {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let logURL = support.appendingPathComponent("KanbeiAgent/bash.log")
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let entry = "[\(timestamp)] $ \(command)\n\(result)\n\n"
    if let data = entry.data(using: .utf8),
       let handle = try? FileHandle(forWritingTo: logURL) {
      handle.seekToEndOfFile()
      handle.write(data)
      try? handle.close()
    } else {
      try? entry.data(using: .utf8)?.write(to: logURL)
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

  private func grep(input: [String: Any]) -> String {
    guard let pattern = input["pattern"] as? String else { return "エラー: pattern が必要です" }
    let basePath = input["path"] as? String
    let baseURL = basePath.map { resolvedURL($0) } ?? workingDirectory
    let globPattern = input["glob"] as? String

    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return "エラー: 無効な正規表現パターン"
    }

    var results: [String] = []
    let files = allFiles(in: baseURL, matching: globPattern)

    for fileURL in files {
      guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
      let lines = content.components(separatedBy: "\n")
      for (i, line) in lines.enumerated() {
        let range = NSRange(line.startIndex..., in: line)
        if regex.firstMatch(in: line, range: range) != nil {
          let relativePath = fileURL.path.replacingOccurrences(of: workingDirectory.path + "/", with: "")
          results.append("\(relativePath):\(i + 1): \(line)")
        }
      }
    }

    return results.isEmpty ? "（マッチなし）" : results.joined(separator: "\n")
  }

  private func glob(input: [String: Any]) -> String {
    guard let pattern = input["pattern"] as? String else { return "エラー: pattern が必要です" }
    let basePath = input["path"] as? String
    let baseURL = basePath.map { resolvedURL($0) } ?? workingDirectory

    let files = allFiles(in: baseURL, matching: pattern)
    let paths = files.map { url -> String in
      url.path.replacingOccurrences(of: workingDirectory.path + "/", with: "")
    }.sorted()

    return paths.isEmpty ? "（マッチなし）" : paths.joined(separator: "\n")
  }

  private func allFiles(in directory: URL, matching globPattern: String?) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
      at: directory,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else { return [] }

    let ignored: Set<String> = [".git", "node_modules", ".build", "DerivedData"]
    var files: [URL] = []

    for case let url as URL in enumerator {
      let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
      if isDir {
        if ignored.contains(url.lastPathComponent) { enumerator.skipDescendants() }
        continue
      }
      if let pattern = globPattern {
        let name = url.lastPathComponent
        let pred = NSPredicate(format: "SELF LIKE %@", pattern)
        guard pred.evaluate(with: name) else { continue }
      }
      files.append(url)
    }
    return files
  }

  // MARK: - ヘルパー

  private func resolvedURL(_ path: String) -> URL {
    if path.hasPrefix("/") {
      return URL(fileURLWithPath: path)
    }
    return workingDirectory.appendingPathComponent(path)
  }
}
