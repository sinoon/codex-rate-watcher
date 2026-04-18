import XCTest
@testable import CodexRateKit

final class UsageEstimatorTests: XCTestCase {

  // MARK: - Helpers

  private func makeSample(
    at date: Date,
    primary: Double,
    primaryResetAt: TimeInterval,
    secondary: Double? = nil,
    secondaryResetAt: TimeInterval? = nil,
    review: Double = 0,
    reviewResetAt: TimeInterval = 0
  ) -> UsageSample {
    UsageSample(
      capturedAt: date,
      primaryUsedPercent: primary,
      primaryResetAt: primaryResetAt,
      secondaryUsedPercent: secondary,
      secondaryResetAt: secondaryResetAt,
      reviewUsedPercent: review,
      reviewResetAt: reviewResetAt
    )
  }

  private func makeLimitWindow(
    usedPercent: Double,
    limitWindowSeconds: Int = 18000,
    resetAfterSeconds: Int = 12345,
    resetAt: TimeInterval = 0
  ) -> LimitWindow {
    let resolvedResetAfterSeconds: Int
    if resetAt > 0, resetAfterSeconds == 12345 {
      resolvedResetAfterSeconds = max(0, Int(resetAt - Date().timeIntervalSince1970))
    } else {
      resolvedResetAfterSeconds = resetAfterSeconds
    }
    let json = """
    {"used_percent":\(usedPercent),"limit_window_seconds":\(limitWindowSeconds),"reset_after_seconds":\(resolvedResetAfterSeconds),"reset_at":\(resetAt)}
    """.data(using: .utf8)!
    return try! JSONDecoder().decode(LimitWindow.self, from: json)
  }

  // MARK: - Empty Samples

  func testEstimateWithNoSamples() {
    let window = makeLimitWindow(usedPercent: 35.0)
    let result = UsageEstimator.estimatePrimary(from: [], window: window)
    XCTAssertNil(result.timeUntilExhausted)
    XCTAssertNil(result.percentPerHour)
    XCTAssertEqual(result.statusText, "采样中")
  }

  // MARK: - Insufficient Time Delta

  func testEstimateWithInsufficientTimeDelta() {
    let now = Date()
    let resetAt: TimeInterval = now.timeIntervalSince1970 + 10000
    let window = makeLimitWindow(usedPercent: 35.0, resetAt: resetAt)

    // Two samples only 2 minutes apart (< 5 min threshold)
    let samples = [
      makeSample(at: now.addingTimeInterval(-120), primary: 30.0, primaryResetAt: resetAt),
      makeSample(at: now, primary: 35.0, primaryResetAt: resetAt),
    ]

    let result = UsageEstimator.estimatePrimary(from: samples, window: window)
    XCTAssertNil(result.timeUntilExhausted)
    XCTAssertNil(result.percentPerHour)
    XCTAssertEqual(result.statusText, "估算中")
  }

  // MARK: - Stable Burn Rate

  func testEstimateStableBurnRate() {
    let now = Date()
    let resetAt: TimeInterval = now.timeIntervalSince1970 + 10000
    let window = makeLimitWindow(usedPercent: 35.0, resetAt: resetAt)

    // Samples with very small delta (< 0.2%)
    let samples = [
      makeSample(at: now.addingTimeInterval(-600), primary: 34.9, primaryResetAt: resetAt),
      makeSample(at: now, primary: 35.0, primaryResetAt: resetAt),
    ]

    let result = UsageEstimator.estimatePrimary(from: samples, window: window)
    XCTAssertNil(result.timeUntilExhausted)
    XCTAssertEqual(result.percentPerHour, 0)
    XCTAssertEqual(result.statusText, "平稳")
  }

  // MARK: - Active Burn Rate

  func testEstimateActiveBurnRate() {
    let now = Date()
    // Reset is far in the future so the estimate won't say "won't run out before reset"
    let resetAt: TimeInterval = now.timeIntervalSince1970 + 100000

    // 10% used at T=0, 30% used at T=1h (same resetAt)
    // delta = 20% over 1h => 20%/h
    // remaining = 100 - 30 = 70%, time = 70/20 * 3600 = 12600s = 3.5h
    let samples = [
      makeSample(at: now.addingTimeInterval(-3600), primary: 10.0, primaryResetAt: resetAt),
      makeSample(at: now, primary: 30.0, primaryResetAt: resetAt),
    ]

    let window = makeLimitWindow(usedPercent: 30.0, resetAt: resetAt)
    let result = UsageEstimator.estimatePrimary(from: samples, window: window)

    XCTAssertNotNil(result.percentPerHour)
    XCTAssertEqual(result.percentPerHour!, 20.0, accuracy: 0.5)

    XCTAssertNotNil(result.timeUntilExhausted)
    XCTAssertEqual(result.timeUntilExhausted!, 12600, accuracy: 60)

    // Status text should contain rate info
    XCTAssertTrue(result.statusText.contains("20"))
    XCTAssertTrue(result.statusText.contains("%/h"))
  }

  // MARK: - Won't Run Out Before Reset

