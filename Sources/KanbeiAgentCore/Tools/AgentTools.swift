//
//  AgentTools.swift
//  KanbeiAgentCore
//

import Foundation

// MARK: - Tool execution engine

public struct AgentTools {
  public var workingDirectory: URL

  /// App Sandbox が有効かどうかをランタイムで検出する。
  /// MAS sandbox では `APP_SANDBOX_CONTAINER_ID` 環境変数が必ず存在する。
  public static var isSandboxed: Bool {
    ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
  }

  public init(workingDirectory: URL) {
    self.workingDirectory = workingDirectory
  }

  // MARK: - Tool definition list (to pass to Claude API)

  public static var definitions: [ToolDefinition] {
    var defs: [ToolDefinition] = [
      ToolDefinition(
        name: "file_read",
        description: "Read file at specified path. Can specify line range with offset/limit (for large files, read only the necessary part)",
        inputSchema: .init(
          type: "object",
          properties: [
            "path": .init(type: "string", description: "Absolute path or relative path from working directory of file to read"),
            "offset": .init(type: "integer", description: "Line number to start reading (1-indexed). Defaults to start from beginning"),
            "limit": .init(type: "integer", description: "Maximum number of lines to read. Defaults to all lines")
          ],
          required: ["path"]
        )
      ),
      ToolDefinition(
        name: "str_replace",
        description: "Replace specific text in file with different text. More efficient than rewriting entire file. old_str must be a string that uniquely exists in the file.",
        inputSchema: .init(
          type: "object",
          properties: [
            "path": .init(type: "string", description: "Path of file to edit"),
            "old_str": .init(type: "string", description: "Text before replacement (string that uniquely exists in file)"),
            "new_str": .init(type: "string", description: "Text after replacement")
          ],
          required: ["path", "old_str", "new_str"]
        )
      ),
      ToolDefinition(
        name: "file_write",
        description: "Write file to specified path (overwrite). Use str_replace for partial edits.",
        inputSchema: .init(
          type: "object",
          properties: [
            "path": .init(type: "string", description: "Path of file to write"),
            "content": .init(type: "string", description: "Content to write")
          ],
          required: ["path", "content"]
        )
      ),
      ToolDefinition(
        name: "list_files",
        description: "Get list of files in directory",
        inputSchema: .init(
          type: "object",
          properties: [
            "path": .init(type: "string", description: "Path of directory to list. Defaults to working directory.")
          ],
          required: []
        )
      ),
      ToolDefinition(
        name: "grep",
        description: "Search file content with regular expression. Returns matched lines with file path and line number.",
        inputSchema: .init(
          type: "object",
          properties: [
            "pattern": .init(type: "string", description: "Regular expression pattern to search"),
            "path": .init(type: "string", description: "Directory or file path to search. Defaults to working directory."),
            "glob": .init(type: "string", description: "Glob pattern to narrow target files (e.g.: *.swift). Defaults to all files.")
          ],
          required: ["pattern"]
        )
      ),
      ToolDefinition(
        name: "glob",
        description: "Search file paths with glob pattern",
        inputSchema: .init(
          type: "object",
          properties: [
            "pattern": .init(type: "string", description: "Glob pattern (e.g.: **/*.swift, src/**/*.ts)"),
            "path": .init(type: "string", description: "Base directory for search. Defaults to working directory.")
          ],
          required: ["pattern"]
        )
      ),
    ]
    #if os(macOS)
    if !AgentTools.isSandboxed {
      defs.append(ToolDefinition(
        name: "bash",
        description: "Execute shell command. Runs in working directory.",
        inputSchema: .init(
          type: "object",
          properties: [
            "command": .init(type: "string", description: "Shell command to execute")
          ],
          required: ["command"]
        )
      ))
    }
    #endif
    return defs
  }

  // MARK: - Tool execution

  public func execute(name: String, input: [String: Any]) async -> String {
    switch name {
    case "file_read":
      return fileRead(input: input)
    case "str_replace":
      return strReplace(input: input)
    case "file_write":
      return fileWrite(input: input)
    #if os(macOS)
    case "bash":
      guard !AgentTools.isSandboxed else { return "Error: bash is not available in sandbox mode" }
      return await bash(input: input)
    #endif
    case "list_files":
      return listFiles(input: input)
    case "grep":
      return grep(input: input)
    case "glob":
      return glob(input: input)
    default:
      return "Error: Unknown tool '\(name)'"
    }
  }

  // MARK: - Individual tool implementations

  private func fileRead(input: [String: Any]) -> String {
    guard let path = input["path"] as? String else { return "Error: path is required" }
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
      return "Error: \(error.localizedDescription)"
    }
  }

  private func strReplace(input: [String: Any]) -> String {
    guard let path = input["path"] as? String,
          let oldStr = input["old_str"] as? String,
          let newStr = input["new_str"] as? String else {
      return "Error: path, old_str, new_str are required"
    }
    let url = resolvedURL(path)
    do {
      let content = try String(contentsOf: url, encoding: .utf8)
      let count = content.components(separatedBy: oldStr).count - 1
      if count == 0 { return "Error: old_str not found in file" }
      if count > 1 { return "Error: old_str found in \(count) places in file. Please specify a uniquely identifiable string" }
      let replaced = content.replacingOccurrences(of: oldStr, with: newStr)
      try replaced.write(to: url, atomically: true, encoding: .utf8)
      return "Replacement complete: \(url.lastPathComponent)"
    } catch {
      return "Error: \(error.localizedDescription)"
    }
  }

  private func fileWrite(input: [String: Any]) -> String {
    guard let path = input["path"] as? String,
          let content = input["content"] as? String else {
      return "Error: path and content are required"
    }
    let url = resolvedURL(path)
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try content.write(to: url, atomically: true, encoding: .utf8)
      return "Write complete: \(url.path)"
    } catch {
      return "Error: \(error.localizedDescription)"
    }
  }

  #if os(macOS)
  private func bash(input: [String: Any]) async -> String {
    guard let command = input["command"] as? String else { return "Error: command is required" }
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
        tryResume(output.isEmpty ? "(No output)" : output)
      }

      do {
        try process.run()
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
          guard process.isRunning else { return }
          process.terminate()
          tryResume("Error: Command forcefully terminated due to timeout (30 seconds)")
        }
      } catch {
        tryResume("Error: \(error.localizedDescription)")
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
  #endif

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
      return "Error: \(error.localizedDescription)"
    }
  }

  private func grep(input: [String: Any]) -> String {
    guard let pattern = input["pattern"] as? String else { return "Error: pattern is required" }
    let basePath = input["path"] as? String
    let baseURL = basePath.map { resolvedURL($0) } ?? workingDirectory
    let globPattern = input["glob"] as? String

    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return "Error: Invalid regular expression pattern"
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

    return results.isEmpty ? "(No matches)" : results.joined(separator: "\n")
  }

  private func glob(input: [String: Any]) -> String {
    guard let pattern = input["pattern"] as? String else { return "Error: pattern is required" }
    let basePath = input["path"] as? String
    let baseURL = basePath.map { resolvedURL($0) } ?? workingDirectory

    let files = allFiles(in: baseURL, matching: pattern)
    let paths = files.map { url -> String in
      url.path.replacingOccurrences(of: workingDirectory.path + "/", with: "")
    }.sorted()

    return paths.isEmpty ? "(No matches)" : paths.joined(separator: "\n")
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

  // MARK: - Helper

  private func resolvedURL(_ path: String) -> URL {
    if path.hasPrefix("/") {
      return URL(fileURLWithPath: path)
    }
    return workingDirectory.appendingPathComponent(path)
  }
}
