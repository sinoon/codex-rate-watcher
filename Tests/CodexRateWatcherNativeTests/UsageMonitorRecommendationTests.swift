import XCTest
@testable import CodexRateWatcherNative
@testable import CodexRateKit

@MainActor
final class UsageMonitorRecommendationTests: XCTestCase {
  func testStayLowRecommendationMentionsNextWaitingProfile() {
    let activeID = UUID()
    let waitingID = UUID()

    let state = UsageMonitor.State(
      snapshot: makeSnapshot(primaryUsed: 99, secondaryUsed: 90),
      profiles: [
        makeRecord(id: activeID, email: "active@example.com", usage: makeUsage(planType: "team", primaryUsed: 99, secondaryUsed: 90)),
        makeRecord(id: waitingID, email: "waiting@example.com", usage: makeUsage(planType: "plus", primaryUsed: 100, secondaryUsed: 61, limitReached: true)),
      ],
      activeProfileID: activeID,
      errorMessage: nil,
      lastUpdatedAt: Date(),
      isRefreshing: false,
      isAddingAccount: false,
      tokenCostSnapshot: nil,
      primaryEstimate: BurnEstimate(timeUntilExhausted: 60, percentPerHour: 20, statusText: "fast"),
      secondaryEstimate: BurnEstimate(timeUntilExhausted: 600, percentPerHour: 2, statusText: "steady"),
      reviewEstimate: BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "idle")
    )

    let recommendation = state.switchRecommendation

    switch recommendation.kind {
    case .stay:
      break
    default:
      XCTFail("Expected stay recommendation when current account is still the only immediately usable profile")
    }

    XCTAssertEqual(recommendation.headline, Copy.recStayLow)
    XCTAssertTrue(recommendation.detail.contains("waiting"))
    XCTAssertTrue(recommendation.detail.contains("周 39%"))
  }

  func testRecommendationTrustsLiveSnapshotWhenCurrentProfileHasStaleValidationError() {
    let activeID = UUID()

    let state = UsageMonitor.State(
      snapshot: makeSnapshot(primaryUsed: 30, secondaryUsed: 7),
      profiles: [
        makeRecord(
          id: activeID,
          email: "active@example.com",
          usage: makeUsage(planType: "pro", primaryUsed: 30, secondaryUsed: 7),
          validationError: "cancelled"
        ),
      ],
      activeProfileID: activeID,
      errorMessage: "cancelled",
      lastUpdatedAt: Date(),
      isRefreshing: false,
      isAddingAccount: false,
      tokenCostSnapshot: nil,
      primaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 60 * 2, percentPerHour: 12, statusText: "steady"),
      secondaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 60 * 24, percentPerHour: 1, statusText: "calm"),
      reviewEstimate: BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "idle")
    )

    let recommendation = state.switchRecommendation

    XCTAssertEqual(recommendation.kind, .stay)
    XCTAssertEqual(recommendation.headline, Copy.recStay)
    XCTAssertFalse(recommendation.detail.contains(Copy.unavailable))
  }

  private func makeRecord(
    id: UUID,
    email: String,
    usage: AuthProfileUsageSummary,
    validationError: String? = nil
  ) -> AuthProfileRecord {
    AuthProfileRecord(
      id: id,
      fingerprint: id.uuidString,
      snapshotFileName: "\(id.uuidString).json",
      authMode: "chatgpt",
      accountID: "acct_\(id.uuidString.prefix(6))",
      email: email,
      createdAt: Date(),
      lastSeenAt: Date(),
      lastValidatedAt: Date(),
      latestUsage: usage,
      validationError: validationError
    )
  }

  private func makeUsage(
    planType: String,
    primaryUsed: Double,
    secondaryUsed: Double,
    limitReached: Bool = false
  ) -> AuthProfileUsageSummary {
    let json = """
    {
      "planType": "\(planType)",
      "isAllowed": true,
      "limitReached": \(limitReached),
      "primaryUsedPercent": \(primaryUsed),
      "primaryResetAt": 1900000000,
      "secondaryUsedPercent": \(secondaryUsed),
      "secondaryResetAt": 1900003600,
      "reviewUsedPercent": 0,
      "reviewResetAt": 1900007200
    }
    """

    return try! JSONDecoder().decode(AuthProfileUsageSummary.self, from: Data(json.utf8))
  }

  private func makeSnapshot(primaryUsed: Double, secondaryUsed: Double) -> UsageSnapshot {
    let json = """
    {
      "plan_type": "team",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {
          "used_percent": \(primaryUsed),
          "limit_window_seconds": 18000,
          "reset_after_seconds": 60,
          "reset_at": 1900000000
        },
        "secondary_window": {
          "used_percent": \(secondaryUsed),
          "limit_window_seconds": 604800,
          "reset_after_seconds": 3600,
          "reset_at": 1900003600
        }
      },
      "code_review_rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {
          "used_percent": 0,
          "limit_window_seconds": 604800,
          "reset_after_seconds": 604800,
          "reset_at": 1900060400
        }
      },
      "credits": {
        "has_credits": false,
        "unlimited": false
      }
    }
    """

    return try! JSONDecoder().decode(UsageSnapshot.self, from: Data(json.utf8))
  }
}
