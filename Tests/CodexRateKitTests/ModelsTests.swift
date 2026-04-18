import XCTest
@testable import CodexRateKit

final class ModelsTests: XCTestCase {

  // MARK: - Helper

  private func makeLimitWindow(
    usedPercent: Double,
    limitWindowSeconds: Int = 18000,
    resetAfterSeconds: Int = 12345,
    resetAt: TimeInterval = 0
  ) -> LimitWindow {
    let json = """
    {"used_percent":\(usedPercent),"limit_window_seconds":\(limitWindowSeconds),"reset_after_seconds":\(resetAfterSeconds),"reset_at":\(resetAt)}
    """.data(using: .utf8)!
    return try! JSONDecoder().decode(LimitWindow.self, from: json)
  }

  // MARK: - UsageSnapshot Decoding

  func testDecodeFullSnapshot() throws {
    let json = """
    {
      "plan_type": "pro",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {
          "used_percent": 35.2,
          "limit_window_seconds": 18000,
          "reset_after_seconds": 12345,
          "reset_at": 1773980000.0
        },
        "secondary_window": {
          "used_percent": 12.5,
          "limit_window_seconds": 604800,
          "reset_after_seconds": 432000,
          "reset_at": 1774400000.0
        }
      },
      "code_review_rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {
          "used_percent": 0.0,
          "limit_window_seconds": 18000,
          "reset_after_seconds": 18000,
          "reset_at": 1773990000.0
        }
      },
      "credits": {
        "has_credits": true,
        "unlimited": false
      }
    }
    """.data(using: .utf8)!

    let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: json)
    XCTAssertEqual(snapshot.planType, "pro")

    // Rate limit
    XCTAssertTrue(snapshot.rateLimit.allowed)
    XCTAssertFalse(snapshot.rateLimit.limitReached)

    // Primary window
    XCTAssertEqual(snapshot.rateLimit.primaryWindow.usedPercent, 35.2, accuracy: 0.001)
    XCTAssertEqual(snapshot.rateLimit.primaryWindow.limitWindowSeconds, 18000)
    XCTAssertEqual(snapshot.rateLimit.primaryWindow.resetAfterSeconds, 12345)
    XCTAssertEqual(snapshot.rateLimit.primaryWindow.resetAt, 1773980000.0, accuracy: 0.1)

    // Secondary window
    let secondary = try XCTUnwrap(snapshot.rateLimit.secondaryWindow)
    XCTAssertEqual(secondary.usedPercent, 12.5, accuracy: 0.001)
    XCTAssertEqual(secondary.limitWindowSeconds, 604800)
    XCTAssertEqual(secondary.resetAfterSeconds, 432000)
    XCTAssertEqual(secondary.resetAt, 1774400000.0, accuracy: 0.1)

    // Code review rate limit
    XCTAssertTrue(snapshot.codeReviewRateLimit.allowed)
    XCTAssertFalse(snapshot.codeReviewRateLimit.limitReached)
    XCTAssertEqual(snapshot.codeReviewRateLimit.primaryWindow.usedPercent, 0.0, accuracy: 0.001)
    XCTAssertNil(snapshot.codeReviewRateLimit.secondaryWindow)

