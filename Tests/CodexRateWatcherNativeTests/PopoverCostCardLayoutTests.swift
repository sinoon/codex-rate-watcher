import XCTest
@testable import CodexRateWatcherNative

final class PopoverCostCardLayoutTests: XCTestCase {
  func testCostTokenMetricUsesReadableTokensSuffix() {
    XCTAssertEqual(Copy.costTokenMetric("147.2M"), "147.2M tokens")
  }

  func testCostMetricRowDoesNotForceEqualWidths() throws {
    let testsDirectory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
    let repositoryRoot = testsDirectory
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let popoverURL = repositoryRoot
      .appendingPathComponent("Sources/CodexRateWatcherNative/PopoverViewController.swift")

    let source = try String(contentsOf: popoverURL, encoding: .utf8)

    XCTAssertFalse(source.contains("metricsStack.distribution = .fillEqually"))
  }
}
