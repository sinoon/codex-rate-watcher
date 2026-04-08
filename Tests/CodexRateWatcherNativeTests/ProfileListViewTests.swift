import XCTest
import AppKit
@testable import CodexRateWatcherNative
@testable import CodexRateKit

@MainActor
final class ProfileListViewTests: XCTestCase {
  func testRenderProfilesKeepsWaitingProfilesSwitchable() throws {
    let monitor = UsageMonitor()
    let viewController = PopoverViewController(monitor: monitor)
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    let activeID = UUID()
    let readyID = UUID()
    let waitingID = UUID()

    let state = UsageMonitor.State(
      snapshot: makeSnapshot(primaryUsed: 99, secondaryUsed: 90),
      profiles: [
        makeRecord(id: activeID, email: "active@example.com", usage: makeUsage(primaryUsed: 99, secondaryUsed: 90)),
        makeRecord(id: readyID, email: "ready@example.com", usage: makeUsage(primaryUsed: 40, secondaryUsed: 20)),
        makeRecord(id: waitingID, email: "waiting@example.com", usage: makeUsage(primaryUsed: 100, secondaryUsed: 61)),
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

    viewController.renderForTesting(state: state)
    viewController.view.layoutSubtreeIfNeeded()

    XCTAssertNotNil(findButton(" Recommend ", in: viewController.view))
    let waitButton = try XCTUnwrap(findButton(" Use ", in: viewController.view))
    XCTAssertTrue(waitButton.isEnabled)
    XCTAssertNotNil(findLabel("Other Profiles · 1 available · 1 waiting", in: viewController.view))

    let resetLabels = allTextFields(in: viewController.view)
      .map(\.stringValue)
      .filter { $0.contains("后重置") }
    XCTAssertGreaterThanOrEqual(resetLabels.count, 2)
    XCTAssertTrue(resetLabels.contains { $0.contains("5h 60%") })
    XCTAssertTrue(resetLabels.contains { $0.contains("5h耗尽") })
  }

  func testProfileRowsUseTwoLineLayoutForLongResetCopy() throws {
    let monitor = UsageMonitor()
    let viewController = PopoverViewController(monitor: monitor)
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    let activeID = UUID()
    let readyID = UUID()

    let state = UsageMonitor.State(
      snapshot: makeSnapshot(primaryUsed: 20, secondaryUsed: 30),
      profiles: [
        makeRecord(id: activeID, email: "active@example.com", usage: makeUsage(planType: "pro", primaryUsed: 20, secondaryUsed: 30)),
        makeRecord(id: readyID, email: "ready@example.com", usage: makeUsage(planType: "team", primaryUsed: 0, secondaryUsed: 43)),
      ],
      activeProfileID: activeID,
      errorMessage: nil,
      lastUpdatedAt: Date(),
      isRefreshing: false,
      isAddingAccount: false,
      tokenCostSnapshot: nil,
      primaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 60 * 2, percentPerHour: 12, statusText: "steady"),
      secondaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 60 * 10, percentPerHour: 1, statusText: "calm"),
      reviewEstimate: BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "idle")
    )

    viewController.renderForTesting(state: state)
    viewController.view.layoutSubtreeIfNeeded()

    let useButton = try XCTUnwrap(findButton(" Use ", in: viewController.view))
    let row = try XCTUnwrap(useButton.superview)
    XCTAssertGreaterThan(row.frame.height, 40)

