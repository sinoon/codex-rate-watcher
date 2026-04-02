import XCTest
import AppKit
@testable import CodexRateWatcherNative
@testable import CodexRateKit

@MainActor
final class ProfileListViewTests: XCTestCase {
  func testRenderProfilesDistinguishesReadyAndWaitingRows() throws {
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
    let waitButton = try XCTUnwrap(findButton(" Wait ", in: viewController.view))
    XCTAssertFalse(waitButton.isEnabled)
    XCTAssertNotNil(findLabel("Other Profiles · 1 available · 1 waiting", in: viewController.view))
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
