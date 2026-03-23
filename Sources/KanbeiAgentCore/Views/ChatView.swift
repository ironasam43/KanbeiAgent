import SwiftUI
import UniformTypeIdentifiers
import AppKit

public struct ChatView: View {
  @StateObject private var viewModel: AgentViewModel
  @State private var input = ""

  public init(context: any KanbeiAgentContext) {
    _viewModel = StateObject(wrappedValue: AgentViewModel(context: context))
  }
  @State private var showingSettings = false
  @State private var showingDirectoryPicker = false
  @State private var showingAttachmentPicker = false
  @State private var showingScreenshotPicker = false
  @State private var attachedFiles: [(name: String, content: String)] = []
  @State private var attachedImages: [(name: String, base64: String, mediaType: String, nsImage: NSImage)] = []
  @State private var exportDocument: ChatExportDocument?
  @State private var showingExporter = false
  @FocusState private var inputFocused: Bool

  public var body: some View {
    VStack(spacing: 0) {
      // ツールバー
      HStack {
        // タイトル
        VStack(alignment: .leading, spacing: 1) {
          Text("Chat")
            .font(.headline)
            .fontWeight(.bold)
          Text("Powered by Claude")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }

        Spacer()

        // 作業ディレクトリ
        Button {
          let panel = NSOpenPanel()
          panel.canChooseFiles = false
          panel.canChooseDirectories = true
          panel.allowsMultipleSelection = false
          panel.prompt = "選択"
          if panel.runModal() == .OK, let url = panel.url {
            viewModel.workingDirectory = url
          }
        } label: {
          Label(viewModel.workingDirectory.lastPathComponent, systemImage: "folder")
            .font(.caption)
            .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Workspace")

        Spacer()

        if viewModel.isRunning {
          Button {
            viewModel.cancelGeneration()
          } label: {
            Label("停止", systemImage: "stop.circle.fill")
              .foregroundStyle(.red)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .help("生成を停止")
        }

        Button {
          exportDocument = ChatExportDocument(messages: viewModel.messages)
          showingExporter = true
        } label: {
          Image(systemName: "square.and.arrow.up")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("会話をエクスポート")
        .disabled(viewModel.messages.isEmpty)

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
        .help("設定")
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(.bar)

      Divider().overlay(Color.primary.opacity(0.3))

      // メッセージリスト
      ScrollViewReader { proxy in
        ZStack {
          Color(red: 0.93, green: 0.93, blue: 0.95)
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
              ForEach(viewModel.messages) { message in
                MessageRow(message: message)
                  .id(message.id)
              }
              // インライン sh 実行確認カード
              if let pending = viewModel.pendingBashCommand {
                BashApprovalCard(command: pending.command) { approved in
                  viewModel.confirmBash(approved: approved)
                }
                .id("bashApproval")
              }
              if let error = viewModel.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                  Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                  Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                }
                .font(.callout)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.25), lineWidth: 1))
                .padding(.horizontal)
              }
            }
            .padding(12)
          }
        }
        .onChange(of: viewModel.messages.count) {
          if let last = viewModel.messages.last {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
          }
        }
        .onChange(of: viewModel.pendingBashCommand == nil) {
          if viewModel.pendingBashCommand != nil {
            withAnimation { proxy.scrollTo("bashApproval", anchor: .bottom) }
            NSSound.beep()
          }
        }
        .onChange(of: viewModel.scrollTrigger) {
          if let last = viewModel.messages.last {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
          }
        }
        .onChange(of: viewModel.isRunning) {
          if !viewModel.isRunning {
            NSSound.beep()
          }
        }
      }

      if viewModel.isRunning {
        Divider()
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("実行中…")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
      }

      Divider()

      // 添付バー（テキストファイル＋画像）
      if !attachedFiles.isEmpty || !attachedImages.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            // テキストファイルチップ
            ForEach(attachedFiles.indices, id: \.self) { idx in
              HStack(spacing: 4) {
                Image(systemName: "doc.text")
                  .font(.caption2)
                Text(attachedFiles[idx].name)
                  .font(.caption2)
                  .lineLimit(1)
                Button {
                  attachedFiles.remove(at: idx)
                } label: {
                  Image(systemName: "xmark")
                    .font(.caption2)
                }
                .buttonStyle(.plain)
              }
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(.quaternary, in: Capsule())
            }
            // 画像サムネイル
            ForEach(attachedImages.indices, id: \.self) { idx in
              ZStack(alignment: .topTrailing) {
                Image(nsImage: attachedImages[idx].nsImage)
                  .resizable()
                  .scaledToFill()
                  .frame(width: 48, height: 48)
                  .clipShape(RoundedRectangle(cornerRadius: 6))
                Button {
                  attachedImages.remove(at: idx)
                } label: {
                  Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .background(Color.black.opacity(0.5), in: Circle())
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
              }
            }
          }
          .padding(.horizontal, 12)
          .padding(.top, 6)
        }
      }

      // 入力エリア
      HStack(alignment: .center, spacing: 6) {
        // ＋メニュー（ファイル添付 / スクリーンショット）
        Menu {
          Button {
            showingAttachmentPicker = true
          } label: {
            Label("ファイル・画像を添付", systemImage: "paperclip")
          }

          Divider()

          Button {
            showingScreenshotPicker = true
          } label: {
            Label("スクリーンショットを送信", systemImage: "camera.viewfinder")
          }
        } label: {
          Image(systemName: "plus.circle.fill")
            .font(.title2)
            .foregroundStyle(Color.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("ファイル・画像を添付")
        .popover(isPresented: $showingScreenshotPicker, arrowEdge: .bottom) {
          ScreenshotPickerView { windowID in
            showingScreenshotPicker = false
            captureAndAttach(windowID: windowID)
          }
        }

        TextField("メッセージを入力…", text: $input, axis: .vertical)
          .textFieldStyle(.plain)
          .lineLimit(1...8)
          .focused($inputFocused)
          .padding(8)
          .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red, lineWidth: 1))

        // よく使う指示
        QuickPromptsButton { selected in
          input = input.isEmpty ? selected : input + "\n" + selected
          inputFocused = true
        }

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
        .help("送信 (⌘Return)")
      }
      .padding(12)
      .background(.bar)
    }
    .sheet(isPresented: $showingSettings) {
      KanbeiSettingsView()
    }
    .fileImporter(
      isPresented: $showingAttachmentPicker,
      allowedContentTypes: [
        .text, .plainText, .sourceCode, .json, .xml, .yaml, .data,
        .image, .png, .jpeg, .gif, .webP, .bmp, .tiff
      ],
      allowsMultipleSelection: true
    ) { result in
      if case .success(let urls) = result {
        for url in urls {
          guard url.startAccessingSecurityScopedResource() else { continue }
          defer { url.stopAccessingSecurityScopedResource() }
          let ext = url.pathExtension.lowercased()
          let imageExts = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "tif", "heic"]
          if imageExts.contains(ext) {
            // 画像として処理
            if let data = try? Data(contentsOf: url),
               let nsImage = NSImage(data: data) {
              let mediaType: String
              switch ext {
              case "jpg", "jpeg": mediaType = "image/jpeg"
              case "gif":         mediaType = "image/gif"
              case "webp":        mediaType = "image/webp"
              default:            mediaType = "image/png"
              }
              // 長辺1568px以下にリサイズしてbase64化（Claude推奨サイズ）
              let resized = nsImage.resizedIfNeeded(maxDimension: 1568)
              let targetType: NSBitmapImageRep.FileType = (mediaType == "image/jpeg") ? .jpeg : .png
              if let rep = resized.representations.first as? NSBitmapImageRep,
                 let imgData = rep.representation(using: targetType, properties: [:]) {
                attachedImages.append((
                  name: url.lastPathComponent,
                  base64: imgData.base64EncodedString(),
                  mediaType: mediaType,
                  nsImage: resized
                ))
              } else if let tiff = resized.tiffRepresentation,
                        let bmpRep = NSBitmapImageRep(data: tiff),
                        let imgData = bmpRep.representation(using: targetType, properties: [:]) {
                attachedImages.append((
                  name: url.lastPathComponent,
                  base64: imgData.base64EncodedString(),
                  mediaType: mediaType,
                  nsImage: resized
                ))
              }
            }
          } else {
            // テキストファイルとして処理
            if let text = try? String(contentsOf: url, encoding: .utf8) {
              attachedFiles.append((name: url.lastPathComponent, content: text))
            } else if let text = try? String(contentsOf: url, encoding: .shiftJIS) {
              attachedFiles.append((name: url.lastPathComponent, content: text))
            }
          }
        }
      }
    }
    .fileExporter(
      isPresented: $showingExporter,
      document: exportDocument,
      contentType: .plainText,
      defaultFilename: "chat-export"
    ) { _ in
      exportDocument = nil
    }
    .onAppear {
      viewModel.loadHistory()
      // loadHistory 後に末尾までスクロール
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        viewModel.scrollTrigger += 1
      }
      inputFocused = true
    }
  }

  // MARK: - スクリーンショット

  struct WindowInfo {
    let windowID: Int
    let title: String
    let appIcon: NSImage?
  }

  private func onScreenWindows() -> [WindowInfo] {
    let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
    guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
    else { return [] }

    return list.compactMap { win -> WindowInfo? in
      guard
        let layer  = win["kCGWindowLayer"] as? Int, layer == 0,
        let winId  = win["kCGWindowNumber"] as? Int,
        let owner  = win["kCGWindowOwnerName"] as? String,
        !owner.isEmpty
      else { return nil }

      let name = win["kCGWindowName"] as? String ?? ""
      let title = name.isEmpty ? owner : "\(owner)  —  \(name)"



      let icon = NSWorkspace.shared.runningApplications
        .first { $0.localizedName == owner }?
        .icon

      return WindowInfo(windowID: winId, title: title, appIcon: icon)
    }
  }

  private func captureAndAttach(windowID: Int) {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("devdeck_cap_\(windowID).png")
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    proc.arguments = ["-l\(windowID)", "-x", tmp.path]
    try? proc.run()
    proc.waitUntilExit()

    guard let data = try? Data(contentsOf: tmp),
          let nsImage = NSImage(data: data)
    else { return }
    try? FileManager.default.removeItem(at: tmp)

    // 長辺 1568px にリサイズして添付
    let resized = nsImage.resizedIfNeeded(maxDimension: 1568)
    guard let tiff = resized.tiffRepresentation,
          let rep  = NSBitmapImageRep(data: tiff),
          let png  = rep.representation(using: .png, properties: [:])
    else { return }

    attachedImages.append((
      name: "screenshot.png",
      base64: png.base64EncodedString(),
      mediaType: "image/png",
      nsImage: resized
    ))
  }

  private var canSend: Bool {
    (!input.trimmingCharacters(in: .whitespaces).isEmpty || !attachedFiles.isEmpty || !attachedImages.isEmpty)
      && !viewModel.isRunning
  }

  private func sendMessage() {
    guard canSend else { return }
    var text = input.trimmingCharacters(in: .whitespaces)
    let files = attachedFiles
    let images = attachedImages
    input = ""
    attachedFiles = []
    attachedImages = []

    // テキストファイルをメッセージ末尾に追記
    if !files.isEmpty {
      let attachmentBlock = files.map { file in
        "\n\n--- 添付ファイル: \(file.name) ---\n\(file.content)\n--- ここまで: \(file.name) ---"
      }.joined()
      text += attachmentBlock
    }

    let imagePayloads = images.map { (base64: $0.base64, mediaType: $0.mediaType) }
    viewModel.currentTask = Task { await viewModel.sendWithImages(text, images: imagePayloads) }
  }
}

