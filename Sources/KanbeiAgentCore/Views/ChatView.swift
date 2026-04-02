//
//  ChatView.swift
//  KanbeiAgentCore
//

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

public struct ChatView: View {
  @StateObject private var viewModel: AgentViewModel
  @State private var input = ""
  private let additionalSettingsContent: AnyView?
  private let title: String?
  private let folderPickerEnabled: Bool
  private let initialSystemContext: String?

  public init(context: any KanbeiAgentContext) {
    _viewModel = StateObject(wrappedValue: AgentViewModel(context: context))
    self.additionalSettingsContent = nil
    self.title = nil
    self.folderPickerEnabled = true
    self.initialSystemContext = nil
  }

  /// - Parameters:
  ///   - context: エージェントコンテキスト
  ///   - storageURL: 履歴 JSON の保存先 URL（nil = App Support デフォルト）
  ///   - title: ツールバータイトル（nil = ローカライズデフォルト）
  ///   - folderPickerEnabled: フォルダ選択ボタンを表示するか（macOS のみ）
  ///   - systemContext: 動的なシステムコンテキスト文字列
  public init(
    context: any KanbeiAgentContext,
    storageURL: URL? = nil,
    title: String? = nil,
    folderPickerEnabled: Bool = true,
    systemContext: String? = nil
  ) {
    _viewModel = StateObject(wrappedValue: AgentViewModel(context: context, storageURL: storageURL))
    self.additionalSettingsContent = nil
    self.title = title
    self.folderPickerEnabled = folderPickerEnabled
    self.initialSystemContext = systemContext
  }

  public init<Extra: View>(
    context: any KanbeiAgentContext,
    @ViewBuilder additionalSettings: @escaping () -> Extra
  ) {
    _viewModel = StateObject(wrappedValue: AgentViewModel(context: context))
    self.additionalSettingsContent = AnyView(additionalSettings())
    self.title = nil
    self.folderPickerEnabled = true
    self.initialSystemContext = nil
  }
  @State private var showingSettings = false
  @State private var showingAttachmentPicker = false
  @State private var attachedFiles: [(name: String, content: String)] = []
  #if os(macOS)
  @State private var showingDirectoryPicker = false
  @State private var showingScreenshotPicker = false
  @State private var attachedImages: [(name: String, base64: String, mediaType: String, nsImage: NSImage)] = []
  #else
  @State private var attachedImages: [(name: String, base64: String, mediaType: String, uiImage: UIImage)] = []
  #endif
  @State private var exportDocument: ChatExportDocument?
  @State private var showingExporter = false
  @FocusState private var inputFocused: Bool

  public var body: some View {
    VStack(spacing: 0) {
      toolbarView
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)

      Divider().overlay(Color.primary.opacity(0.3))

      messageListView

      if viewModel.isRunning {
        Divider()
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text("chat.running", bundle: .localizedModule)
            .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.bar)
      }

      Divider()

