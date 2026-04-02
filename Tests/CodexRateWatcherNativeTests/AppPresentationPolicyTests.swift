import XCTest
import AppKit
@testable import CodexRateWatcherNative

final class AppPresentationPolicyTests: XCTestCase {
  func testDashboardKeepsMenuBarAppsInAccessoryMode() {
    XCTAssertEqual(
      AppPresentationPolicy.activationPolicyForDashboard(windowMode: false),
      .accessory
    )
  }

  func testDashboardKeepsDebugWindowModeRegular() {
    XCTAssertEqual(
      AppPresentationPolicy.activationPolicyForDashboard(windowMode: true),
      .regular
    )
  }
}
