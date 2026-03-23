import Foundation
import KanbeiAgentCore

/// スタンドアロン版 KanbeiAgent 用のシンプルなコンテキスト
struct SimpleAgentContext: KanbeiAgentContext {
  let workingDirectoryURL: URL
  let historyFileName: String = "history"
  let systemPromptAddendum: String = ""
}
