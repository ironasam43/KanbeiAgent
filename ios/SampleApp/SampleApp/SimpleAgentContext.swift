//
//  SimpleAgentContext.swift
//  KanbeiAgent
//

import Foundation
import KanbeiAgentCore

/// Simple context for standalone version of KanbeiAgent
struct SimpleAgentContext: KanbeiAgentContext {
  let workingDirectoryURL: URL
  let historyFileName: String = "history"
  let systemPromptAddendum: String = ""
}