    // Credits
    XCTAssertTrue(snapshot.credits.hasCredits)
    XCTAssertFalse(snapshot.credits.unlimited)
  }

  func testDecodeSnapshotWithoutSecondaryWindow() throws {
    let json = """
    {
      "plan_type": "plus",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {
          "used_percent": 50.0,
          "limit_window_seconds": 18000,
          "reset_after_seconds": 9000,
          "reset_at": 1773980000.0
        }
      },
      "code_review_rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {
          "used_percent": 0.0,
          "limit_window_seconds": 18000,
          "reset_after_seconds": 18000,
          "reset_at": 1773990000.0
        }
      },
      "credits": {
        "has_credits": true,
        "unlimited": false
      }
    }
    """.data(using: .utf8)!

    let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: json)
    XCTAssertEqual(snapshot.planType, "plus")
    XCTAssertEqual(snapshot.rateLimit.primaryWindow.usedPercent, 50.0, accuracy: 0.001)
    XCTAssertNil(snapshot.rateLimit.secondaryWindow)
  }

  func testDecodeSnapshotWithNullCodeReviewRateLimit() throws {
    let json = """
    {
      "plan_type": "team",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {
          "used_percent": 99.0,
          "limit_window_seconds": 18000,
          "reset_after_seconds": 17422,
          "reset_at": 1775205433
        },
        "secondary_window": {
          "used_percent": 12.0,
          "limit_window_seconds": 604800,
          "reset_after_seconds": 604222,
          "reset_at": 1775792233
        }
      },
      "code_review_rate_limit": null,
      "credits": {
        "has_credits": false,
        "unlimited": false
      }
    }
    """.data(using: .utf8)!

    let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: json)
    XCTAssertEqual(snapshot.planType, "team")
    XCTAssertEqual(snapshot.codeReviewRateLimit.primaryWindow.usedPercent, 0.0, accuracy: 0.001)
    XCTAssertTrue(snapshot.codeReviewRateLimit.allowed)
    XCTAssertFalse(snapshot.codeReviewRateLimit.limitReached)
    XCTAssertEqual(
      snapshot.codeReviewRateLimit.primaryWindow.resetAt,
      snapshot.rateLimit.primaryWindow.resetAt,
      accuracy: 0.1
    )
  }

  func testDecodeSnapshotWithEmptyCodeReviewRateLimit() throws {
    let json = """
    {
      "plan_type": "team",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {
          "used_percent": 42.0,
          "limit_window_seconds": 18000,
          "reset_after_seconds": 1200,
          "reset_at": 1775205433
        }
      },
      "code_review_rate_limit": {},
      "credits": {
        "has_credits": false,
        "unlimited": false
      }
    }
    """.data(using: .utf8)!

    let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: json)
    XCTAssertEqual(snapshot.codeReviewRateLimit.primaryWindow.usedPercent, 0.0, accuracy: 0.001)
    XCTAssertEqual(
      snapshot.codeReviewRateLimit.primaryWindow.limitWindowSeconds,
      snapshot.rateLimit.primaryWindow.limitWindowSeconds
    )
  }

  func testDecodeLimitWindowRepairsImplausibleFarFutureResetAt() {
    let before = Date().timeIntervalSince1970
    let window = makeLimitWindow(
      usedPercent: 10.0,
      limitWindowSeconds: 18_000,
      resetAfterSeconds: 9_000,
      resetAt: 4_102_444_800
    )
    let after = Date().timeIntervalSince1970

    XCTAssertGreaterThanOrEqual(window.resetAt, before + 8_990)
    XCTAssertLessThanOrEqual(window.resetAt, after + 9_010)
  }

  // MARK: - LimitWindow Computed Properties

  func testLimitWindowRemainingPercentNormal() {
    let window = makeLimitWindow(usedPercent: 35.2)
    XCTAssertEqual(window.remainingPercent, 64.8, accuracy: 0.001)
  }

  func testLimitWindowRemainingPercentZero() {
    let window = makeLimitWindow(usedPercent: 100.0)
    XCTAssertEqual(window.remainingPercent, 0.0, accuracy: 0.001)
  }

  func testLimitWindowRemainingPercentOverflow() {
    let window = makeLimitWindow(usedPercent: 105.0)
    XCTAssertEqual(window.remainingPercent, 0.0, accuracy: 0.001)
  }

  func testLimitWindowRemainingPercentFull() {
    let window = makeLimitWindow(usedPercent: 0.0)
    XCTAssertEqual(window.remainingPercent, 100.0, accuracy: 0.001)
  }

  func testLimitWindowUsedPercentLabel() {
    let window = makeLimitWindow(usedPercent: 35.2)
    XCTAssertEqual(window.usedPercentLabel, "35%")
  }

  func testLimitWindowUsedPercentLabelRounding() {
    let window = makeLimitWindow(usedPercent: 35.7)
    XCTAssertEqual(window.usedPercentLabel, "36%")
  }

  func testLimitWindowRemainingPercentLabel() {
    let window = makeLimitWindow(usedPercent: 35.2)
    XCTAssertEqual(window.remainingPercentLabel, "65%")
  }

  func testLimitWindowRemainingPercentLabelZero() {
    let window = makeLimitWindow(usedPercent: 100.0)
    XCTAssertEqual(window.remainingPercentLabel, "0%")
  }

  // MARK: - Blocked State Decoding

  func testDecodeBlockedState() throws {
    let json = """
    {
      "plan_type": "plus",
      "rate_limit": {
        "allowed": false,
        "limit_reached": true,
        "primary_window": {
          "used_percent": 100.0,
          "limit_window_seconds": 18000,
          "reset_after_seconds": 5000,
          "reset_at": 1773980000.0
        }
      },
      "code_review_rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {
          "used_percent": 0.0,
          "limit_window_seconds": 18000,
          "reset_after_seconds": 18000,
          "reset_at": 1773990000.0
        }
      },
      "credits": {
        "has_credits": false,
        "unlimited": false
      }
    }
    """.data(using: .utf8)!

    let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: json)
    XCTAssertFalse(snapshot.rateLimit.allowed)
    XCTAssertTrue(snapshot.rateLimit.limitReached)
    XCTAssertEqual(snapshot.rateLimit.primaryWindow.usedPercent, 100.0, accuracy: 0.001)
    XCTAssertFalse(snapshot.credits.hasCredits)
  }

  // MARK: - Credits Decoding

  func testDecodeCreditsUnlimited() throws {
    let json = """
    {"has_credits": true, "unlimited": true}
    """.data(using: .utf8)!
    let credits = try JSONDecoder().decode(Credits.self, from: json)
    XCTAssertTrue(credits.hasCredits)
    XCTAssertTrue(credits.unlimited)
  }

  func testDecodeCreditsNoCredits() throws {
    let json = """
    {"has_credits": false, "unlimited": false}
    """.data(using: .utf8)!
    let credits = try JSONDecoder().decode(Credits.self, from: json)
    XCTAssertFalse(credits.hasCredits)
    XCTAssertFalse(credits.unlimited)
  }

  // MARK: - AuthProfileUsageSummary from Snapshot

  func testAuthProfileUsageSummaryFromSnapshot() throws {
    let json = """
    {
      "plan_type": "pro",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {
          "used_percent": 35.2,
          "limit_window_seconds": 18000,
          "reset_after_seconds": 12345,
          "reset_at": 1773980000.0
        },
        "secondary_window": {
          "used_percent": 12.5,
          "limit_window_seconds": 604800,
          "reset_after_seconds": 432000,
          "reset_at": 1774400000.0
        }
      },
      "code_review_rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {
          "used_percent": 5.0,
          "limit_window_seconds": 18000,
          "reset_after_seconds": 18000,
          "reset_at": 1773990000.0
        }
      },
      "credits": {
        "has_credits": true,
        "unlimited": false
      }
    }
    """.data(using: .utf8)!

    let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: json)
    let summary = AuthProfileUsageSummary(snapshot: snapshot)

    XCTAssertEqual(summary.planType, "pro")
    XCTAssertTrue(summary.isAllowed)
    XCTAssertFalse(summary.limitReached)
    XCTAssertEqual(summary.primaryUsedPercent, 35.2, accuracy: 0.001)
    XCTAssertEqual(summary.primaryResetAt, 1773980000.0, accuracy: 0.1)

    let secUsed = try XCTUnwrap(summary.secondaryUsedPercent)
    XCTAssertEqual(secUsed, 12.5, accuracy: 0.001)
    let secReset = try XCTUnwrap(summary.secondaryResetAt)
    XCTAssertEqual(secReset, 1774400000.0, accuracy: 0.1)

    XCTAssertEqual(summary.reviewUsedPercent, 5.0, accuracy: 0.001)
    XCTAssertEqual(summary.reviewResetAt, 1773990000.0, accuracy: 0.1)
  }

  func testAuthProfileUsageSummaryFromSnapshotWithoutSecondary() throws {
    let json = """
    {
      "plan_type": "plus",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {
          "used_percent": 50.0,
          "limit_window_seconds": 18000,
          "reset_after_seconds": 9000,
          "reset_at": 1773980000.0
        }
      },
      "code_review_rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {
          "used_percent": 0.0,
          "limit_window_seconds": 18000,
          "reset_after_seconds": 18000,
          "reset_at": 1773990000.0
        }
      },
      "credits": {
        "has_credits": true,
        "unlimited": false
      }
    }
    """.data(using: .utf8)!

    let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: json)
    let summary = AuthProfileUsageSummary(snapshot: snapshot)

    XCTAssertNil(summary.secondaryUsedPercent)
    XCTAssertNil(summary.secondaryResetAt)
  }

  func testDecodeAuthProfileUsageSummaryRepairsImplausibleStoredResetTimes() throws {
    let json = """
    {
      "planType": "plus",
      "isAllowed": true,
      "limitReached": false,
      "primaryUsedPercent": 10,
      "primaryResetAt": 4102444800,
      "secondaryUsedPercent": 15,
      "secondaryResetAt": 4102444800,
      "reviewUsedPercent": 20,
      "reviewResetAt": 4102444800
    }
    """.data(using: .utf8)!

    let before = Date().timeIntervalSince1970
    let summary = try JSONDecoder().decode(AuthProfileUsageSummary.self, from: json)
    let after = Date().timeIntervalSince1970

    XCTAssertGreaterThanOrEqual(summary.primaryResetAt, before + 17_990)
    XCTAssertLessThanOrEqual(summary.primaryResetAt, after + 18_010)

    let secondaryResetAt = try XCTUnwrap(summary.secondaryResetAt)
    XCTAssertGreaterThanOrEqual(secondaryResetAt, before + 604_790)
    XCTAssertLessThanOrEqual(secondaryResetAt, after + 604_810)

    XCTAssertGreaterThanOrEqual(summary.reviewResetAt, before + 17_990)
    XCTAssertLessThanOrEqual(summary.reviewResetAt, after + 18_010)
  }

  // MARK: - AuthProfileUsageSummary Computed Properties

  func testPrimaryRemainingPercent() {
    let summary = makeSummary(primaryUsedPercent: 35.2)
    XCTAssertEqual(summary.primaryRemainingPercent, 64.8, accuracy: 0.001)
  }

  func testPrimaryRemainingPercentClamped() {
    let summary = makeSummary(primaryUsedPercent: 110.0)
    XCTAssertEqual(summary.primaryRemainingPercent, 0.0, accuracy: 0.001)
  }

  func testSecondaryRemainingPercent() {
    let summary = makeSummary(secondaryUsedPercent: 30.0)
    let secRemaining = try! XCTUnwrap(summary.secondaryRemainingPercent)
    XCTAssertEqual(secRemaining, 70.0, accuracy: 0.001)
  }

  func testSecondaryRemainingPercentNil() {
    let summary = makeSummary(secondaryUsedPercent: nil)
    XCTAssertNil(summary.secondaryRemainingPercent)
  }

  func testPlanDisplayNamePlus() {
    let summary = makeSummary(planType: "plus")
    XCTAssertEqual(summary.planDisplayName, "Plus")
  }

  func testPlanDisplayNameTeam() {
    let summary = makeSummary(planType: "team")
    XCTAssertEqual(summary.planDisplayName, "Team")
  }

  func testPlanDisplayNamePro() {
    let summary = makeSummary(planType: "pro")
    XCTAssertEqual(summary.planDisplayName, "Pro")
  }

  func testPlanDisplayNameUnknown() {
    let summary = makeSummary(planType: "enterprise")
    XCTAssertEqual(summary.planDisplayName, "Enterprise")
  }

  func testIsBlockedWhenNotAllowed() {
    let summary = makeSummary(isAllowed: false)
    XCTAssertTrue(summary.isBlocked)
  }

  func testIsBlockedWhenLimitReached() {
    let summary = makeSummary(limitReached: true)
    XCTAssertTrue(summary.isBlocked)
  }

  func testIsBlockedWhenPrimaryExhausted() {
    let summary = makeSummary(primaryUsedPercent: 100.0)
    XCTAssertTrue(summary.isBlocked)
    XCTAssertTrue(summary.isPrimaryExhausted)
  }

  func testIsBlockedWhenWeeklyExhausted() {
    let summary = makeSummary(secondaryUsedPercent: 100.0)
    XCTAssertTrue(summary.isBlocked)
    XCTAssertTrue(summary.isWeeklyExhausted)
  }

  func testIsNotBlockedNormal() {
    let summary = makeSummary(primaryUsedPercent: 50.0, secondaryUsedPercent: 30.0)
    XCTAssertFalse(summary.isBlocked)
  }

  func testIsRunningLowPrimary() {
    let summary = makeSummary(primaryUsedPercent: 90.0)
    XCTAssertTrue(summary.isRunningLow)
  }

  func testIsRunningLowSecondary() {
    let summary = makeSummary(primaryUsedPercent: 50.0, secondaryUsedPercent: 90.0)
    XCTAssertTrue(summary.isRunningLow)
  }

  func testIsNotRunningLow() {
    let summary = makeSummary(primaryUsedPercent: 50.0, secondaryUsedPercent: 50.0)
    XCTAssertFalse(summary.isRunningLow)
  }

  func testPrimaryRemainingPercentLabel() {
    let summary = makeSummary(primaryUsedPercent: 35.2)
    XCTAssertEqual(summary.primaryRemainingPercentLabel, "65%")
  }

  func testSecondaryRemainingPercentLabel() {
    let summary = makeSummary(secondaryUsedPercent: 12.5)
    XCTAssertEqual(summary.secondaryRemainingPercentLabel, "88%")
  }

  func testSecondaryRemainingPercentLabelNil() {
    let summary = makeSummary(secondaryUsedPercent: nil)
    XCTAssertNil(summary.secondaryRemainingPercentLabel)
  }

  func testEffectiveAvailablePercentNormal() {
    let summary = makeSummary(primaryUsedPercent: 40.0, secondaryUsedPercent: 30.0)
    XCTAssertEqual(summary.effectiveAvailablePercent, 60.0, accuracy: 0.001)
  }

  func testEffectiveAvailablePercentBlocked() {
    let summary = makeSummary(primaryUsedPercent: 100.0)
    XCTAssertEqual(summary.effectiveAvailablePercent, 0.0, accuracy: 0.001)
  }

  func testEffectiveRemainingPercent() {
    let summary = makeSummary(primaryUsedPercent: 40.0, secondaryUsedPercent: 30.0)
    XCTAssertEqual(summary.effectiveRemainingPercent, 60.0, accuracy: 0.001)
  }

  func testEffectiveRemainingPercentNoSecondary() {
    let summary = makeSummary(primaryUsedPercent: 40.0, secondaryUsedPercent: nil)
    XCTAssertEqual(summary.effectiveRemainingPercent, 60.0, accuracy: 0.001)
  }

  func testUsageSummaryTextWithSecondary() {
    let summary = makeSummary(primaryUsedPercent: 35.2, secondaryUsedPercent: 12.5)
    let text = summary.usageSummaryText
    XCTAssertTrue(text.contains("5h 65%"))
    XCTAssertTrue(text.contains("周 88%"))
  }

  func testUsageSummaryTextWithoutSecondary() {
    let summary = makeSummary(primaryUsedPercent: 35.2, secondaryUsedPercent: nil)
    let text = summary.usageSummaryText
    XCTAssertTrue(text.contains("5h 65%"))
    XCTAssertTrue(text.contains("周 --"))
  }

  func testBlockingLabelWeeklyExhausted() {
    // secondaryResetAt is a past timestamp so nextResetLabel returns nil,
    // but blockingLabel still includes the weekly exhaustion message
    let summary = makeSummary(secondaryUsedPercent: 100.0, secondaryResetAt: 0)
    let label = summary.blockingLabel
    XCTAssertNotNil(label)
    XCTAssertTrue(label!.contains("周额度"))
  }

  func testBlockingLabelPrimaryExhausted() {
    let summary = makeSummary(primaryUsedPercent: 100.0, primaryResetAt: 0)
    let label = summary.blockingLabel
    XCTAssertNotNil(label)
    XCTAssertTrue(label!.contains("5h"))
  }

  func testBlockingLabelPrimaryExhaustedIncludesWeeklyRemainingWhenAvailable() {
    let summary = makeSummary(
      primaryUsedPercent: 100.0,
      primaryResetAt: 1_900_000_000,
      secondaryUsedPercent: 61.0,
      secondaryResetAt: 1_900_500_000
    )

    let label = try! XCTUnwrap(summary.blockingLabel)

    XCTAssertTrue(label.contains("5h耗尽"))
    XCTAssertTrue(label.contains("周 39%"))
  }

  func testBlockingLabelNotAllowed() {
    let summary = makeSummary(isAllowed: false)
    XCTAssertEqual(summary.blockingLabel, "不可用")
  }

  func testBlockingLabelNilWhenNormal() {
    let summary = makeSummary(primaryUsedPercent: 50.0, secondaryUsedPercent: 30.0)
    XCTAssertNil(summary.blockingLabel)
  }

  func testSwitchSummaryTextPrimaryExhaustedIncludesWeeklyRemainingWhenAvailable() {
    let summary = makeSummary(
      primaryUsedPercent: 100.0,
      primaryResetAt: 1_900_000_000,
      secondaryUsedPercent: 61.0,
      secondaryResetAt: 1_900_500_000
    )

    XCTAssertTrue(summary.switchSummaryText.contains("5h耗尽"))
    XCTAssertTrue(summary.switchSummaryText.contains("周 39%"))
    XCTAssertTrue(summary.switchSummaryText.contains("5h 重置"))
    XCTAssertTrue(summary.switchSummaryText.contains("周重置"))
  }

  func testProfileListSummaryTextUsesWeeklyResetContextWhenWeeklyBlocked() {
    let summary = makeSummary(
      primaryUsedPercent: 22.0,
      primaryResetAt: 1_900_000_000,
      secondaryUsedPercent: 100.0,
      secondaryResetAt: 1_900_500_000
    )

    XCTAssertTrue(summary.profileListSummaryText.contains("周额度耗尽"))
    XCTAssertTrue(summary.profileListSummaryText.contains("5h 重置"))
    XCTAssertTrue(summary.profileListSummaryText.contains("周重置"))
    XCTAssertTrue(summary.profileListSummaryText.contains("\n"))
  }

  // MARK: - AuthProfileUsageSummary Codable Round-trip

  func testAuthProfileUsageSummaryCodableRoundTrip() throws {
    let summary = makeSummary(
      planType: "pro",
      primaryUsedPercent: 35.2,
      primaryResetAt: 1773980000.0,
      secondaryUsedPercent: 12.5,
      secondaryResetAt: 1774400000.0,
      reviewUsedPercent: 5.0,
      reviewResetAt: 1773990000.0
    )

    let data = try JSONEncoder().encode(summary)
    let decoded = try JSONDecoder().decode(AuthProfileUsageSummary.self, from: data)

    XCTAssertEqual(decoded.planType, summary.planType)
    XCTAssertEqual(decoded.isAllowed, summary.isAllowed)
    XCTAssertEqual(decoded.limitReached, summary.limitReached)
    XCTAssertEqual(decoded.primaryUsedPercent, summary.primaryUsedPercent, accuracy: 0.001)
    XCTAssertEqual(decoded.primaryResetAt, summary.primaryResetAt, accuracy: 0.1)
    XCTAssertEqual(decoded.secondaryUsedPercent, summary.secondaryUsedPercent)
    XCTAssertEqual(decoded.secondaryResetAt, summary.secondaryResetAt)
    XCTAssertEqual(decoded.reviewUsedPercent, summary.reviewUsedPercent, accuracy: 0.001)
    XCTAssertEqual(decoded.reviewResetAt, summary.reviewResetAt, accuracy: 0.1)
  }

  // MARK: - AuthProfileRecord

  func testAuthProfileRecordIsValid() {
    let record = makeRecord(latestUsage: makeSummary(), validationError: nil)
    XCTAssertTrue(record.isValid)
  }

  func testAuthProfileRecordIsInvalidWithError() {
    let record = makeRecord(latestUsage: makeSummary(), validationError: "402 Payment Required")
    XCTAssertFalse(record.isValid)
  }

  func testAuthProfileRecordIsInvalidWithoutUsage() {
    let record = makeRecord(latestUsage: nil, validationError: nil)
    XCTAssertFalse(record.isValid)
  }

  func testAuthProfileRecordIsSubscriptionFailed() {
    let record = makeRecord(validationError: "402 Payment Required")
    XCTAssertTrue(record.isSubscriptionFailed)
  }

  func testAuthProfileRecordAccountIdentifierEmail() {
    let record = makeRecord(email: "sinoon1218@gmail.com")
    XCTAssertEqual(record.accountIdentifier, "sinoon1218")
  }

  func testAuthProfileRecordAccountIdentifierAccountID() {
    let record = makeRecord(email: nil, accountID: "acct_12345678")
    XCTAssertEqual(record.accountIdentifier, "5678")
  }

  func testAuthProfileRecordAccountIdentifierFallback() {
    let record = makeRecord(email: nil, accountID: nil)
    XCTAssertEqual(record.accountIdentifier, "????")
  }

  func testAuthProfileRecordPlanBadge() {
    let record = makeRecord(latestUsage: makeSummary(planType: "team"))
    XCTAssertEqual(record.planBadge, "Team")
  }

  func testAuthProfileRecordPlanBadgeNoUsage() {
    let record = makeRecord(latestUsage: nil)
    XCTAssertEqual(record.planBadge, "—")
  }

  func testAuthProfileRecordDisplayName() {
    let record = makeRecord(email: "testuser@example.com", latestUsage: makeSummary(planType: "plus"))
    XCTAssertEqual(record.displayName, "Plus · testuser")
  }

  func testAuthProfileRecordStatusTextNormal() {
    let record = makeRecord(latestUsage: makeSummary(primaryUsedPercent: 50.0))
    XCTAssertEqual(record.statusText, "可用")
  }

  func testAuthProfileRecordStatusTextRunningLow() {
    let record = makeRecord(latestUsage: makeSummary(primaryUsedPercent: 90.0))
    XCTAssertEqual(record.statusText, "即将耗尽")
  }

  func testAuthProfileRecordSwitchStateReady() {
    let record = makeRecord(latestUsage: makeSummary(primaryUsedPercent: 40.0, secondaryUsedPercent: 20.0))
    XCTAssertEqual(record.switchState, .ready)
  }

  func testAuthProfileRecordSwitchStateWaitingForResetWhenPrimaryExhausted() {
    let record = makeRecord(latestUsage: makeSummary(primaryUsedPercent: 100.0, secondaryUsedPercent: 61.0))
    XCTAssertEqual(record.switchState, .waitingForReset)
  }

  func testAuthProfileRecordSwitchStateUnavailableWhenValidationFails() {
    let record = makeRecord(
      latestUsage: makeSummary(primaryUsedPercent: 20.0, secondaryUsedPercent: 10.0),
      validationError: "401"
    )
    XCTAssertEqual(record.switchState, .unavailable)
  }

  func testAuthProfileRecordStatusTextValidating() {
    let record = makeRecord(latestUsage: nil, validationError: nil)
    XCTAssertEqual(record.statusText, "校验中")
  }

  func testAuthProfileRecordStatusTextError() {
    let record = makeRecord(latestUsage: nil, validationError: "Token expired")
    XCTAssertEqual(record.statusText, "Token expired")
  }

  // MARK: - Helper to build AuthProfileUsageSummary

  private func makeSummary(
    planType: String = "pro",
    isAllowed: Bool = true,
    limitReached: Bool = false,
    primaryUsedPercent: Double = 30.0,
    primaryResetAt: TimeInterval = 1773980000.0,
    secondaryUsedPercent: Double? = 10.0,
    secondaryResetAt: TimeInterval? = 1774400000.0,
    reviewUsedPercent: Double = 0.0,
    reviewResetAt: TimeInterval = 1773990000.0
  ) -> AuthProfileUsageSummary {
    let json: String
    if let secUsed = secondaryUsedPercent, let secReset = secondaryResetAt {
      json = """
      {
        "planType": "\(planType)",
        "isAllowed": \(isAllowed),
        "limitReached": \(limitReached),
        "primaryUsedPercent": \(primaryUsedPercent),
        "primaryResetAt": \(primaryResetAt),
        "secondaryUsedPercent": \(secUsed),
        "secondaryResetAt": \(secReset),
        "reviewUsedPercent": \(reviewUsedPercent),
        "reviewResetAt": \(reviewResetAt)
      }
      """
    } else {
      json = """
      {
        "planType": "\(planType)",
        "isAllowed": \(isAllowed),
        "limitReached": \(limitReached),
        "primaryUsedPercent": \(primaryUsedPercent),
        "primaryResetAt": \(primaryResetAt),
        "reviewUsedPercent": \(reviewUsedPercent),
        "reviewResetAt": \(reviewResetAt)
      }
      """
    }
    return try! JSONDecoder().decode(AuthProfileUsageSummary.self, from: json.data(using: .utf8)!)
  }

  // MARK: - Helper to build AuthProfileRecord

  private func makeRecord(
    email: String? = "test@example.com",
    accountID: String? = "acct_12345678",
    latestUsage: AuthProfileUsageSummary? = nil,
    validationError: String? = nil
  ) -> AuthProfileRecord {
    AuthProfileRecord(
      id: UUID(),
      fingerprint: "abc123",
      snapshotFileName: "snapshot.json",
      authMode: "browser",
      accountID: accountID,
      email: email,
      createdAt: Date(),
      lastSeenAt: Date(),
      lastValidatedAt: Date(),
      latestUsage: latestUsage,
      validationError: validationError
    )
  }
}
