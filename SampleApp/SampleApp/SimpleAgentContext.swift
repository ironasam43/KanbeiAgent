//
//  SimpleAgentContext.swift
//  KanbeiAgent
//

import Foundation
import KanbeiAgentCore

/// Simple context for standalone version of KanbeiAgent
struct SimpleAgentContext: KanbeiAgentContext {
  let workingDirectoryURL: URL
  let workspaceRoot: URL?
  let historyFileName: String = "history"
  let systemPromptAddendum: String = ""

  init(workingDirectoryURL: URL, workspaceRoot: URL? = nil) {
    self.workingDirectoryURL = workingDirectoryURL
    self.workspaceRoot = workspaceRoot
  }

  var contextFiles: [URL] {
    var candidates: [URL] = []

    // workspace root の handoff.md
    if let root = workspaceRoot {
      candidates.append(root.appendingPathComponent("handoff.md"))
    }

    // working directory 内の handoff.md（直下 / docs/）
    candidates.append(workingDirectoryURL.appendingPathComponent("handoff.md"))
    candidates.append(workingDirectoryURL.appendingPathComponent("docs/handoff.md"))

    let fm = FileManager.default
    var seen = Set<String>()
    return candidates.filter { url in
      let path = url.standardizedFileURL.path
      guard fm.fileExists(atPath: path), !seen.contains(path) else { return false }
      seen.insert(path)
      return true
    }
  }
}
