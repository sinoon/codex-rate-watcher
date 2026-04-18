import XCTest
@testable import CodexRateKit

final class ResetTimeFormatterTests: XCTestCase {
  func testResetLabelUsesProvidedDeviceTimeZone() throws {
    let localTimeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
    let utcTimeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = localTimeZone

    let now = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 4, day: 8, hour: 12, minute: 30))
    )
    let reset = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 4, day: 8, hour: 16, minute: 45))
    )

    let localLabel = QuotaTimeFormatter.resetLabel(
      for: reset.timeIntervalSince1970,
      now: now,
      timeZone: localTimeZone
    )
    let utcLabel = QuotaTimeFormatter.resetLabel(
      for: reset.timeIntervalSince1970,
      now: now,
      timeZone: utcTimeZone
    )

    XCTAssertEqual(localLabel, "16:45")
    XCTAssertEqual(utcLabel, "08:45")
  }

  func testResetCountdownIncludesRemainingDurationAndLocalClock() throws {
    let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone

    let now = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 4, day: 8, hour: 12, minute: 30))
    )
    let reset = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 4, day: 8, hour: 16, minute: 45))
    )

    let countdown = QuotaTimeFormatter.resetCountdownLabel(
      for: reset.timeIntervalSince1970,
      now: now,
      timeZone: timeZone
    )

    XCTAssertEqual(countdown, "16:45 重置 · 4h15m后")
  }

  func testContextualResetCountdownIncludesWindowTypeAndLocalClockHint() throws {
    let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone

    let now = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 4, day: 8, hour: 12, minute: 30))
    )
    let reset = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 4, day: 8, hour: 16, minute: 45))
    )

    let countdown = QuotaTimeFormatter.contextualResetCountdownLabel(
      context: "5h 重置",
      for: reset.timeIntervalSince1970,
      now: now,
      timeZone: timeZone
    )

    XCTAssertEqual(countdown, "5h 重置：16:45 · 4h15m后")
  }

  func testResetLabelIncludesClockTimeWhenDateIsBeyondTomorrow() throws {
    let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone

    let now = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 4, day: 18, hour: 17, minute: 17))
    )
    let reset = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 4, day: 20, hour: 20, minute: 21))
    )

    let label = QuotaTimeFormatter.resetLabel(
      for: reset.timeIntervalSince1970,
      now: now,
      timeZone: timeZone
    )

    XCTAssertEqual(label, "4/20 20:21")
  }

  func testContextualResetCountdownUsesAbsoluteTimeBeforeRelativeTime() throws {
    let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone

    let now = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 4, day: 18, hour: 17, minute: 17))
    )
    let reset = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 4, day: 20, hour: 20, minute: 21))
    )

    let countdown = QuotaTimeFormatter.contextualResetCountdownLabel(
      context: "周重置",
      for: reset.timeIntervalSince1970,
      now: now,
      timeZone: timeZone
    )

    XCTAssertEqual(countdown, "周重置：4/20 20:21 · 2天3h后")
  }
}
