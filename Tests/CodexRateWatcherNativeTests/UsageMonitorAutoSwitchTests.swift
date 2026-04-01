import XCTest
@testable import CodexRateWatcherNative

@MainActor
final class UsageMonitorAutoSwitchTests: XCTestCase {
  func testAutoSwitchCannotBeEnabled() {
    let monitor = UsageMonitor(clearPersistedAutoSwitchConfig: {})

    XCTAssertFalse(monitor.autoSwitchConfig.enabled)

    monitor.setAutoSwitch(enabled: true)

    XCTAssertFalse(monitor.autoSwitchConfig.enabled)
  }
}