// MARK: - エクスポートドキュメント

struct ChatExportDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.plainText] }

  var text: String

  init(messages: [Message]) {
    let dateFormatter = ISO8601DateFormatter()
    let lines = messages.map { msg -> String in
      switch msg.role {
      case .user:      return "【ユーザー】\n\(msg.content)"
      case .assistant: return "【アシスタント】\n\(msg.content)"
      case .tool:      return "【ツール】\(msg.content)"
      }
    }
    text = "# KanbeiAgent チャットエクスポート\n"
          + "出力日時: \(dateFormatter.string(from: Date()))\n\n"
          + lines.joined(separator: "\n\n---\n\n")
  }

  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents,
          let str = String(data: data, encoding: .utf8) else {
      throw CocoaError(.fileReadCorruptFile)
    }
    text = str
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    let data = Data(text.utf8)
    return FileWrapper(regularFileWithContents: data)
  }
}

// MARK: - Markdownレンダラー

private struct MarkdownBodyView: View {
  let text: String

  // コードブロックとそれ以外を分割したセグメント
  private enum Segment {
    case prose(String)
    case code(lang: String, body: String)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
        switch seg {
        case .code(let lang, let body):
          VStack(alignment: .leading, spacing: 0) {
            if !lang.isEmpty {
              Text(lang)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 6)
            }
            Text(body)
              .font(.system(size: 12, design: .monospaced))
              .textSelection(.enabled)
              .padding(.horizontal, 10)
              .padding(.vertical, lang.isEmpty ? 8 : 4)
              .padding(.bottom, 6)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color(NSColor.textBackgroundColor).opacity(0.7),
                      in: RoundedRectangle(cornerRadius: 8))
          .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color.primary.opacity(0.1), lineWidth: 1))

        case .prose(let chunk):
          ProseView(text: chunk)
        }
      }
    }
    .textSelection(.enabled)
  }

  private var segments: [Segment] {
    var result: [Segment] = []
    var remaining = text
    let pattern = "```([^\\n]*?)\\n([\\s\\S]*?)```"
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return [.prose(text)]
    }
    while !remaining.isEmpty {
      let range = NSRange(remaining.startIndex..., in: remaining)
      if let match = regex.firstMatch(in: remaining, range: range),
         let fullRange = Range(match.range, in: remaining) {
        // コードブロック前のテキスト
        let before = String(remaining[remaining.startIndex..<fullRange.lowerBound])
        if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          result.append(.prose(before))
        }
        let lang = match.range(at: 1).location != NSNotFound
          ? (Range(match.range(at: 1), in: remaining).map { String(remaining[$0]) } ?? "")
          : ""
        let body = match.range(at: 2).location != NSNotFound
          ? (Range(match.range(at: 2), in: remaining).map { String(remaining[$0]) } ?? "")
          : ""
        result.append(.code(lang: lang.trimmingCharacters(in: .whitespaces),
                            body: body.trimmingCharacters(in: .newlines)))
        remaining = String(remaining[fullRange.upperBound...])
      } else {
        if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          result.append(.prose(remaining))
        }
        break
      }
    }
    return result
  }
}

