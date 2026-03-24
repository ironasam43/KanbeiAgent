//
//  AgentEvent.swift
//  KanbeiAgentCore
//

import Foundation

/// Events emitted by AgentService during an agent run.
/// Consumers can drive any UI (SwiftUI, UIKit, AppKit, CLI) by handling these events.
public enum AgentEvent: Sendable {
  /// Streaming text chunk from the assistant
  case text(String)
  /// A tool started executing
  case toolRunning(name: String)
  /// A tool completed successfully
  case toolCompleted(name: String)
  /// A tool completed with an error (preview: first 120 chars of the error)
  case toolFailed(name: String, preview: String)
  /// A new assistant response turn has started (initial turn or after tool results)
  case assistantTurnStarted
  /// The agent loop finished normally
  case finished
  /// The agent loop hit the maximum iteration count
  case maxIterationsReached(Int)
  /// Rate limit encountered; waiting before retry
  case rateLimitWaiting(seconds: Int, attempt: Int, maxAttempts: Int)
  /// A fatal error occurred (network failure, invalid API key, etc.)
  case error(String)
}
