import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
  @StateObject private var viewModel = AgentViewModel()
  @State private var input = ""
  @State private var showingSettings = false
  @State private var showingDirectoryPicker = false
  @FocusState private var inputFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      // ツールバー
      HStack {
        // 作業ディレクトリ
        Button {
          showingDirectoryPicker = true
        } label: {
          Label(viewModel.workingDirectory.lastPathComponent, systemImage: "folder")
            .font(.caption)
            .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(viewModel.workingDirectory.path)

        Spacer()

        if viewModel.isRunning {
          ProgressView().controlSize(.small)
        }

        Button {
          viewModel.clearHistory()
        } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("会話をクリア")
        .disabled(viewModel.messages.isEmpty)

        Button {
          showingSettings = true
        } label: {
          Image(systemName: "gear")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(.bar)

      Divider()

      // メッセージリスト
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(viewModel.messages) { message in
              MessageRow(message: message)
                .id(message.id)
            }
            if let error = viewModel.errorMessage {
              Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .padding(.horizontal)
            }
          }
          .padding(12)
        }
        .onChange(of: viewModel.messages.count) {
          if let last = viewModel.messages.last {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
          }
        }
      }

      Divider()

      // 入力エリア
      HStack(alignment: .bottom, spacing: 8) {
        TextField("メッセージを入力…", text: $input, axis: .vertical)
          .textFieldStyle(.plain)
          .lineLimit(1...8)
          .focused($inputFocused)
          .onSubmit { sendMessage() }
          .padding(8)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

        Button {
          sendMessage()
        } label: {
          Image(systemName: "arrow.up.circle.fill")
            .font(.title2)
            .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .keyboardShortcut(.return, modifiers: .command)
      }
      .padding(12)
    }
    .sheet(isPresented: $showingSettings) {
      SettingsView()
    }
    .fileImporter(
      isPresented: $showingDirectoryPicker,
      allowedContentTypes: [.folder]
    ) { result in
      if case .success(let url) = result {
        viewModel.workingDirectory = url
      }
    }
    .onAppear { inputFocused = true }
  }

  private var canSend: Bool {
    !input.trimmingCharacters(in: .whitespaces).isEmpty && !viewModel.isRunning
  }

  private func sendMessage() {
    guard canSend else { return }
    let text = input
    input = ""
    Task { await viewModel.send(text) }
  }
}

// MARK: - メッセージ行

private struct MessageRow: View {
  let message: Message

  var body: some View {
    switch message.role {
    case .user:
      HStack {
        Spacer(minLength: 60)
        Text(message.content)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
          .textSelection(.enabled)
      }

    case .assistant:
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "sparkles")
          .foregroundStyle(.tint)
          .frame(width: 20)
        VStack(alignment: .leading, spacing: 4) {
          Text(message.content.isEmpty && message.isStreaming ? "…" : message.content)
            .textSelection(.enabled)
          if message.isStreaming && !message.content.isEmpty {
            ProgressView().controlSize(.mini)
          }
        }
        Spacer(minLength: 60)
      }

    case .tool:
      HStack(spacing: 6) {
        Image(systemName: "wrench.and.screwdriver")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(message.content)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.leading, 28)
    }
  }
}

// MARK: - 設定画面

private struct SettingsView: View {
  @AppStorage("claudeApiKey") private var claudeApiKey = ""
  @AppStorage("claudeModel") private var claudeModel = "claude-sonnet-4-6"
  @State private var inputKey = ""
  @Environment(\.dismiss) private var dismiss

  private let models: [(id: String, label: String)] = [
    ("claude-sonnet-4-6", "Claude Sonnet 4.6（推奨）"),
    ("claude-opus-4-6",   "Claude Opus 4.6（高精度）"),
    ("claude-haiku-4-5-20251001", "Claude Haiku 4.5（高速）"),
  ]

  var body: some View {
    NavigationStack {
      Form {
        Section {
          SecureField("sk-ant-...", text: $inputKey)
        } header: {
          Text("Claude API Key")
        } footer: {
          Text("Anthropic Consoleから取得してください。")
            .font(.caption)
        }

        Section {
          Picker("モデル", selection: $claudeModel) {
            ForEach(models, id: \.id) { model in
              Text(model.label).tag(model.id)
            }
          }
        } header: {
          Text("モデル")
        }
      }
      .formStyle(.grouped)
      .navigationTitle("設定")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            claudeApiKey = inputKey
            dismiss()
          }
        }
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
      }
      .onAppear { inputKey = claudeApiKey }
    }
    .frame(minWidth: 360, minHeight: 240)
  }
}