// インラインマークダウン（見出し・箇条書き・太字・斜体・インラインコード）
private struct ProseView: View {
  let text: String

  // ブロック単位のセグメント
  private enum Block: Identifiable {
    case line(Int, String)          // offset, raw
    case table(Int, [[String]])     // offset, rows (separator行は除去済み)
    var id: Int {
      switch self { case .line(let o, _): return o; case .table(let o, _): return o }
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(blocks) { block in
        switch block {
        case .line(_, let raw):
          lineView(raw)
        case .table(_, let rows):
          TableView(rows: rows)
        }
      }
    }
  }

  // 連続する | 行をまとめてテーブルブロックに変換
  private var blocks: [Block] {
    let rawLines = text.components(separatedBy: "\n")
    var result: [Block] = []
    var i = 0
    while i < rawLines.count {
      let line = rawLines[i]
      if isTableRow(line) {
        var tableLines: [String] = []
        while i < rawLines.count && isTableRow(rawLines[i]) {
          tableLines.append(rawLines[i])
          i += 1
        }
        // セパレーター行（|---|---| 形式）を除去
        let rows = tableLines
          .filter { !$0.replacingOccurrences(of: "|", with: "")
                        .replacingOccurrences(of: "-", with: "")
                        .replacingOccurrences(of: ":", with: "")
                        .trimmingCharacters(in: .whitespaces).isEmpty }
          .map { parseCells($0) }
        result.append(.table(result.count, rows))
      } else {
        result.append(.line(result.count, line))
        i += 1
      }
    }
    return result
  }

