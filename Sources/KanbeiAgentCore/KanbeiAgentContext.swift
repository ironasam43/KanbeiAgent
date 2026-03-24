//
//  KanbeiAgentContext.swift
//  KanbeiAgentCore
//

import Foundation

/// Protocol providing context information needed when using KanbeiAgent
public protocol KanbeiAgentContext {
  /// Working directory where the agent operates
  var workingDirectoryURL: URL { get }
  /// File name for saving conversation history (without extension) e.g.: "history", "issue-123"
  var historyFileName: String { get }
  /// Additional information for the system prompt (such as issue information)
  var systemPromptAddendum: String { get }
}