      inputAreaView
    }
    .sheet(isPresented: $showingSettings) {
      KanbeiSettingsView(additionalContent: additionalSettingsContent)
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
            // Process as image
            let mediaType: String
            switch ext {
            case "jpg", "jpeg": mediaType = "image/jpeg"
            case "gif":         mediaType = "image/gif"
            case "webp":        mediaType = "image/webp"
            default:            mediaType = "image/png"
            }
            #if os(macOS)
            if let data = try? Data(contentsOf: url),
               let nsImage = NSImage(data: data) {
              let resized = nsImage.resizedIfNeeded(maxDimension: 1568)
              let targetType: NSBitmapImageRep.FileType = (mediaType == "image/jpeg") ? .jpeg : .png
              if let rep = resized.representations.first as? NSBitmapImageRep,
                 let imgData = rep.representation(using: targetType, properties: [:]) {
                attachedImages.append((name: url.lastPathComponent, base64: imgData.base64EncodedString(), mediaType: mediaType, nsImage: resized))
              } else if let tiff = resized.tiffRepresentation,
                        let bmpRep = NSBitmapImageRep(data: tiff),
                        let imgData = bmpRep.representation(using: targetType, properties: [:]) {
                attachedImages.append((name: url.lastPathComponent, base64: imgData.base64EncodedString(), mediaType: mediaType, nsImage: resized))
              }
            }
            #else
            if let data = try? Data(contentsOf: url),
               let uiImage = UIImage(data: data) {
              let resized = uiImage.resizedIfNeeded(maxDimension: 1568)
              let imgData = (mediaType == "image/jpeg")
                ? resized.jpegData(compressionQuality: 0.9)
                : resized.pngData()
              if let imgData {
                attachedImages.append((name: url.lastPathComponent, base64: imgData.base64EncodedString(), mediaType: mediaType, uiImage: resized))
              }
            }
            #endif
          } else {
            // Process as text file
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
      viewModel.systemContext = initialSystemContext
      viewModel.loadHistory()
      // Scroll to end after loadHistory
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        viewModel.scrollTrigger += 1
      }
      inputFocused = true
    }
    .onChange(of: initialSystemContext) { _, new in
      viewModel.systemContext = new
    }
  }

  // MARK: - Screenshot (macOS only)

  #if os(macOS)
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

    // Resize to 1568px on longest side before attaching
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
  #endif

  @ViewBuilder
  private var messageListView: some View {
    ScrollViewReader { proxy in
      ZStack {
        Color(red: 0.93, green: 0.93, blue: 0.95)
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(viewModel.messages) { message in
              MessageRow(message: message)
                .id(message.id)
            }
            #if os(macOS)
            if let pending = viewModel.pendingBashCommand {
              BashApprovalCard(command: pending.command) { approved in
                viewModel.confirmBash(approved: approved)
              }
              .id("bashApproval")
            }
            #endif
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
      #if os(macOS)
      .onChange(of: viewModel.pendingBashCommand == nil) {
        if viewModel.pendingBashCommand != nil {
          withAnimation { proxy.scrollTo("bashApproval", anchor: .bottom) }
          NSSound.beep()
        }
      }
      .onChange(of: viewModel.isRunning) {
        if !viewModel.isRunning { NSSound.beep() }
      }
      #endif
      .onChange(of: viewModel.scrollTrigger) {
        if let last = viewModel.messages.last {
          withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        }
      }
    }
  }

  @ViewBuilder
  private var inputAreaView: some View {
    VStack(spacing: 0) {
      if !attachedFiles.isEmpty || !attachedImages.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            ForEach(attachedFiles.indices, id: \.self) { idx in
              HStack(spacing: 4) {
                Image(systemName: "doc.text").font(.caption2)
                Text(attachedFiles[idx].name).font(.caption2).lineLimit(1)
                Button { attachedFiles.remove(at: idx) } label: {
                  Image(systemName: "xmark").font(.caption2)
                }
                .buttonStyle(.plain)
              }
              .padding(.horizontal, 8).padding(.vertical, 4)
              .background(.quaternary, in: Capsule())
            }
            ForEach(attachedImages.indices, id: \.self) { idx in
              ZStack(alignment: .topTrailing) {
                #if os(macOS)
                Image(nsImage: attachedImages[idx].nsImage)
                  .resizable().scaledToFill()
                  .frame(width: 48, height: 48)
                  .clipShape(RoundedRectangle(cornerRadius: 6))
                #else
                Image(uiImage: attachedImages[idx].uiImage)
                  .resizable().scaledToFill()
                  .frame(width: 48, height: 48)
                  .clipShape(RoundedRectangle(cornerRadius: 6))
                #endif
                Button { attachedImages.remove(at: idx) } label: {
                  Image(systemName: "xmark.circle.fill")
                    .font(.caption).foregroundStyle(.white)
                    .background(Color.black.opacity(0.5), in: Circle())
                }
                .buttonStyle(.plain).offset(x: 4, y: -4)
              }
            }
          }
          .padding(.horizontal, 12).padding(.top, 6)
        }
      }

      HStack(alignment: .center, spacing: 6) {
        TokenArcButton {
          viewModel.clearHistory()
          TokenUsageStore.shared.resetSession()
        }

        Menu {
          Button {
            showingAttachmentPicker = true
          } label: {
            Label(String(localized: "chat.attach.file", bundle: .localizedModule), systemImage: "paperclip")
          }
          #if os(macOS)
          if !AgentTools.isSandboxed {
            Divider()
            Button {
              showingScreenshotPicker = true
            } label: {
              Label(String(localized: "chat.attach.screenshot", bundle: .localizedModule), systemImage: "camera.viewfinder")
            }
          }
          #endif
        } label: {
          Image(systemName: "plus.circle.fill")
            .font(.title2).foregroundStyle(Color.secondary)
        }
        .menuStyle(.borderlessButton).fixedSize()
        .nativeTooltip(String(localized: "chat.attach.help", bundle: .localizedModule))
        #if os(macOS)
        .popover(isPresented: $showingScreenshotPicker, arrowEdge: .bottom) {
          ScreenshotPickerView { windowID in
            showingScreenshotPicker = false
            captureAndAttach(windowID: windowID)
          }
        }
        #endif

        TextField(String(localized: "chat.input.placeholder", bundle: .localizedModule), text: $input, axis: .vertical)
          .textFieldStyle(.plain)
          .lineLimit(1...8)
          .focused($inputFocused)
          .padding(8)
          .background(Color.textInputBackground, in: RoundedRectangle(cornerRadius: 8))
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.6), lineWidth: 1))
          .onKeyPress(.return, phases: .down) { press in
            if press.modifiers.contains(.option) || press.modifiers.contains(.shift) {
              input += "\n"
              return .handled
            }
            #if os(macOS)
            if NSTextInputContext.current?.client.hasMarkedText() == true {
              return .ignored
            }
            #endif
            guard canSend, !viewModel.isRunning else { return .ignored }
            sendMessage()
            return .handled
          }

        QuickPromptsButton { selected in
          input = input.isEmpty ? selected : input + "\n" + selected
          inputFocused = true
        }

        if viewModel.isRunning {
          Button { viewModel.cancelGeneration() } label: {
            Image(systemName: "stop.circle.fill")
              .font(.title2)
              .foregroundStyle(Color.red)
          }
          .buttonStyle(.plain)
          .nativeTooltip(String(localized: "chat.stop.help", bundle: .localizedModule))
        } else {
          Button { sendMessage() } label: {
            Image(systemName: "arrow.up.circle.fill")
              .font(.title2)
              .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
          }
          .buttonStyle(.plain).disabled(!canSend)
          .nativeTooltip(String(localized: "chat.send.help", bundle: .localizedModule))
        }
      }
      .padding(12).background(.bar)
    }
  }

  @ViewBuilder
  private var toolbarView: some View {
    HStack {
      VStack(alignment: .leading, spacing: 1) {
        Text(title ?? String(localized: "chat.title", bundle: .localizedModule))
          .font(.headline).fontWeight(.bold)
        Text("chat.subtitle", bundle: .localizedModule)
          .font(.caption2).foregroundStyle(.secondary)
      }
      Spacer()
      #if os(macOS)
      if folderPickerEnabled {
        Button {
          let panel = NSOpenPanel()
          panel.canChooseFiles = false
          panel.canChooseDirectories = true
          panel.allowsMultipleSelection = false
          panel.prompt = String(localized: "chat.workspace.prompt", bundle: .localizedModule)
          if panel.runModal() == .OK, let url = panel.url {
            viewModel.workingDirectory = url
          }
        } label: {
          Label(viewModel.workingDirectory.lastPathComponent, systemImage: "folder")
            .font(.caption).lineLimit(1)
        }
        .buttonStyle(.bordered).controlSize(.small)
        .nativeTooltip(String(localized: "chat.workspace.help", bundle: .localizedModule))
      }
      #endif
      Spacer()
      Button {
        exportDocument = ChatExportDocument(messages: viewModel.messages)
        showingExporter = true
      } label: { Image(systemName: "square.and.arrow.up") }
        .buttonStyle(.plain).foregroundStyle(.secondary)
        .nativeTooltip(String(localized: "chat.export.help", bundle: .localizedModule))
        .disabled(viewModel.messages.isEmpty)
      Button { viewModel.clearHistory() } label: { Image(systemName: "trash") }
        .buttonStyle(.plain).foregroundStyle(.secondary)
        .nativeTooltip(String(localized: "chat.clear.help", bundle: .localizedModule))
        .disabled(viewModel.messages.isEmpty)
      Button { showingSettings = true } label: { Image(systemName: "gear") }
        .buttonStyle(.plain).foregroundStyle(.secondary)
        .nativeTooltip(String(localized: "chat.settings.help", bundle: .localizedModule))
    }
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

    // Append text file to end of message
    if !files.isEmpty {
      let fmt = String(localized: "export.attachment", bundle: .localizedModule)
      let attachmentBlock = files.map { file in
        String(format: fmt, file.name, file.content, file.name)
      }.joined()
      text += attachmentBlock
    }

    let imagePayloads = images.map { (base64: $0.base64, mediaType: $0.mediaType) }
    viewModel.currentTask = Task { await viewModel.sendWithImages(text, images: imagePayloads) }
  }
}