  private func isTableRow(_ s: String) -> Bool {
    let t = s.trimmingCharacters(in: .whitespaces)
    return t.hasPrefix("|") && t.hasSuffix("|") && t.count > 2
  }

  private func parseCells(_ s: String) -> [String] {
    var t = s.trimmingCharacters(in: .whitespaces)
    if t.hasPrefix("|") { t = String(t.dropFirst()) }
    if t.hasSuffix("|") { t = String(t.dropLast()) }
    return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
  }

  @ViewBuilder
  private func lineView(_ raw: String) -> some View {
    let line = raw
    if line.hasPrefix("### ") {
      inlineText(String(line.dropFirst(4))).font(.subheadline).bold()
    } else if line.hasPrefix("## ") {
      inlineText(String(line.dropFirst(3))).font(.headline)
    } else if line.hasPrefix("# ") {
      inlineText(String(line.dropFirst(2))).font(.title3).bold()
    } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text("•"); inlineText(String(line.dropFirst(2)))
      }
    } else if let rest = numberedListRest(line) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(numberedListPrefix(line) + ".").monospacedDigit()
        inlineText(rest)
      }
    } else if line.hasPrefix("> ") {
      inlineText(String(line.dropFirst(2)))
        .foregroundStyle(.secondary)
        .padding(.leading, 10)
        .overlay(Rectangle().frame(width: 3).foregroundStyle(.secondary.opacity(0.5)),
                 alignment: .leading)
    } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
      Spacer().frame(height: 4)
    } else {
      inlineText(line)
    }
  }

  private func numberedListRest(_ s: String) -> String? {
    guard let dot = s.firstIndex(of: "."),
          Int(s[s.startIndex..<dot]) != nil,
          s.index(after: dot) < s.endIndex,
          s[s.index(after: dot)] == " "
    else { return nil }
    return String(s[s.index(dot, offsetBy: 2)...])
  }
  private func numberedListPrefix(_ s: String) -> String {
    guard let dot = s.firstIndex(of: ".") else { return "" }
    return String(s[s.startIndex..<dot])
  }

  func inlineText(_ s: String) -> Text {
    var result = Text("")
    var remaining = s
    let patterns: [(String, (String) -> Text)] = [
      ("\\*\\*(.+?)\\*\\*", { Text($0).bold() }),
      ("\\*(.+?)\\*",       { Text($0).italic() }),
      ("`(.+?)`",           { Text($0).font(.system(size: 12, design: .monospaced)) }),
    ]
    let combined = patterns.map { $0.0 }.joined(separator: "|")
    guard let regex = try? NSRegularExpression(pattern: combined) else { return Text(s) }
    while !remaining.isEmpty {
      let nsRange = NSRange(remaining.startIndex..., in: remaining)
      guard let match = regex.firstMatch(in: remaining, range: nsRange),
            let fullRange = Range(match.range, in: remaining) else {
        result = result + Text(remaining); break
      }
      let before = String(remaining[remaining.startIndex..<fullRange.lowerBound])
      if !before.isEmpty { result = result + Text(before) }
      var matched = false
      for (idx, (_, transform)) in patterns.enumerated() {
        if match.range(at: idx + 1).location != NSNotFound,
           let r = Range(match.range(at: idx + 1), in: remaining) {
          result = result + transform(String(remaining[r])); matched = true; break
        }
      }
      if !matched { result = result + Text(String(remaining[fullRange])) }
      remaining = String(remaining[fullRange.upperBound...])
    }
    return result
  }
}

