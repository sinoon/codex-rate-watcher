import Foundation

public enum TokenCostPricing {
  public struct CodexPricing: Sendable {
    public let inputCostPerToken: Double
    public let outputCostPerToken: Double
    public let cacheReadInputCostPerToken: Double?
    // Per-token rate billed when fresh tokens are written to a prompt cache.
    // Codex models do not bill cache writes, so they leave this nil.
    public let cacheCreationInputCostPerToken: Double?
    public let displayLabel: String?

    public init(
      inputCostPerToken: Double,
      outputCostPerToken: Double,
      cacheReadInputCostPerToken: Double?,
      cacheCreationInputCostPerToken: Double? = nil,
      displayLabel: String? = nil
    ) {
      self.inputCostPerToken = inputCostPerToken
      self.outputCostPerToken = outputCostPerToken
      self.cacheReadInputCostPerToken = cacheReadInputCostPerToken
      self.cacheCreationInputCostPerToken = cacheCreationInputCostPerToken
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

  // Claude pricing in USD per token. Rates published per 1M tokens by Anthropic;
  // divide by 1e6 here. Cache write (creation) rates use the 5-minute ephemeral
  // tier, the default Claude Code uses.
  private static let claude: [String: CodexPricing] = [
    // Opus 4.x: input $15 / output $75 / cache write $18.75 / cache read $1.50 per 1M
    "claude-4.7-opus": CodexPricing(
      inputCostPerToken: 1.5e-5,
      outputCostPerToken: 7.5e-5,
      cacheReadInputCostPerToken: 1.5e-6,
      cacheCreationInputCostPerToken: 1.875e-5
    ),
    "claude-4.6-opus": CodexPricing(
      inputCostPerToken: 1.5e-5,
      outputCostPerToken: 7.5e-5,
      cacheReadInputCostPerToken: 1.5e-6,
      cacheCreationInputCostPerToken: 1.875e-5
    ),
    "claude-opus-4-7": CodexPricing(
      inputCostPerToken: 1.5e-5,
      outputCostPerToken: 7.5e-5,
      cacheReadInputCostPerToken: 1.5e-6,
      cacheCreationInputCostPerToken: 1.875e-5
    ),
    "claude-opus-4-6": CodexPricing(
      inputCostPerToken: 1.5e-5,
      outputCostPerToken: 7.5e-5,
      cacheReadInputCostPerToken: 1.5e-6,
      cacheCreationInputCostPerToken: 1.875e-5
    ),

    // Sonnet 4.x: input $3 / output $15 / cache write $3.75 / cache read $0.30 per 1M
    "claude-4.6-sonnet": CodexPricing(
      inputCostPerToken: 3e-6,
      outputCostPerToken: 1.5e-5,
      cacheReadInputCostPerToken: 3e-7,
      cacheCreationInputCostPerToken: 3.75e-6
    ),
    "claude-4.5-sonnet": CodexPricing(
      inputCostPerToken: 3e-6,
      outputCostPerToken: 1.5e-5,
      cacheReadInputCostPerToken: 3e-7,
      cacheCreationInputCostPerToken: 3.75e-6
    ),
    "claude-sonnet-4-6": CodexPricing(
      inputCostPerToken: 3e-6,
      outputCostPerToken: 1.5e-5,
      cacheReadInputCostPerToken: 3e-7,
      cacheCreationInputCostPerToken: 3.75e-6
    ),
    "claude-sonnet-4-5": CodexPricing(
      inputCostPerToken: 3e-6,
      outputCostPerToken: 1.5e-5,
      cacheReadInputCostPerToken: 3e-7,
      cacheCreationInputCostPerToken: 3.75e-6
    ),

    // Haiku 4.5: input $1 / output $5 / cache write $1.25 / cache read $0.10 per 1M
    "claude-4.5-haiku": CodexPricing(
      inputCostPerToken: 1e-6,
      outputCostPerToken: 5e-6,
      cacheReadInputCostPerToken: 1e-7,
      cacheCreationInputCostPerToken: 1.25e-6
    ),
    "claude-haiku-4-5": CodexPricing(
      inputCostPerToken: 1e-6,
      outputCostPerToken: 5e-6,
      cacheReadInputCostPerToken: 1e-7,
      cacheCreationInputCostPerToken: 1.25e-6
    ),
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

  // Claude session logs use names like "anthropic/claude-4.7-opus-20260416".
  // Strip the vendor prefix and any trailing -YYYYMMDD release tag, then look the
  // base name up in the rate card. Names not in the dict fall through unchanged.
  public static func normalizeClaudeModel(_ raw: String) -> String {
    var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("anthropic/") {
      trimmed = String(trimmed.dropFirst("anthropic/".count))
    }

    if claude[trimmed] != nil {
      return trimmed
    }

    if let datedSuffix = trimmed.range(of: #"-\d{8}$"#, options: .regularExpression) {
      let base = String(trimmed[..<datedSuffix.lowerBound])
      if claude[base] != nil {
        return base
      }
      trimmed = base
    }

    if let datedSuffix = trimmed.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) {
      let base = String(trimmed[..<datedSuffix.lowerBound])
      if claude[base] != nil {
        return base
      }
    }

    return trimmed
  }

  public static func codexDisplayLabel(model: String) -> String? {
    let key = normalizeCodexModel(model)
    if let label = codex[key]?.displayLabel { return label }
    let claudeKey = normalizeClaudeModel(model)
    return claude[claudeKey]?.displayLabel
  }

  public static func codexCostUSD(
    model: String,
    inputTokens: Int,
    cachedInputTokens: Int,
    outputTokens: Int
  ) -> Double? {
    costUSD(
      model: model,
      inputTokens: inputTokens,
      cacheReadTokens: cachedInputTokens,
      cacheCreationTokens: 0,
      outputTokens: outputTokens
    )
  }

  // Unified rate lookup for both Codex and Claude. `inputTokens` is the total prompt
  // size on this turn; `cacheReadTokens` and `cacheCreationTokens` are subsets of
  // it. The non-cached portion is what's left after subtracting both subsets.
  public static func costUSD(
    model: String,
    inputTokens: Int,
    cacheReadTokens: Int,
    cacheCreationTokens: Int,
    outputTokens: Int
  ) -> Double? {
    let pricing = lookupPricing(model: model)
    guard let pricing else { return nil }

    let safeInput = max(0, inputTokens)
    let safeCacheRead = min(max(0, cacheReadTokens), safeInput)
    let safeCacheCreate = min(max(0, cacheCreationTokens), max(0, safeInput - safeCacheRead))
    let nonCached = max(0, safeInput - safeCacheRead - safeCacheCreate)

    let cacheReadRate = pricing.cacheReadInputCostPerToken ?? pricing.inputCostPerToken
    let cacheCreateRate = pricing.cacheCreationInputCostPerToken ?? pricing.inputCostPerToken

    return Double(nonCached) * pricing.inputCostPerToken
      + Double(safeCacheRead) * cacheReadRate
      + Double(safeCacheCreate) * cacheCreateRate
      + Double(max(0, outputTokens)) * pricing.outputCostPerToken
  }

  private static func lookupPricing(model: String) -> CodexPricing? {
    if let codexEntry = codex[normalizeCodexModel(model)] {
      return codexEntry
    }
    if let claudeEntry = claude[normalizeClaudeModel(model)] {
      return claudeEntry
    }
    return nil
  }
}
