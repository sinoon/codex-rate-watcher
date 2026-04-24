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
}