  func testEstimateWontRunOutBeforeReset() {
    let now = Date()
    // Reset in 30 minutes
    let resetAt: TimeInterval = now.timeIntervalSince1970 + 1800

    // Low burn rate: 1% over 10 minutes = 6%/h
    // remaining = 80%, time = 80/6 * 3600 = 48000s ≈ 13.3h
    // But reset is in 1800s, so won't run out
    let samples = [
      makeSample(at: now.addingTimeInterval(-600), primary: 19.0, primaryResetAt: resetAt),
      makeSample(at: now, primary: 20.0, primaryResetAt: resetAt),
    ]

    let window = makeLimitWindow(usedPercent: 20.0, resetAt: resetAt)
    let result = UsageEstimator.estimatePrimary(from: samples, window: window)

    XCTAssertNil(result.timeUntilExhausted)
    XCTAssertNotNil(result.percentPerHour)
    XCTAssertEqual(result.statusText, "充足")
  }

  // MARK: - Filter Same Window

  func testEstimateFiltersSameWindow() {
    let now = Date()
    let currentResetAt: TimeInterval = now.timeIntervalSince1970 + 10000
    let oldResetAt: TimeInterval = now.timeIntervalSince1970 - 50000  // different window

    // Old sample from different window should be filtered out
    let samples = [
      makeSample(at: now.addingTimeInterval(-7200), primary: 90.0, primaryResetAt: oldResetAt),
      makeSample(at: now.addingTimeInterval(-600), primary: 10.0, primaryResetAt: currentResetAt),
      makeSample(at: now, primary: 10.1, primaryResetAt: currentResetAt),
    ]

    let window = makeLimitWindow(usedPercent: 10.1, resetAt: currentResetAt)
    let result = UsageEstimator.estimatePrimary(from: samples, window: window)

    // Only the two current-window samples are used; delta = 0.1 < 0.2 => stable
    XCTAssertEqual(result.statusText, "平稳")
  }

  // MARK: - Secondary Window Estimation

  func testEstimateSecondary() {
    let now = Date()
    let resetAt: TimeInterval = now.timeIntervalSince1970 + 500000  // far future

    let samples = [
      makeSample(
        at: now.addingTimeInterval(-7200),
        primary: 10.0,
        primaryResetAt: 0,
        secondary: 20.0,
        secondaryResetAt: resetAt
      ),
      makeSample(
        at: now,
        primary: 30.0,
        primaryResetAt: 0,
        secondary: 30.0,
        secondaryResetAt: resetAt
      ),
    ]

    let window = makeLimitWindow(usedPercent: 30.0, resetAt: resetAt)
    let result = UsageEstimator.estimateSecondary(from: samples, window: window)

    XCTAssertNotNil(result.percentPerHour)
    // 10% over 2 hours = 5%/h
    XCTAssertEqual(result.percentPerHour!, 5.0, accuracy: 0.5)
  }

  // MARK: - Review Estimation

  func testEstimateReview() {
    let now = Date()
    let resetAt: TimeInterval = now.timeIntervalSince1970 + 500000

    let samples = [
      makeSample(
        at: now.addingTimeInterval(-3600),
        primary: 10.0,
        primaryResetAt: 0,
        review: 5.0,
        reviewResetAt: resetAt
      ),
      makeSample(
        at: now,
        primary: 20.0,
        primaryResetAt: 0,
        review: 15.0,
        reviewResetAt: resetAt
      ),
    ]

    let window = makeLimitWindow(usedPercent: 15.0, resetAt: resetAt)
    let result = UsageEstimator.estimateReview(from: samples, window: window)

    XCTAssertNotNil(result.percentPerHour)
    // 10% over 1 hour = 10%/h
    XCTAssertEqual(result.percentPerHour!, 10.0, accuracy: 0.5)
  }

  // MARK: - Samples with nil secondaryUsedPercent filtered out

  func testEstimateSecondaryFiltersNilSamples() {
    let now = Date()
    let resetAt: TimeInterval = now.timeIntervalSince1970 + 500000

    let samples = [
      // This sample has nil secondary → should be filtered out
      makeSample(
        at: now.addingTimeInterval(-7200),
        primary: 10.0,
        primaryResetAt: 0,
        secondary: nil,
        secondaryResetAt: nil
      ),
      makeSample(
        at: now,
        primary: 30.0,
        primaryResetAt: 0,
        secondary: 30.0,
        secondaryResetAt: resetAt
      ),
    ]

    let window = makeLimitWindow(usedPercent: 30.0, resetAt: resetAt)
    let result = UsageEstimator.estimateSecondary(from: samples, window: window)

    // Only one valid sample, not enough for estimation
    XCTAssertEqual(result.statusText, "估算中")
  }

  // MARK: - BurnEstimate struct

  func testBurnEstimateInit() {
    let est = BurnEstimate(timeUntilExhausted: 3600, percentPerHour: 10.0, statusText: "test")
    XCTAssertEqual(est.timeUntilExhausted, 3600)
    XCTAssertEqual(est.percentPerHour, 10.0)
    XCTAssertEqual(est.statusText, "test")
  }

  func testBurnEstimateNilValues() {
    let est = BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "no data")
    XCTAssertNil(est.timeUntilExhausted)
    XCTAssertNil(est.percentPerHour)
    XCTAssertEqual(est.statusText, "no data")
  }
}
