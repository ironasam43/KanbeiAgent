//
//  AgentViewModel.swift
//  KanbeiAgentCore
//

import Foundation
import Combine
import SwiftUI

@MainActor
public class AgentViewModel: ObservableObject {
  @Published public var messages: [Message] = []
  @Published public var isRunning = false
  @Published public var errorMessage: String?
  @Published public var scrollTrigger = 0
  @Published public var workingDirectory: URL
  #if os(macOS)
  @Published public var pendingBashCommand: PendingBashCommand?
  #endif

  private let service: AgentService
  private let historyFileURL: URL

  public init(context: any KanbeiAgentContext) {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = support.appendingPathComponent("KanbeiAgent")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    self.historyFileURL = dir.appendingPathComponent("\(context.historyFileName).json")
    self.workingDirectory = context.workingDirectoryURL

    let svc = AgentService(context: context)
    self.service = svc

    #if os(macOS)
    svc.bashApprovalHandler = { [weak self] command in
      await self?.requestBashApproval(command: command) ?? false
    }
    #endif
  }

  // MARK: - macOS bash approval UI

  #if os(macOS)
  public struct PendingBashCommand: Identifiable {
    public let id = UUID()
    public let command: String
    public let continuation: CheckedContinuation<Bool, Never>
  }

  private func requestBashApproval(command: String) async -> Bool {
    await withCheckedContinuation { continuation in
      self.pendingBashCommand = PendingBashCommand(command: command, continuation: continuation)
    }
  }

  public func confirmBash(approved: Bool) {
    guard let pending = pendingBashCommand else { return }
    pendingBashCommand = nil
    pending.continuation.resume(returning: approved)
  }
  #endif

  // MARK: - Send

  public var currentTask: Task<Void, Never>?

  public func cancelGeneration() {
    currentTask?.cancel()
    currentTask = nil
  }

  @AppStorage("claudeApiKey") private var apiKey = ""
  @AppStorage("claudeModel") private var claudeModel = "claude-sonnet-4-6"

  public func send(_ userInput: String) {
    currentTask = Task { await sendWithImages(userInput, images: []) }
  }

  public func sendWithImages(_ userInput: String, images: [(base64: String, mediaType: String)]) async {
    let trimmed = userInput.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty || !images.isEmpty else { return }
    guard !apiKey.isEmpty else {
      errorMessage = String(localized: "agent.api_key_missing", bundle: .localizedModule)
      return
    }

    let displayText = images.isEmpty
      ? trimmed
      : trimmed + (trimmed.isEmpty ? "" : "\n") + "📎 \(images.count) image\(images.count == 1 ? "" : "s") attached"
    messages.append(Message(role: .user, content: displayText))

    isRunning = true
    errorMessage = nil

    var assistantIndex = messages.count  // will be set on first .assistantTurnStarted

    do {
      for try await event in service.send(trimmed, images: images, apiKey: apiKey, model: claudeModel) {
        switch event {
        case .assistantTurnStarted:
          messages.append(Message(role: .assistant, content: "", isStreaming: true))
          assistantIndex = messages.count - 1

        case .text(let chunk):
          messages[assistantIndex].content += chunk

        case .toolRunning(let name):
          let msg = String(format: String(localized: "tool.running", bundle: .localizedModule), name)
          messages.append(Message(role: .tool, content: msg))

        case .toolCompleted(let name):
          let msg = String(format: String(localized: "tool.done", bundle: .localizedModule), name)
          messages[messages.count - 1].content = msg

        case .toolFailed(let name, let preview):
          let msg = String(format: String(localized: "tool.error", bundle: .localizedModule), name, preview)
          messages[messages.count - 1].content = msg

        case .rateLimitWaiting(let seconds, let attempt, let maxAttempts):
          errorMessage = String(format: String(localized: "agent.rate_limit", bundle: .localizedModule), seconds, attempt, maxAttempts)
          scrollTrigger += 1

        case .maxIterationsReached(let max):
          messages[assistantIndex].content += String(format: String(localized: "agent.max_iterations", bundle: .localizedModule), max)

        case .error(let msg):
          errorMessage = msg
          scrollTrigger += 1

        case .finished:
          errorMessage = nil
        }
      }
    } catch is CancellationError {
      let stopped = String(localized: "agent.stopped", bundle: .localizedModule)
      if assistantIndex < messages.count {
        messages[assistantIndex].content += messages[assistantIndex].content.isEmpty
          ? stopped : "\n\n" + stopped
      }
    } catch {
      errorMessage = error.localizedDescription
      scrollTrigger += 1
    }

    for i in messages.indices where messages[i].isStreaming {
      messages[i].isStreaming = false
    }
    isRunning = false
    currentTask = nil
    scrollTrigger += 1
    saveHistory()
  }

  // MARK: - Persistence

  private struct SavedHistory: Codable {
    var messages: [Message]
    var history: [APIMessage]
    var workingDirectoryPath: String?
  }

  private func saveHistory() {
    let toSave = messages.compactMap { msg -> Message? in
      if msg.role == .tool { return nil }
      if msg.role == .assistant && msg.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
      var m = msg
      m.isStreaming = false
      return m
    }
    let saved = SavedHistory(
      messages: toSave,
      history: service.exportHistory(),
      workingDirectoryPath: workingDirectory.path
    )
    guard let data = try? JSONEncoder().encode(saved) else { return }
    try? data.write(to: historyFileURL)
  }

  public func loadHistory() {
    guard let data = try? Data(contentsOf: historyFileURL),
          let saved = try? JSONDecoder().decode(SavedHistory.self, from: data) else { return }
    messages = saved.messages
    service.importHistory(saved.history)
    if let path = saved.workingDirectoryPath {
      workingDirectory = URL(fileURLWithPath: path)
    }
  }

  public func clearHistory() {
    messages.removeAll()
    service.clearHistory()
    errorMessage = nil
    saveHistory()
  }
}