// テーブルビュー
private struct TableView: View {
  let rows: [[String]]

  var body: some View {
    let colCount = rows.map(\.count).max() ?? 1
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, cells in
        HStack(spacing: 0) {
          ForEach(0..<colCount, id: \.self) { col in
            let text = col < cells.count ? cells[col] : ""
            let prose = ProseView(text: text)
            Group {
              if rowIdx == 0 {
                prose.inlineText(text).bold()
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(.horizontal, 10)
                  .padding(.vertical, 6)
                  .background(Color.primary.opacity(0.07))
              } else {
                prose.inlineText(text)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(.horizontal, 10)
                  .padding(.vertical, 5)
                  .background(rowIdx % 2 == 0 ? Color.primary.opacity(0.03) : Color.clear)
              }
            }
            if col < colCount - 1 {
              Divider()
            }
          }
        }
        Divider()
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15), lineWidth: 1))
  }
}

// MARK: - スクリーンショット選択ポップオーバー

private struct ScreenshotPickerView: View {
  let onSelect: (Int) -> Void

  struct WinItem: Identifiable {
    let id: Int          // windowID
    let title: String
    let appName: String
    let appIcon: NSImage
  }

  @State private var items: [WinItem] = []

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("キャプチャするウィンドウを選択")
        .font(.headline)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)

      Divider()

      if items.isEmpty {
        Text("ウィンドウが見つかりません")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 80)
          .multilineTextAlignment(.center)
      } else {
        ScrollView {
          VStack(spacing: 4) {
            ForEach(items) { item in
              Button {
                onSelect(item.id)
              } label: {
                HStack(spacing: 10) {
                  Image(nsImage: item.appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)

                  VStack(alignment: .leading, spacing: 1) {
                    Text(item.appName)
                      .font(.body)
                      .lineLimit(1)

                    if item.title != item.appName {
                      Text(item.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                  }

                  Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
                .background(Color.primary.opacity(0.0001)) // ホバー領域確保
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.vertical, 6)
        }
      }
    }
    .frame(width: 280, height: 320)
    .onAppear { loadItems() }
  }

  private func loadItems() {
    let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
    guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
    else { return }

    let runningApps = NSWorkspace.shared.runningApplications

    var seen = Set<Int>()   // 同一アプリを1エントリに集約
    items = list.compactMap { win -> WinItem? in
      guard
        let layer = win["kCGWindowLayer"] as? Int, layer == 0,
        let winId = win["kCGWindowNumber"] as? Int,
        let owner = win["kCGWindowOwnerName"] as? String,
        !owner.isEmpty
      else { return nil }

      // 同一アプリの複数ウィンドウは最初の1件のみ
      let pid = win["kCGWindowOwnerPID"] as? Int ?? 0
      guard !seen.contains(pid) else { return nil }
      seen.insert(pid)

      let name  = win["kCGWindowName"] as? String ?? ""
      let icon     = runningApps.first { Int($0.processIdentifier) == pid }?.icon
      let fallback = NSWorkspace.shared.icon(forFile: "/Applications")
      return WinItem(id: winId, title: name.isEmpty ? owner : name,
                     appName: owner, appIcon: icon ?? fallback)

    }
  }
}

// MARK: - sh 実行確認カード（インライン）

private struct BashApprovalCard: View {
  let command: String
  let onDecide: (Bool) -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "terminal")
        .foregroundStyle(.orange)
        .frame(width: 20)

      VStack(alignment: .leading, spacing: 8) {
        Text("以下のコマンドを実行しますか？")
          .font(.subheadline)
          .foregroundStyle(.primary)

        Text(command)
          .font(.system(.caption, design: .monospaced))
          .padding(8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
          .textSelection(.enabled)

        HStack(spacing: 8) {
          Button {
            onDecide(true)
          } label: {
            Label("実行", systemImage: "checkmark")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .tint(.orange)
          .controlSize(.small)
          .keyboardShortcut(.return, modifiers: [])

          Button {
            onDecide(false)
          } label: {
            Label("キャンセル", systemImage: "xmark")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
      }

      Spacer(minLength: 60)
    }
    .padding(12)
    .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.orange.opacity(0.3), lineWidth: 1))
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
          if message.isStreaming && message.content.isEmpty {
            Text("…").foregroundStyle(.secondary)
          } else {
            MarkdownBodyView(text: message.content)
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

private struct KanbeiSettingsView: View {
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

// MARK: - よく使う指示

private let quickPromptsKey = "QuickPrompts"
private let defaultQuickPrompts: [String] = [
  "このIssueの実装方針を提案して",
  "コードレビューしてください",
  "テストケースを考えて",
  "バグの原因を調査して",
  "リファクタリング案を出して",
]

private struct QuickPromptsButton: View {
  let onSelect: (String) -> Void
  @State private var showingPopover = false

  var body: some View {
    Button {
      showingPopover = true
    } label: {
      Image(systemName: "chevron.up.circle")
        .font(.title2)
        .foregroundStyle(Color.secondary)
    }
    .buttonStyle(.plain)
    .help("よく使う指示")
    .popover(isPresented: $showingPopover, arrowEdge: .top) {
      QuickPromptsPopover { selected in
        showingPopover = false
        onSelect(selected)
      } onDismiss: {
        showingPopover = false
      }
    }
  }
}

private struct QuickPromptsPopover: View {
  let onSelect: (String) -> Void
  let onDismiss: () -> Void

  @AppStorage(quickPromptsKey) private var storedJSON: String = ""
  @State private var showingEdit = false

  private var prompts: [String] {
    guard !storedJSON.isEmpty,
          let data = storedJSON.data(using: .utf8),
          let arr = try? JSONDecoder().decode([String].self, from: data)
    else { return defaultQuickPrompts }
    return arr
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("よく使う指示")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 12)
          .padding(.top, 10)
          .padding(.bottom, 6)
        Spacer()
        Button {
          showingEdit = true
        } label: {
          Image(systemName: "pencil")
            .font(.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.trailing, 12)
        .padding(.top, 10)
      }

      Divider()

      if prompts.isEmpty {
        Text("指示が登録されていません")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(12)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(prompts, id: \.self) { prompt in
              Button {
                onSelect(prompt)
              } label: {
                Text(prompt)
                  .font(.body)
                  .foregroundStyle(.primary)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(.horizontal, 12)
                  .padding(.vertical, 8)
                  .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .background(Color.primary.opacity(0.001))

              Divider().padding(.leading, 12)
            }
          }
        }
        .frame(maxHeight: 280)
      }
    }
    .frame(width: 280)
    .sheet(isPresented: $showingEdit) {
      QuickPromptsEditSheet()
    }
  }
}

private struct QuickPromptsEditSheet: View {
  @Environment(\.dismiss) private var dismiss
  @AppStorage(quickPromptsKey) private var storedJSON: String = ""
  @State private var prompts: [String] = []
  @State private var newPrompt: String = ""
  @FocusState private var newFieldFocused: Bool

  private func loadPrompts() {
    guard !storedJSON.isEmpty,
          let data = storedJSON.data(using: .utf8),
          let arr = try? JSONDecoder().decode([String].self, from: data)
    else { prompts = defaultQuickPrompts; return }
    prompts = arr
  }

  private func savePrompts() {
    if let data = try? JSONEncoder().encode(prompts),
       let json = String(data: data, encoding: .utf8) {
      storedJSON = json
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      // ヘッダー
      HStack {
        Text("よく使う指示を編集")
          .font(.headline)
        Spacer()
        Button("完了") { savePrompts(); dismiss() }
          .keyboardShortcut(.return, modifiers: .command)
      }
      .padding()

      Divider()

      // リスト
      List {
        ForEach($prompts, id: \.self) { $prompt in
          TextField("指示を入力", text: $prompt)
            .textFieldStyle(.plain)
        }
        .onMove { from, to in
          prompts.move(fromOffsets: from, toOffset: to)
        }
        .onDelete { offsets in
          prompts.remove(atOffsets: offsets)
        }
      }
      .listStyle(.inset)

      Divider()

      // 新規追加
      HStack(spacing: 8) {
        TextField("新しい指示を追加…", text: $newPrompt)
          .textFieldStyle(.roundedBorder)
          .focused($newFieldFocused)
          .onSubmit { addPrompt() }
        Button("追加") { addPrompt() }
          .disabled(newPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
      }
      .padding()
    }
    .frame(minWidth: 400, minHeight: 360)
    .onAppear { loadPrompts() }
  }

  private func addPrompt() {
    let trimmed = newPrompt.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    prompts.append(trimmed)
    newPrompt = ""
    newFieldFocused = true
  }
}

// MARK: - NSImage リサイズ拡張

private extension NSImage {
  /// 長辺が maxDimension を超える場合、アスペクト比を保って縮小する
  func resizedIfNeeded(maxDimension: CGFloat) -> NSImage {
    let w = size.width
    let h = size.height
    let longer = max(w, h)
    guard longer > maxDimension else { return self }
    let scale = maxDimension / longer
    let newSize = NSSize(width: w * scale, height: h * scale)
    let result = NSImage(size: newSize)
    result.lockFocus()
    self.draw(in: NSRect(origin: .zero, size: newSize),
              from: NSRect(origin: .zero, size: size),
              operation: .copy, fraction: 1.0)
    result.unlockFocus()
    return result
  }
}