// MARK: - Export document

struct ChatExportDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.plainText] }

  var text: String

  init(messages: [Message]) {
    let dateFormatter = ISO8601DateFormatter()
    let bundle = Bundle.localizedModule
    let lines = messages.map { msg -> String in
      switch msg.role {
      case .user:      return String(format: String(localized: "export.user", bundle: bundle), msg.content)
      case .assistant: return String(format: String(localized: "export.assistant", bundle: bundle), msg.content)
      case .tool:      return String(format: String(localized: "export.tool", bundle: bundle), msg.content)
      }
    }
    text = String(format: String(localized: "export.header", bundle: bundle), dateFormatter.string(from: Date()))
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

// MARK: - Markdown renderer

private struct MarkdownBodyView: View {
  let text: String

  // Segments divided into code blocks and other text
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
          .background(Color.textInputBackground.opacity(0.7),
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
        // Text before code block
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

// Inline markdown (headings, bullet lists, bold, italic, inline code)
private struct ProseView: View {
  let text: String

  // Segments by block unit
  private enum Block: Identifiable {
    case line(Int, String)          // offset, raw
    case table(Int, [[String]])     // offset, rows (separator row removed)
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

  // Convert consecutive | lines into table blocks
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
        // Remove separator row (|---|---| format)
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

// Table view
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

// MARK: - Screenshot selection popover (macOS only)

#if os(macOS)
private struct ScreenshotPickerView: View {
  let onSelect: (Int) -> Void

  struct WinItem: Identifiable {
    let id: Int          // window ID
    let title: String
    let appName: String
    let appIcon: NSImage
  }

  @State private var items: [WinItem] = []

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("screenshot.title", bundle: .localizedModule)
        .font(.headline)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)

      Divider()

      if items.isEmpty {
        Text("screenshot.empty", bundle: .localizedModule)
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
                .background(Color.primary.opacity(0.0001)) // Reserve hover area
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

    var seen = Set<Int>()   // Consolidate same app to 1 entry
    items = list.compactMap { win -> WinItem? in
      guard
        let layer = win["kCGWindowLayer"] as? Int, layer == 0,
        let winId = win["kCGWindowNumber"] as? Int,
        let owner = win["kCGWindowOwnerName"] as? String,
        !owner.isEmpty
      else { return nil }

      // Only first window for same app
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

// MARK: - Shell execution approval card (inline, macOS only)
#endif // os(macOS) - ScreenshotPickerView

// MARK: - Token Arc Button

private struct TokenArcButton: View {
  let onCompact: () -> Void
  @ObservedObject private var tokenStore = TokenUsageStore.shared
  @State private var showingConfirm = false

  private let contextWindow: Double = 200_000

  private var progress: Double {
    min(Double(tokenStore.sessionInputTokens) / contextWindow, 1.0)
  }

  private var arcColor: Color {
    switch progress {
    case ..<0.5: return .secondary
    case ..<0.8: return .yellow
    default:     return .red
    }
  }

  var body: some View {
    Button { showingConfirm = true } label: {
      ZStack {
        Circle()
          .stroke(Color.secondary.opacity(0.2), lineWidth: 2.5)
        Circle()
          .trim(from: 0, to: progress)
          .stroke(arcColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .animation(.easeInOut, value: progress)
      }
      .frame(width: 18, height: 18)
    }
    .buttonStyle(.plain)
    .nativeTooltip(String(format: String(localized: "chat.compact.tooltip", bundle: .localizedModule), tokenStore.sessionInputTokens))
    .confirmationDialog(
      String(localized: "chat.compact.confirm.title", bundle: .localizedModule),
      isPresented: $showingConfirm,
      titleVisibility: .visible
    ) {
      Button(String(localized: "chat.compact.confirm.button", bundle: .localizedModule), role: .destructive) { onCompact() }
    } message: {
      Text("chat.compact.confirm.message", bundle: .localizedModule)
    }
  }
}

#if os(macOS)
private struct BashApprovalCard: View {
  let command: String
  let onDecide: (Bool) -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "terminal")
        .foregroundStyle(.blue)
        .frame(width: 20)

      VStack(alignment: .leading, spacing: 8) {
        Text("bash.approval.title", bundle: .localizedModule)
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
            Label(String(localized: "bash.approval.approve", bundle: .localizedModule), systemImage: "checkmark")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .tint(.blue)
          .controlSize(.small)
          .keyboardShortcut(.return, modifiers: [])

          Button {
            onDecide(false)
          } label: {
            Label(String(localized: "bash.approval.deny", bundle: .localizedModule), systemImage: "xmark")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
      }

      Spacer(minLength: 60)
    }
    .padding(12)
    .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.blue.opacity(0.3), lineWidth: 1))
  }
}

#endif // os(macOS) - BashApprovalCard

// MARK: - Message row

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

// MARK: - Settings screen

private struct KanbeiSettingsView: View {
  let additionalContent: AnyView?

  init(additionalContent: AnyView? = nil) {
    self.additionalContent = additionalContent
  }

  @AppStorage("claudeApiKey") private var claudeApiKey = ""
  @AppStorage("claudeModel") private var claudeModel = "claude-sonnet-4-6"
  @State private var inputKey = ""
  @Environment(\.dismiss) private var dismiss

  private let models: [(id: String, labelKey: String)] = [
    ("claude-sonnet-4-6", "settings.model.sonnet"),
    ("claude-opus-4-6",   "settings.model.opus"),
    ("claude-haiku-4-5-20251001", "settings.model.haiku"),
  ]

  var body: some View {
    NavigationStack {
      Form {
        Section {
          HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
              .foregroundStyle(.tint)
              .font(.body)
            VStack(alignment: .leading, spacing: 4) {
              Text("settings.notice.api_key_required", bundle: .localizedModule)
                .fontWeight(.medium)
              Text("settings.notice.billing", bundle: .localizedModule)
                .foregroundStyle(.secondary)
              Link(String(localized: "settings.notice.console_link", bundle: .localizedModule),
                   destination: URL(string: "https://console.anthropic.com/")!)
            }
            .font(.callout)
          }
          .padding(.vertical, 4)
        }

        Section {
          SecureField("sk-ant-...", text: $inputKey)
        } header: {
          Text("settings.api_key.header", bundle: .localizedModule)
        } footer: {
          Text("settings.api_key.footer", bundle: .localizedModule)
            .font(.caption)
        }

        Section {
          Picker(String(localized: "settings.model.label", bundle: .localizedModule), selection: $claudeModel) {
            ForEach(models, id: \.id) { model in
              Text(Bundle.localizedModule.localizedString(forKey: model.labelKey, value: nil, table: nil)).tag(model.id)
            }
          }
        } header: {
          Text("settings.model.header", bundle: .localizedModule)
        }

        if let extra = additionalContent {
          extra
        }
      }
      .formStyle(.grouped)
      .navigationTitle(String(localized: "settings.title", bundle: .localizedModule))
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: "settings.save", bundle: .localizedModule)) {
            claudeApiKey = inputKey
            dismiss()
          }
        }
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: "settings.cancel", bundle: .localizedModule)) { dismiss() }
        }
      }
      .onAppear { inputKey = claudeApiKey }
    }
    .frame(minWidth: 360, minHeight: 300)
  }
}

