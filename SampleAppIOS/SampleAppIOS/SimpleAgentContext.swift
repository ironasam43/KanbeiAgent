//
//  SimpleAgentContext.swift
//  KanbeiAgentIOS
//

import Foundation
import KanbeiAgentCore

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
    guard let root = workspaceRoot else { return [] }
    let handoff = root.appendingPathComponent("handoff.md")
    guard FileManager.default.fileExists(atPath: handoff.path) else { return [] }
    return [handoff]
  }
}
