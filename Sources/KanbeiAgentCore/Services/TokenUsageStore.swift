import Foundation
import Combine

// MARK: - トークン使用量の1回分

public struct APIUsage {
  public let inputTokens: Int
  public let outputTokens: Int

  public init(inputTokens: Int, outputTokens: Int) {
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
  }
}

// MARK: - Claude モデル別料金定義（USD per 1M tokens）

private struct ModelPricing {
  let inputPerMTok: Double
  let outputPerMTok: Double
}

private let modelPricingTable: [String: ModelPricing] = [
  "claude-opus-4-5":            ModelPricing(inputPerMTok: 15.0, outputPerMTok: 75.0),
  "claude-sonnet-4-5":          ModelPricing(inputPerMTok: 3.0,  outputPerMTok: 15.0),
  "claude-sonnet-4-6":          ModelPricing(inputPerMTok: 3.0,  outputPerMTok: 15.0),
  "claude-haiku-4-5-20251001":  ModelPricing(inputPerMTok: 0.8,  outputPerMTok: 4.0),
]

private let defaultPricing = ModelPricing(inputPerMTok: 3.0, outputPerMTok: 15.0)

// MARK: - TokenUsageStore（シングルトン）

@MainActor
public class TokenUsageStore: ObservableObject {
  public static let shared = TokenUsageStore()

  @Published public private(set) var totalInputTokens: Int
  @Published public private(set) var totalOutputTokens: Int
  @Published public private(set) var sessionInputTokens: Int = 0
  @Published public private(set) var sessionOutputTokens: Int = 0

  private let defaults = UserDefaults.standard
  private let keyInput  = "tokenUsage.totalInput"
  private let keyOutput = "tokenUsage.totalOutput"

  private init() {
    totalInputTokens  = defaults.integer(forKey: "tokenUsage.totalInput")
    totalOutputTokens = defaults.integer(forKey: "tokenUsage.totalOutput")
  }

  public func record(usage: APIUsage) {
    sessionInputTokens  += usage.inputTokens
    sessionOutputTokens += usage.outputTokens
    totalInputTokens    += usage.inputTokens
    totalOutputTokens   += usage.outputTokens
    defaults.set(totalInputTokens,  forKey: keyInput)
    defaults.set(totalOutputTokens, forKey: keyOutput)
  }

  public func sessionCostUSD(model: String) -> Double {
    cost(input: sessionInputTokens, output: sessionOutputTokens, model: model)
  }

  public func totalCostUSD(model: String) -> Double {
    cost(input: totalInputTokens, output: totalOutputTokens, model: model)
  }

  private func cost(input: Int, output: Int, model: String) -> Double {
    let pricing = modelPricingTable[model] ?? defaultPricing
    return Double(input)  / 1_000_000 * pricing.inputPerMTok
         + Double(output) / 1_000_000 * pricing.outputPerMTok
  }

  public func resetTotal() {
    totalInputTokens  = 0
    totalOutputTokens = 0
    defaults.set(0, forKey: keyInput)
    defaults.set(0, forKey: keyOutput)
  }

  public func resetSession() {
    sessionInputTokens  = 0
    sessionOutputTokens = 0
  }
}
