import XCTest
@testable import CodexRateKit

final class TokenCostPricingTests: XCTestCase {

  func testNormalizeCodexModelStripsOpenAIPrefix() {
    XCTAssertEqual(
      TokenCostPricing.normalizeCodexModel("openai/gpt-5"),
      "gpt-5"
    )
  }

  func testNormalizeCodexModelCollapsesDatedSuffix() {
    XCTAssertEqual(
      TokenCostPricing.normalizeCodexModel("gpt-5-2026-03-01"),
      "gpt-5"
    )
  }

  func testNormalizeCodexModelCollapsesGPT55DatedSuffix() {
    XCTAssertEqual(
      TokenCostPricing.normalizeCodexModel("openai/gpt-5.5-2026-04-24"),
      "gpt-5.5"
    )
  }

  func testCostUsesCachedRateForCachedInputTokens() {
    let cost = TokenCostPricing.codexCostUSD(
      model: "gpt-5",
      inputTokens: 1_000_000,
      cachedInputTokens: 400_000,
      outputTokens: 10_000
    )

    XCTAssertNotNil(cost)
    XCTAssertEqual(cost!, 0.90, accuracy: 0.0001)
  }

  func testCostSupportsGPT55Pricing() {
    let cost = TokenCostPricing.codexCostUSD(
      model: "gpt-5.5",
      inputTokens: 1_000_000,
      cachedInputTokens: 400_000,
      outputTokens: 10_000
    )

    XCTAssertNotNil(cost)
    XCTAssertEqual(cost!, 3.5, accuracy: 0.0001)
  }

  func testUnknownModelHasNoCost() {
    XCTAssertNil(
      TokenCostPricing.codexCostUSD(
        model: "gpt-unknown",
        inputTokens: 1000,
        cachedInputTokens: 0,
        outputTokens: 100
      )
    )
  }

  func testNormalizeClaudeModelStripsAnthropicPrefixAndDatedSuffix() {
    XCTAssertEqual(
      TokenCostPricing.normalizeClaudeModel("anthropic/claude-sonnet-4-6-20260101"),
      "claude-sonnet-4-6"
    )
    XCTAssertEqual(
      TokenCostPricing.normalizeClaudeModel("claude-opus-4-7"),
      "claude-opus-4-7"
    )
  }

  func testCostBillsClaudeCacheReadAndCreationSeparately() {
    // 1M total prompt = 100k cache read + 200k cache creation + 700k uncached.
    // Sonnet rates per 1M: input $3 / cache read $0.30 / cache creation $3.75 / output $15.
    // Expected: 0.7 * 3 + 0.1 * 0.30 + 0.2 * 3.75 + 0.05 * 15 = 2.1 + 0.03 + 0.75 + 0.75 = 3.63.
    let cost = TokenCostPricing.costUSD(
      model: "claude-sonnet-4-6",
      inputTokens: 1_000_000,
      cacheReadTokens: 100_000,
      cacheCreationTokens: 200_000,
      outputTokens: 50_000
    )

    XCTAssertNotNil(cost)
    XCTAssertEqual(cost!, 3.63, accuracy: 0.0001)
  }

  func testCostUSDDispatchesToClaudePricingForVendorPrefixedNames() {
    let cost = TokenCostPricing.costUSD(
      model: "anthropic/claude-haiku-4-5-20260101",
      inputTokens: 1_000,
      cacheReadTokens: 0,
      cacheCreationTokens: 0,
      outputTokens: 1_000
    )

    XCTAssertNotNil(cost)
    // Haiku 4.5: $1 input + $5 output per 1M ⇒ 1k * 1e-6 + 1k * 5e-6 = 0.006.
    XCTAssertEqual(cost!, 0.006, accuracy: 1e-6)
  }
}
