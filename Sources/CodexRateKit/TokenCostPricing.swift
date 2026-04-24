import Foundation

public enum TokenCostPricing {
  public struct CodexPricing: Sendable {
    public let inputCostPerToken: Double
    public let outputCostPerToken: Double
    public let cacheReadInputCostPerToken: Double?
    public let displayLabel: String?

    public init(
      inputCostPerToken: Double,
      outputCostPerToken: Double,
      cacheReadInputCostPerToken: Double?,
      displayLabel: String? = nil
    ) {
      self.inputCostPerToken = inputCostPerToken
      self.outputCostPerToken = outputCostPerToken
      self.cacheReadInputCostPerToken = cacheReadInputCostPerToken
      self.displayLabel = displayLabel
    }
  }

  private static let codex: [String: CodexPricing] = [
    "gpt-5": CodexPricing(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadInputCostPerToken: 1.25e-7),
    "gpt-5-codex": CodexPricing(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadInputCostPerToken: 1.25e-7),
    "gpt-5-mini": CodexPricing(inputCostPerToken: 2.5e-7, outputCostPerToken: 2e-6, cacheReadInputCostPerToken: 2.5e-8),
    "gpt-5-nano": CodexPricing(inputCostPerToken: 5e-8, outputCostPerToken: 4e-7, cacheReadInputCostPerToken: 5e-9),
    "gpt-5-pro": CodexPricing(inputCostPerToken: 1.5e-5, outputCostPerToken: 1.2e-4, cacheReadInputCostPerToken: nil),
    "gpt-5.1": CodexPricing(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadInputCostPerToken: 1.25e-7),
    "gpt-5.1-codex": CodexPricing(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadInputCostPerToken: 1.25e-7),
    "gpt-5.1-codex-max": CodexPricing(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadInputCostPerToken: 1.25e-7),
    "gpt-5.1-codex-mini": CodexPricing(inputCostPerToken: 2.5e-7, outputCostPerToken: 2e-6, cacheReadInputCostPerToken: 2.5e-8),
    "gpt-5.2": CodexPricing(inputCostPerToken: 1.75e-6, outputCostPerToken: 1.4e-5, cacheReadInputCostPerToken: 1.75e-7),
    "gpt-5.2-codex": CodexPricing(inputCostPerToken: 1.75e-6, outputCostPerToken: 1.4e-5, cacheReadInputCostPerToken: 1.75e-7),
    "gpt-5.2-pro": CodexPricing(inputCostPerToken: 2.1e-5, outputCostPerToken: 1.68e-4, cacheReadInputCostPerToken: nil),
    "gpt-5.3-codex": CodexPricing(inputCostPerToken: 1.75e-6, outputCostPerToken: 1.4e-5, cacheReadInputCostPerToken: 1.75e-7),
    "gpt-5.3-codex-spark": CodexPricing(inputCostPerToken: 0, outputCostPerToken: 0, cacheReadInputCostPerToken: 0, displayLabel: "Research Preview"),
    "gpt-5.4": CodexPricing(inputCostPerToken: 2.5e-6, outputCostPerToken: 1.5e-5, cacheReadInputCostPerToken: 2.5e-7),
    "gpt-5.4-mini": CodexPricing(inputCostPerToken: 7.5e-7, outputCostPerToken: 4.5e-6, cacheReadInputCostPerToken: 7.5e-8),
    "gpt-5.4-nano": CodexPricing(inputCostPerToken: 2e-7, outputCostPerToken: 1.25e-6, cacheReadInputCostPerToken: 2e-8),
    "gpt-5.4-pro": CodexPricing(inputCostPerToken: 3e-5, outputCostPerToken: 1.8e-4, cacheReadInputCostPerToken: nil),
    "gpt-5.5": CodexPricing(inputCostPerToken: 5e-6, outputCostPerToken: 3e-5, cacheReadInputCostPerToken: 5e-7),
  ]

  public static func normalizeCodexModel(_ raw: String) -> String {
    var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("openai/") {
      trimmed = String(trimmed.dropFirst("openai/".count))
    }

    if codex[trimmed] != nil {
      return trimmed
    }

    if let datedSuffix = trimmed.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) {
      let base = String(trimmed[..<datedSuffix.lowerBound])
      if codex[base] != nil {
        return base
      }
    }

    return trimmed
  }

  public static func codexDisplayLabel(model: String) -> String? {
    let key = normalizeCodexModel(model)
    return codex[key]?.displayLabel
  }

  public static func codexCostUSD(
    model: String,
    inputTokens: Int,
    cachedInputTokens: Int,
    outputTokens: Int
  ) -> Double? {
    let key = normalizeCodexModel(model)
    guard let pricing = codex[key] else { return nil }

    let cached = min(max(0, cachedInputTokens), max(0, inputTokens))
    let nonCached = max(0, inputTokens - cached)
    let cachedRate = pricing.cacheReadInputCostPerToken ?? pricing.inputCostPerToken

    return Double(nonCached) * pricing.inputCostPerToken
      + Double(cached) * cachedRate
      + Double(max(0, outputTokens)) * pricing.outputCostPerToken
  }
}
