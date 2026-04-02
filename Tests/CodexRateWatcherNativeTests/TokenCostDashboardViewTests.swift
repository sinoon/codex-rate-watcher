import XCTest
import AppKit
@testable import CodexRateWatcherNative
@testable import CodexRateKit

@MainActor
final class TokenCostDashboardViewTests: XCTestCase {
  func testDashboardEmptyStateShowsLocalLogGuidance() {
    let viewController = TokenCostDashboardViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()
    viewController.renderForTesting(snapshot: nil)

    XCTAssertNotNil(findLabel(Copy.dashboardEmptyTitle, in: viewController.view))
    XCTAssertNotNil(findLabel(Copy.dashboardEmptyBody, in: viewController.view))
  }

  func testDashboardPopulatedStateShowsResearchDeskSectionsAndPartialPricing() {
    let viewController = TokenCostDashboardViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()
    viewController.renderForTesting(snapshot: makeSnapshot())
    viewController.view.layoutSubtreeIfNeeded()

    XCTAssertNotNil(findLabel(Copy.dashboardTitle, in: viewController.view))
    XCTAssertNotNil(findLabel(Copy.dashboardBurnTimeline, in: viewController.view))
    XCTAssertNotNil(findLabel(Copy.dashboardModelLeaderboard, in: viewController.view))
    XCTAssertNotNil(findLabel(Copy.dashboardNarrative, in: viewController.view))
    XCTAssertNotNil(findLabel(Copy.dashboardPartialPricing, in: viewController.view))
    XCTAssertNotNil(findLabel("gpt-5", in: viewController.view))
    XCTAssertNotNil(findButton(Copy.dashboardCopyJSON, in: viewController.view))
  }

  func testDashboardWindowCreatesScrollableDocumentHeight() throws {
    let viewController = TokenCostDashboardViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.frame = NSRect(x: 0, y: 0, width: 1240, height: 920)
    viewController.renderForTesting(snapshot: makeSnapshot())
    viewController.view.layoutSubtreeIfNeeded()

    let scrollView = try XCTUnwrap(findScrollView(in: viewController.view))
    let documentView = try XCTUnwrap(scrollView.documentView)

    XCTAssertGreaterThan(scrollView.contentSize.height, 100)
    XCTAssertGreaterThan(documentView.fittingSize.height, scrollView.contentSize.height)
  }

  func testPopoverCostCardShowsOpenDashboardButton() {
    let viewController = PopoverViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    XCTAssertNotNil(findButton(Copy.costOpenDashboard, in: viewController.view))
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

  private func findScrollView(in view: NSView) -> NSScrollView? {
    if let scrollView = view as? NSScrollView {
      return scrollView
    }

    for subview in view.subviews {
      if let scrollView = findScrollView(in: subview) {
        return scrollView
      }
    }

    return nil
  }

  private func findLabel(_ text: String, in view: NSView) -> NSTextField? {
    allTextFields(in: view).first { $0.stringValue == text }
  }

  private func findButton(_ title: String, in view: NSView) -> NSButton? {
    allButtons(in: view).first { $0.title == title }
  }

  private func makeSnapshot() -> TokenCostSnapshot {
    let alerts = [
      TokenCostInsight(
        kind: "partial_pricing",
        title: "Partial pricing",
        message: "Some 30D usage came from unpriced models.",
        severity: "warning"
      ),
    ]

    let narrative = TokenCostNarrative(
      whatChanged: ["30D spend stayed elevated across 5 active days."],
      whatHelped: ["Cache reads covered 38% of input tokens."],
      whatToWatch: ["pricing is incomplete because one model has no rate card."]
    )

    let modelSummaries = [
      TokenCostModelSummary(
        modelName: "gpt-5",
        inputTokens: 80_000,
        cacheReadTokens: 30_000,
        outputTokens: 12_000,
        totalTokens: 92_000,
        costUSD: 26.5,
        costShare: nil,
        tokenShare: 0.76
      ),
      TokenCostModelSummary(
        modelName: "gpt-5-mini",
        inputTokens: 22_000,
        cacheReadTokens: 8_000,
        outputTokens: 4_000,
        totalTokens: 26_000,
        costUSD: 2.4,
        costShare: nil,
        tokenShare: 0.24
      ),
    ]

    let hourly = [
      TokenCostHourlyEntry(hour: 9, inputTokens: 20_000, cacheReadTokens: 8_000, outputTokens: 4_000, totalTokens: 24_000, costUSD: 8.1),
      TokenCostHourlyEntry(hour: 14, inputTokens: 18_000, cacheReadTokens: 7_000, outputTokens: 3_000, totalTokens: 21_000, costUSD: nil),
    ]

    let daily = [
      TokenCostDailyEntry(
        date: "2026-04-01",
        inputTokens: 8_000,
        cacheReadTokens: 3_000,
        outputTokens: 1_200,
        totalTokens: 9_200,
        costUSD: nil,
        modelsUsed: ["gpt-5", "gpt-5-mini"],
        modelBreakdowns: [
          TokenCostModelBreakdown(modelName: "gpt-5", inputTokens: 6_000, cacheReadTokens: 2_500, outputTokens: 1_000, costUSD: 2.8, totalTokens: 7_000),
          TokenCostModelBreakdown(modelName: "gpt-5-mini", inputTokens: 2_000, cacheReadTokens: 500, outputTokens: 200, costUSD: nil, totalTokens: 2_200),
        ],
        hourlyBreakdowns: hourly
      ),
    ]

    let windows = [
      TokenCostWindowSummary(
        windowDays: 7,
        totalTokens: 40_000,
        totalCostUSD: 8.5,
        averageDailyTokens: 5_714.2,
        averageDailyCostUSD: 1.21,
        activeDayCount: 4,
        cacheShare: 0.40,
        dominantModelName: "gpt-5",
        modelSummaries: modelSummaries,
        hourly: hourly,
        alerts: [],
        narrative: narrative,
        hasPartialPricing: false
      ),
      TokenCostWindowSummary(
        windowDays: 30,
        totalTokens: 118_000,
        totalCostUSD: nil,
        averageDailyTokens: 3_933.3,
        averageDailyCostUSD: nil,
        activeDayCount: 5,
        cacheShare: 0.38,
        dominantModelName: "gpt-5",
        modelSummaries: modelSummaries,
        hourly: hourly,
        alerts: alerts,
        narrative: narrative,
        hasPartialPricing: true
      ),
      TokenCostWindowSummary(
        windowDays: 90,
        totalTokens: 200_000,
        totalCostUSD: 118.4,
        averageDailyTokens: 2_222.2,
        averageDailyCostUSD: 1.31,
        activeDayCount: 12,
        cacheShare: 0.31,
        dominantModelName: "gpt-5",
        modelSummaries: modelSummaries,
        hourly: hourly,
        alerts: alerts,
        narrative: narrative,
        hasPartialPricing: false
      ),
    ]

    return TokenCostSnapshot(
      todayTokens: 9_200,
      todayCostUSD: nil,
      last7DaysTokens: 40_000,
      last7DaysCostUSD: 8.5,
      last30DaysTokens: 118_000,
      last30DaysCostUSD: nil,
      last90DaysTokens: 200_000,
      last90DaysCostUSD: 118.4,
      averageDailyTokens: 3_933.3,
      averageDailyCostUSD: nil,
      modelSummaries: modelSummaries,
      hourly: hourly,
      alerts: alerts,
      narrative: narrative,
      windows: windows,
      hasPartialPricing: true,
      daily: daily,
      updatedAt: Date(timeIntervalSince1970: 1_775_100_000)
    )
  }
}