    let labels = row.subviews.compactMap { $0 as? NSTextField }
    let nameLabel = try XCTUnwrap(labels.first { $0.stringValue == "Team · ready" })
    let usageLabel = try XCTUnwrap(labels.first { $0.stringValue.contains("后重置") })
    XCTAssertGreaterThan(nameLabel.frame.midY, usageLabel.frame.midY + 6)
  }

  func testRenderSwitchRecommendationShowsDetailText() throws {
    let monitor = UsageMonitor()
    let viewController = PopoverViewController(monitor: monitor)
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    let activeID = UUID()
    let recommendedID = UUID()

    let state = UsageMonitor.State(
      snapshot: makeSnapshot(primaryUsed: 78, secondaryUsed: 85),
      profiles: [
        makeRecord(id: activeID, email: "active@example.com", usage: makeUsage(planType: "pro", primaryUsed: 78, secondaryUsed: 85)),
        makeRecord(id: recommendedID, email: "best@example.com", usage: makeUsage(planType: "plus", primaryUsed: 10, secondaryUsed: 15)),
      ],
      activeProfileID: activeID,
      errorMessage: nil,
      lastUpdatedAt: Date(),
      isRefreshing: false,
      isAddingAccount: false,
      tokenCostSnapshot: nil,
      primaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 45, percentPerHour: 18, statusText: "steady"),
      secondaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 60 * 8, percentPerHour: 1, statusText: "calm"),
      reviewEstimate: BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "idle")
    )

    let recommendation = state.switchRecommendation
    XCTAssertEqual(recommendation.kind, .switchNow)
    XCTAssertFalse(recommendation.detail.isEmpty)

    viewController.renderForTesting(state: state)
    viewController.view.layoutSubtreeIfNeeded()

    let labels = allTextFields(in: viewController.view).map(\.stringValue)
    XCTAssertTrue(labels.contains { $0.contains(recommendation.headline) })
    XCTAssertTrue(labels.contains { $0.contains(recommendation.detail) })
  }

  func testRenderStayRecommendationRemainsVisible() throws {
    let monitor = UsageMonitor()
    let viewController = PopoverViewController(monitor: monitor)
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    let activeID = UUID()
    let backupID = UUID()

    let state = UsageMonitor.State(
      snapshot: makeSnapshot(primaryUsed: 35, secondaryUsed: 40),
      profiles: [
        makeRecord(id: activeID, email: "active@example.com", usage: makeUsage(planType: "pro", primaryUsed: 35, secondaryUsed: 40)),
        makeRecord(id: backupID, email: "backup@example.com", usage: makeUsage(planType: "team", primaryUsed: 60, secondaryUsed: 65)),
      ],
      activeProfileID: activeID,
      errorMessage: nil,
      lastUpdatedAt: Date(),
      isRefreshing: false,
      isAddingAccount: false,
      tokenCostSnapshot: nil,
      primaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 60 * 3, percentPerHour: 8, statusText: "steady"),
      secondaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 60 * 12, percentPerHour: 1, statusText: "calm"),
      reviewEstimate: BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "idle")
    )

    let recommendation = state.switchRecommendation
    XCTAssertEqual(recommendation.kind, .stay)
    XCTAssertEqual(recommendation.headline, Copy.recStay)

    viewController.renderForTesting(state: state)
    viewController.view.layoutSubtreeIfNeeded()

    let labels = allTextFields(in: viewController.view).map(\.stringValue)
    XCTAssertTrue(labels.contains { $0.contains(recommendation.headline) })
    XCTAssertTrue(labels.contains { $0.contains(recommendation.detail) })
  }

  private func allTextFields(in view: NSView) -> [NSTextField] {
    var result: [NSTextField] = []
    for subview in view.subviews {
      if let textField = subview as? NSTextField {
        result.append(textField)
      }
      result += allTextFields(in: subview)
    }
    return result
  }

  private func allButtons(in view: NSView) -> [NSButton] {
    var result: [NSButton] = []
    for subview in view.subviews {
      if let button = subview as? NSButton {
        result.append(button)
      }
      result += allButtons(in: subview)
    }
    return result
  }

  private func findLabel(_ text: String, in view: NSView) -> NSTextField? {
    allTextFields(in: view).first { $0.stringValue == text }
  }

  private func findButton(_ title: String, in view: NSView) -> NSButton? {
    allButtons(in: view).first { $0.title == title }
  }

  private func makeRecord(
    id: UUID,
    email: String,
    usage: AuthProfileUsageSummary?,
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
    planType: String = "plus",
    isAllowed: Bool = true,
    limitReached: Bool = false,
    primaryUsed: Double,
    secondaryUsed: Double?
  ) -> AuthProfileUsageSummary {
    let json: String
    if let secondaryUsed {
      json = """
      {
        "planType": "\(planType)",
        "isAllowed": \(isAllowed),
        "limitReached": \(limitReached),
        "primaryUsedPercent": \(primaryUsed),
        "primaryResetAt": 1900000000,
        "secondaryUsedPercent": \(secondaryUsed),
        "secondaryResetAt": 1900003600,
        "reviewUsedPercent": 0,
        "reviewResetAt": 1900007200
      }
      """
    } else {
      json = """
      {
        "planType": "\(planType)",
        "isAllowed": \(isAllowed),
        "limitReached": \(limitReached),
        "primaryUsedPercent": \(primaryUsed),
        "primaryResetAt": 1900000000,
        "reviewUsedPercent": 0,
        "reviewResetAt": 1900007200
      }
      """
    }

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
          "reset_after_seconds": 600,
          "reset_at": 1900000000
        },
        "secondary_window": {
          "used_percent": \(secondaryUsed),
          "limit_window_seconds": 604800,
          "reset_after_seconds": 7200,
          "reset_at": 1900007200
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