// MARK: - Quick prompts

private let quickPromptsKey = "QuickPrompts"
private var defaultQuickPrompts: [String] {
  (1...5).map { Bundle.localizedModule.localizedString(forKey: "quickprompts.default.\($0)", value: nil, table: nil) }
}

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
    .nativeTooltip(String(localized: "quickprompts.help", bundle: .localizedModule))
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
        Text("quickprompts.title", bundle: .localizedModule)
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
        .padding(.top, 10)
        Button {
          onDismiss()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 12)
        .padding(.top, 10)
      }

      Divider()

      if prompts.isEmpty {
        Text("quickprompts.empty", bundle: .localizedModule)
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
      // Header
      HStack {
        Text("quickprompts.edit.title", bundle: .localizedModule)
          .font(.headline)
        Spacer()
        Button(String(localized: "quickprompts.edit.done", bundle: .localizedModule)) { savePrompts(); dismiss() }
          .keyboardShortcut(.return, modifiers: .command)
      }
      .padding()

      Divider()

      // List
      List {
        ForEach($prompts, id: \.self) { $prompt in
          TextField(String(localized: "quickprompts.edit.placeholder", bundle: .localizedModule), text: $prompt)
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

      // Add new
      HStack(spacing: 8) {
        TextField(String(localized: "quickprompts.add.placeholder", bundle: .localizedModule), text: $newPrompt)
          .textFieldStyle(.roundedBorder)
          .focused($newFieldFocused)
          .onSubmit { addPrompt() }
        Button(String(localized: "quickprompts.add.button", bundle: .localizedModule)) { addPrompt() }
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

// MARK: - Platform compatible color

private extension Color {
  static var textInputBackground: Color {
    #if os(macOS)
    Color(NSColor.textBackgroundColor)
    #else
    Color(.systemBackground)
    #endif
  }
}

// MARK: - Image resize extension

#if os(macOS)
private extension NSImage {
  /// If longest side exceeds maxDimension, shrink while maintaining aspect ratio
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
#else
private extension UIImage {
  /// If longest side exceeds maxDimension, shrink while maintaining aspect ratio
  func resizedIfNeeded(maxDimension: CGFloat) -> UIImage {
    let longer = max(size.width, size.height)
    guard longer > maxDimension else { return self }
    let scale = maxDimension / longer
    let newSize = CGSize(width: size.width * scale, height: size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: newSize)
    return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
  }
}
#endif

// MARK: - Tooltip (macOS NSView.toolTip fallback, iOS .help() fallback)

extension View {
  func nativeTooltip(_ text: String) -> some View {
    #if os(macOS)
    self.overlay(NativeTooltipView(text: text).allowsHitTesting(false))
    #else
    self.help(text)
    #endif
  }
}

#if os(macOS)
private struct NativeTooltipView: NSViewRepresentable {
  let text: String
  func makeNSView(context: Context) -> NSView {
    let v = NSView()
    v.toolTip = text
    return v
  }
  func updateNSView(_ nsView: NSView, context: Context) {
    nsView.toolTip = text
  }
}
#endif
