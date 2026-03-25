//
//  ContentView.swift
//  KanbeiAgent
//

import SwiftUI
import UniformTypeIdentifiers
import KanbeiAgentCore

struct ContentView: View {
  @AppStorage("workingDirectoryPath") private var workingDirectoryPath = ""
  @AppStorage("workspaceRootPath") private var workspaceRootPath = ""

  private var workingDirectoryURL: URL {
    workingDirectoryPath.isEmpty
      ? FileManager.default.homeDirectoryForCurrentUser
      : URL(fileURLWithPath: workingDirectoryPath)
  }

  private var workspaceRootURL: URL? {
    workspaceRootPath.isEmpty ? nil : URL(fileURLWithPath: workspaceRootPath)
  }

  var body: some View {
    ChatView(
      context: SimpleAgentContext(
        workingDirectoryURL: workingDirectoryURL,
        workspaceRoot: workspaceRootURL
      ),
      additionalSettings: { WorkspaceSettingsSections() }
    )
    .frame(minWidth: 600, minHeight: 500)
  }
}

// MARK: - Workspace Settings Sections

private struct WorkspaceSettingsSections: View {
  @AppStorage("workingDirectoryPath") private var workingDirectoryPath = ""
  @AppStorage("workspaceRootPath") private var workspaceRootPath = ""
  @State private var showingWorkingDirPicker = false
  @State private var showingWorkspaceRootPicker = false

  private var defaultWorkingDirPath: String {
    FileManager.default.homeDirectoryForCurrentUser.path
  }

  var body: some View {
    Group {
      Section {
        HStack {
          TextField(defaultWorkingDirPath, text: $workingDirectoryPath)
          Button("選択") { showingWorkingDirPicker = true }
        }
      } header: {
        Text("作業ディレクトリ")
      } footer: {
        Text("エージェントが操作するディレクトリ。空欄の場合は \(defaultWorkingDirPath) を使用します。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section {
        HStack {
          TextField("未設定", text: $workspaceRootPath)
          Button("選択") { showingWorkspaceRootPicker = true }
          if !workspaceRootPath.isEmpty {
            Button("クリア") { workspaceRootPath = "" }
              .foregroundStyle(.red)
          }
        }
      } header: {
        Text("Workspace Root")
      } footer: {
        Text("handoff.md が置かれたディレクトリ。設定するとその内容がエージェントのコンテキストに自動注入されます。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .fileImporter(isPresented: $showingWorkingDirPicker, allowedContentTypes: [.folder]) { result in
      if case .success(let url) = result { workingDirectoryPath = url.path }
    }
    .fileImporter(isPresented: $showingWorkspaceRootPicker, allowedContentTypes: [.folder]) { result in
      if case .success(let url) = result { workspaceRootPath = url.path }
    }
  }
}
