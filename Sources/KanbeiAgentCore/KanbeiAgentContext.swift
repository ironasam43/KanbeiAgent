import Foundation

/// KanbeiAgentを利用する際に必要なコンテキスト情報を提供するプロトコル
public protocol KanbeiAgentContext {
  /// エージェントが操作する作業ディレクトリ
  var workingDirectoryURL: URL { get }
  /// 会話履歴の保存ファイル名（拡張子なし）例: "history", "issue-123"
  var historyFileName: String { get }
  /// システムプロンプトへの追加情報（Issue情報など）
  var systemPromptAddendum: String { get }
}
