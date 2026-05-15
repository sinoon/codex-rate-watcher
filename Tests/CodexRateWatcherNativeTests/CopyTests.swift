import XCTest
@testable import CodexRateWatcherNative

final class CopyTests: XCTestCase {
  func testQuotaBurnIncludesResetCountdownForFutureReset() throws {
    let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone

    let now = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 4, day: 18, hour: 17, minute: 17))
    )
    let reset = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 4, day: 20, hour: 20, minute: 21))
    )

    let label = Copy.quotaBurn(
      timeLeft: 12 * 3600 + 32 * 60,
      resetAt: reset.timeIntervalSince1970,
      now: now,
      timeZone: timeZone
    )

    XCTAssertEqual(label, "≈12h32m · 4/20 20:21 重置 · 2天3h后")
  }

  func testQuotaBurnWithoutEstimateStillIncludesResetCountdown() throws {
    let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone

    let now = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 4, day: 18, hour: 17, minute: 17))
    )
    let reset = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 4, day: 20, hour: 20, minute: 21))
    )

    let label = Copy.quotaBurn(
      timeLeft: nil,
      resetAt: reset.timeIntervalSince1970,
      now: now,
      timeZone: timeZone
    )

    XCTAssertEqual(label, "4/20 20:21 重置 · 2天3h后")
  }

  func testQuotaExhaustedIncludesResetCountdown() throws {
    let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone

    let now = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 4, day: 18, hour: 17, minute: 17))
    )
    let reset = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 4, day: 20, hour: 20, minute: 21))
    )

    let label = Copy.quotaExhausted(
      resetAt: reset.timeIntervalSince1970,
      now: now,
      timeZone: timeZone
    )

    XCTAssertEqual(label, "已耗尽 · 4/20 20:21 重置 · 2天3h后")
  }
}
