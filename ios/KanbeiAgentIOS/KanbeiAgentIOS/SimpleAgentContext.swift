//
//  SimpleAgentContext.swift
//  KanbeiAgentIOS
//

import Foundation
import KanbeiAgentCore

struct SimpleAgentContext: KanbeiAgentContext {
  let workingDirectoryURL: URL
  let historyFileName: String = "history"
  let systemPromptAddendum: String = ""
}
