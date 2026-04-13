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

  func testDashboardMergedSnapshotShowsAllDeviceAndAccountContext() {
    let viewController = TokenCostDashboardViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()
    viewController.renderForTesting(snapshot: makeFullyPricedSnapshot())
    viewController.view.layoutSubtreeIfNeeded()

    XCTAssertNotNil(findLabel("ALL DEVICES TOKEN COST", in: viewController.view))
    XCTAssertNotNil(findLabel("alpha@example.com", in: viewController.view))
    XCTAssertNotNil(findLabel("Local / Unknown", in: viewController.view))
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

  func testPopoverCostCardShowsShareButton() {
    let viewController = PopoverViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    XCTAssertNotNil(findButton("Share", in: viewController.view))
  }

  func testPopoverCanBuildLargeSharePreviewWithCopyImageAction() throws {
    let viewController = PopoverViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    viewController.renderForTesting(state: makeState())
    viewController.view.layoutSubtreeIfNeeded()

    let previewController = try XCTUnwrap(viewController.makeCostSharePreviewControllerForTesting())
    _ = previewController.view
    previewController.view.layoutSubtreeIfNeeded()

    XCTAssertNotNil(findButton("Copy Image", in: previewController.view))

    let image = try XCTUnwrap(previewController.renderImageForTesting())
    XCTAssertGreaterThan(image.size.width, 700)
    XCTAssertGreaterThan(image.size.height, 350)
  }

  func testSharePreviewUsesFullWidthChartStage() throws {
    let viewController = PopoverViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    viewController.renderForTesting(state: makeState())
    viewController.view.layoutSubtreeIfNeeded()

    let previewController = try XCTUnwrap(viewController.makeCostSharePreviewControllerForTesting())
    _ = previewController.view
    previewController.view.layoutSubtreeIfNeeded()

    let titleLabel = try XCTUnwrap(findLabel("Burn Pattern", in: previewController.view))
    let chartHeader = try XCTUnwrap(titleLabel.superview)
    let chartCard = try XCTUnwrap(chartHeader.superview)

    XCTAssertGreaterThan(chartCard.frame.width, 680)
  }

  func testSharePreviewKeepsWindowCardsTallEnoughToShowMetrics() throws {
    let viewController = PopoverViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    viewController.renderForTesting(state: makeState(snapshot: makeFullyPricedSnapshot()))
    viewController.view.layoutSubtreeIfNeeded()

    let previewController = try XCTUnwrap(viewController.makeCostSharePreviewControllerForTesting())
    _ = previewController.view
    previewController.view.layoutSubtreeIfNeeded()

    let currentTitle = try XCTUnwrap(findLabel("CURRENT", in: previewController.view))
    let currentCard = try XCTUnwrap(currentTitle.superview)

    XCTAssertGreaterThanOrEqual(currentCard.frame.height, 140)
  }

  func testSharePreviewAlignsHeaderTitleToCopyButtonTitleCenter() throws {
    let viewController = PopoverViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    viewController.renderForTesting(state: makeState())
    viewController.view.layoutSubtreeIfNeeded()

    let previewController = try XCTUnwrap(viewController.makeCostSharePreviewControllerForTesting())
    _ = previewController.view
    previewController.view.layoutSubtreeIfNeeded()

    let titleLabel = try XCTUnwrap(findLabel(Copy.costSharePreviewTitle, in: previewController.view))
    let button = try XCTUnwrap(findButton(Copy.costShareCopyImage, in: previewController.view))
    let cell = try XCTUnwrap(button.cell as? NSButtonCell)

    let titleRect = cell.titleRect(forBounds: button.bounds)
    let buttonTitleMidY = button.frame.minY + titleRect.midY
    let delta = abs(titleLabel.frame.midY - buttonTitleMidY)

    XCTAssertLessThanOrEqual(delta, 1.0)
  }

  func testSharePreviewCentersBrandTextInsideBadgeChip() throws {
    let viewController = PopoverViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    viewController.renderForTesting(state: makeState())
    viewController.view.layoutSubtreeIfNeeded()

    let previewController = try XCTUnwrap(viewController.makeCostSharePreviewControllerForTesting())
    _ = previewController.view
    previewController.view.layoutSubtreeIfNeeded()

    let brandLabel = try XCTUnwrap(findLabel(Copy.costShareBrand.uppercased(), in: previewController.view))
    let badgeChip = try XCTUnwrap(brandLabel.superview)
    let delta = abs(brandLabel.frame.midY - badgeChip.bounds.midY)

    XCTAssertLessThanOrEqual(delta, 1.0)
  }

  func testSharePreviewShowsCurrentSevenAndThirtyDayPeriodCards() throws {
    let viewController = PopoverViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    viewController.renderForTesting(state: makeState(snapshot: makeFullyPricedSnapshot()))
    viewController.view.layoutSubtreeIfNeeded()

    let previewController = try XCTUnwrap(viewController.makeCostSharePreviewControllerForTesting())
    _ = previewController.view
    previewController.view.layoutSubtreeIfNeeded()

    XCTAssertNotNil(findLabel("CURRENT", in: previewController.view))
    XCTAssertNotNil(findLabel("7D", in: previewController.view))
    XCTAssertNotNil(findLabel("30D", in: previewController.view))

    XCTAssertNotNil(findLabel("9.2K tokens", in: previewController.view))
    XCTAssertNotNil(findLabel("40.0K tokens", in: previewController.view))
    XCTAssertNotNil(findLabel("118.0K tokens", in: previewController.view))
  }

  func testSharePreviewShowsAverageSublineForWindowCards() throws {
    let viewController = PopoverViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    viewController.renderForTesting(state: makeState(snapshot: makeFullyPricedSnapshot()))
    viewController.view.layoutSubtreeIfNeeded()

    let previewController = try XCTUnwrap(viewController.makeCostSharePreviewControllerForTesting())
    _ = previewController.view
    previewController.view.layoutSubtreeIfNeeded()

    XCTAssertNotNil(findLabel("Avg/day 5.7K tokens", in: previewController.view))
    XCTAssertNotNil(findLabel("Avg/day 3.9K tokens", in: previewController.view))
  }

  func testSharePreviewShowsApiPricedSpendAsSmallerDetailBelowTokenHeadline() throws {
    let viewController = PopoverViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    viewController.renderForTesting(state: makeState(snapshot: makeFullyPricedSnapshot()))
    viewController.view.layoutSubtreeIfNeeded()

    let previewController = try XCTUnwrap(viewController.makeCostSharePreviewControllerForTesting())
    _ = previewController.view
    previewController.view.layoutSubtreeIfNeeded()

    let currentCard = try XCTUnwrap(findLabel("CURRENT", in: previewController.view)?.superview)
    let currentTokenLabel = try XCTUnwrap(findLabel("9.2K tokens", in: currentCard))
    let currentCostLabel = try XCTUnwrap(findLabel("API priced $3.40", in: currentCard))

    XCTAssertGreaterThan(currentTokenLabel.font?.pointSize ?? 0, currentCostLabel.font?.pointSize ?? 0)

    XCTAssertNotNil(findLabel("API priced $8.50 · 4 active days", in: previewController.view))
    XCTAssertNotNil(findLabel("API priced $34.20 · 5 active days", in: previewController.view))
  }

  func testSharePreviewRemovesLegacyThirtyDayHeroCopy() throws {
    let viewController = PopoverViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    viewController.renderForTesting(state: makeState(snapshot: makeFullyPricedSnapshot()))
    viewController.view.layoutSubtreeIfNeeded()

    let previewController = try XCTUnwrap(viewController.makeCostSharePreviewControllerForTesting())
    _ = previewController.view
    previewController.view.layoutSubtreeIfNeeded()

    XCTAssertNil(findLabel("30-DAY COST", in: previewController.view))
    XCTAssertNil(findLabel("5 active days · Dominant gpt-5", in: previewController.view))
  }

  func testSharePreviewUsesCompactWindowDetailInsteadOfNarrativeSentence() throws {
    let viewController = PopoverViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    viewController.renderForTesting(state: makeState(snapshot: makeFullyPricedSnapshot()))
    viewController.view.layoutSubtreeIfNeeded()

    let previewController = try XCTUnwrap(viewController.makeCostSharePreviewControllerForTesting())
    _ = previewController.view
    previewController.view.layoutSubtreeIfNeeded()

    XCTAssertNotNil(findLabel("API priced $34.20 · 5 active days", in: previewController.view))
    XCTAssertNil(findLabel("30D spend stayed elevated across 5 active days.", in: previewController.view))
  }

  func testSharePreviewTokenMetricKeepsFullTextHeightForDescenders() throws {
    let snapshot = makeFullyPricedSnapshot(dominantModelName: "opt-5.4")
    let viewController = PopoverViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    viewController.renderForTesting(state: makeState(snapshot: snapshot))
    viewController.view.layoutSubtreeIfNeeded()

    let previewController = try XCTUnwrap(viewController.makeCostSharePreviewControllerForTesting())
    _ = previewController.view
    previewController.view.layoutSubtreeIfNeeded()

    let metricLabel = try XCTUnwrap(findLabel("118.0K tokens", in: previewController.view))

    XCTAssertGreaterThanOrEqual(
      metricLabel.frame.height,
      metricLabel.intrinsicContentSize.height
    )
  }

  func testSharePreviewWindowDetailKeepsBottomPadding() throws {
    let viewController = PopoverViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    viewController.renderForTesting(state: makeState(snapshot: makeFullyPricedSnapshot()))
    viewController.view.layoutSubtreeIfNeeded()

    let previewController = try XCTUnwrap(viewController.makeCostSharePreviewControllerForTesting())
    _ = previewController.view
    previewController.view.layoutSubtreeIfNeeded()

    let detailLabel = try XCTUnwrap(findLabel("API priced $34.20 · 5 active days", in: previewController.view))
    let metricCard = try XCTUnwrap(detailLabel.superview)

    XCTAssertGreaterThanOrEqual(detailLabel.frame.minY, 12)
    XCTAssertGreaterThanOrEqual(metricCard.frame.height, 140)
  }

  func testPopoverCostCardHoverShowsExpandedTokenCostContext() throws {
    let viewController = PopoverViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    let state = UsageMonitor.State(
      snapshot: makeUsageSnapshot(),
      profiles: [],
      activeProfileID: nil,
      errorMessage: nil,
      lastUpdatedAt: Date(),
      isRefreshing: false,
      isAddingAccount: false,
      tokenCostSnapshot: makeSnapshot(),
      primaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 60 * 2, percentPerHour: 10, statusText: "steady"),
      secondaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 60 * 12, percentPerHour: 1, statusText: "calm"),
      reviewEstimate: BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "idle")
    )

    viewController.renderForTesting(state: state)
    viewController.view.layoutSubtreeIfNeeded()

    XCTAssertTrue(
      allViews(in: viewController.view)
        .map(\.toolTip)
        .allSatisfy { $0 == nil || $0?.isEmpty == true }
    )
  }

  func testPopoverCostCardHoverPanelCanBeToggledForVisibleDetail() throws {
    let viewController = PopoverViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    let state = UsageMonitor.State(
      snapshot: makeUsageSnapshot(),
      profiles: [],
      activeProfileID: nil,
      errorMessage: nil,
      lastUpdatedAt: Date(),
      isRefreshing: false,
      isAddingAccount: false,
      tokenCostSnapshot: makeSnapshot(),
      primaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 60 * 2, percentPerHour: 10, statusText: "steady"),
      secondaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 60 * 12, percentPerHour: 1, statusText: "calm"),
      reviewEstimate: BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "idle")
    )

    viewController.renderForTesting(state: state)
    viewController.view.layoutSubtreeIfNeeded()

    let selector = NSSelectorFromString("setCostHoverIndexForTesting:")
    XCTAssertTrue(viewController.responds(to: selector))

    _ = viewController.perform(selector, with: 0)
    viewController.view.layoutSubtreeIfNeeded()

    XCTAssertNotNil(findLabel("2026-04-01", in: viewController.view))
    XCTAssertTrue(
      allTextFields(in: viewController.view)
        .map(\.stringValue)
        .contains { $0.contains("日期: 2026-04-01 · 成本:") }
    )
    XCTAssertTrue(
      allTextFields(in: viewController.view)
        .map(\.stringValue)
        .contains { $0.contains("主模型: gpt-5") }
    )
  }

  func testPopoverCostHoverPanelFloatsNearSparklineInsteadOfCoveringIt() {
    let viewController = PopoverViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    let state = UsageMonitor.State(
      snapshot: makeUsageSnapshot(),
      profiles: [],
      activeProfileID: nil,
      errorMessage: nil,
      lastUpdatedAt: Date(),
      isRefreshing: false,
      isAddingAccount: false,
      tokenCostSnapshot: makeSnapshot(),
      primaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 60 * 2, percentPerHour: 10, statusText: "steady"),
      secondaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 60 * 12, percentPerHour: 1, statusText: "calm"),
      reviewEstimate: BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "idle")
    )

    viewController.renderForTesting(state: state)
    _ = viewController.perform(NSSelectorFromString("setCostHoverVisibleForTesting:"), with: true)
    viewController.view.layoutSubtreeIfNeeded()

    let panelFrame = viewController.costHoverPanelFrameForTesting()
    let sparklineFrame = viewController.costSparklineFrameForTesting()

    XCTAssertFalse(panelFrame.intersects(sparklineFrame))
    XCTAssertLessThan(panelFrame.width, sparklineFrame.width - 40)
  }

  func testPopoverCostHoverTracksSparklineInsteadOfModeCard() {
    let viewController = PopoverViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    let state = UsageMonitor.State(
      snapshot: makeUsageSnapshot(),
      profiles: [],
      activeProfileID: nil,
      errorMessage: nil,
      lastUpdatedAt: Date(),
      isRefreshing: false,
      isAddingAccount: false,
      tokenCostSnapshot: makeSnapshot(),
      primaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 60 * 2, percentPerHour: 10, statusText: "steady"),
      secondaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 60 * 12, percentPerHour: 1, statusText: "calm"),
      reviewEstimate: BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "idle")
    )

    viewController.renderForTesting(state: state)
    viewController.view.layoutSubtreeIfNeeded()

    XCTAssertEqual(
      viewController.costHoverTargetFrameForTesting(),
      viewController.costSparklineFrameForTesting()
    )
  }

  func testPopoverCostCardShowsSevenDaySummaryInline() {
    let viewController = PopoverViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    let state = UsageMonitor.State(
      snapshot: makeUsageSnapshot(),
      profiles: [],
      activeProfileID: nil,
      errorMessage: nil,
      lastUpdatedAt: Date(),
      isRefreshing: false,
      isAddingAccount: false,
      tokenCostSnapshot: makeSnapshot(),
      primaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 60 * 2, percentPerHour: 10, statusText: "steady"),
      secondaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 60 * 12, percentPerHour: 1, statusText: "calm"),
      reviewEstimate: BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "idle")
    )

    viewController.renderForTesting(state: state)
    viewController.view.layoutSubtreeIfNeeded()

    XCTAssertTrue(viewController.costSublineTextForTesting().contains("7d"))
  }

  func testPopoverCostCardShowsLocalSupportingDetailWhenMergedSnapshotExists() {
    let viewController = PopoverViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    let state = UsageMonitor.State(
      snapshot: makeUsageSnapshot(),
      profiles: [],
      activeProfileID: nil,
      errorMessage: nil,
      lastUpdatedAt: Date(),
      isRefreshing: false,
      isAddingAccount: false,
      tokenCostSnapshot: makeFullyPricedSnapshot(),
      primaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 60 * 2, percentPerHour: 10, statusText: "steady"),
      secondaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 60 * 12, percentPerHour: 1, statusText: "calm"),
      reviewEstimate: BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "idle")
    )

    viewController.renderForTesting(state: state)
    viewController.view.layoutSubtreeIfNeeded()

    XCTAssertTrue(viewController.costSublineTextForTesting().contains("Local"))
  }

  func testPopoverCostSparklineUsesTallerChartForDailyHovering() {
    let viewController = PopoverViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    let state = UsageMonitor.State(
      snapshot: makeUsageSnapshot(),
      profiles: [],
      activeProfileID: nil,
      errorMessage: nil,
      lastUpdatedAt: Date(),
      isRefreshing: false,
      isAddingAccount: false,
      tokenCostSnapshot: makeSnapshot(),
      primaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 60 * 2, percentPerHour: 10, statusText: "steady"),
      secondaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 60 * 12, percentPerHour: 1, statusText: "calm"),
      reviewEstimate: BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "idle")
    )

    viewController.renderForTesting(state: state)
    viewController.view.layoutSubtreeIfNeeded()

    XCTAssertGreaterThanOrEqual(viewController.costSparklineFrameForTesting().height, 40)
  }

  func testPopoverCostHoverCanFocusSpecificDay() throws {
    let viewController = PopoverViewController(monitor: UsageMonitor())
    _ = viewController.view
    viewController.view.layoutSubtreeIfNeeded()

    let state = UsageMonitor.State(
      snapshot: makeUsageSnapshot(),
      profiles: [],
      activeProfileID: nil,
      errorMessage: nil,
      lastUpdatedAt: Date(),
      isRefreshing: false,
      isAddingAccount: false,
      tokenCostSnapshot: makeSnapshot(),
      primaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 60 * 2, percentPerHour: 10, statusText: "steady"),
      secondaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 60 * 12, percentPerHour: 1, statusText: "calm"),
      reviewEstimate: BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "idle")
    )

    viewController.renderForTesting(state: state)
    viewController.view.layoutSubtreeIfNeeded()

    let selector = NSSelectorFromString("setCostHoverIndexForTesting:")
    XCTAssertTrue(viewController.responds(to: selector))

    _ = viewController.perform(selector, with: 0)
    viewController.view.layoutSubtreeIfNeeded()

    XCTAssertNotNil(findLabel("2026-04-01", in: viewController.view))
    XCTAssertTrue(
      allTextFields(in: viewController.view)
        .map(\.stringValue)
        .contains { $0.contains("主模型") || $0.contains("gpt-5") }
    )
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

  private func allViews(in view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(allViews)
  }

  private func findLabel(_ text: String, in view: NSView) -> NSTextField? {
    allTextFields(in: view).first { $0.stringValue == text }
  }

  private func findButton(_ title: String, in view: NSView) -> NSButton? {
    allButtons(in: view).first { $0.title == title }
  }

  private func makeUsageSnapshot() -> UsageSnapshot {
    let data = Data(
      """
      {
        "plan_type": "plus",
        "rate_limit": {
          "allowed": true,
          "limit_reached": false,
          "primary_window": {
            "used_percent": 18,
            "limit_window_seconds": 18000,
            "reset_after_seconds": 7200,
            "reset_at": 4102444800
          },
          "secondary_window": {
            "used_percent": 22,
            "limit_window_seconds": 604800,
            "reset_after_seconds": 86400,
            "reset_at": 4102444800
          }
        },
        "code_review_rate_limit": {
          "allowed": true,
          "limit_reached": false,
          "primary_window": {
            "used_percent": 5,
            "limit_window_seconds": 18000,
            "reset_after_seconds": 7200,
            "reset_at": 4102444800
          }
        },
        "credits": {
          "has_credits": false,
          "unlimited": false
        }
      }
      """.utf8
    )

    return try! JSONDecoder().decode(UsageSnapshot.self, from: data)
  }

  private func makeState(snapshot: TokenCostSnapshot? = nil) -> UsageMonitor.State {
    UsageMonitor.State(
      snapshot: makeUsageSnapshot(),
      profiles: [],
      activeProfileID: nil,
      errorMessage: nil,
      lastUpdatedAt: Date(),
      isRefreshing: false,
      isAddingAccount: false,
      tokenCostSnapshot: snapshot ?? makeSnapshot(),
      primaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 60 * 2, percentPerHour: 10, statusText: "steady"),
      secondaryEstimate: BurnEstimate(timeUntilExhausted: 60 * 60 * 12, percentPerHour: 1, statusText: "calm"),
      reviewEstimate: BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "idle")
    )
  }

  private func makeSnapshot(dominantModelName: String = "gpt-5") -> TokenCostSnapshot {
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
        modelName: dominantModelName,
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
        dominantModelName: dominantModelName,
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
        dominantModelName: dominantModelName,
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
        dominantModelName: dominantModelName,
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
      source: TokenCostSourceSummary(
        mode: .iCloudMerged,
        syncedDeviceCount: 2,
        localDeviceID: "device-a",
        localDeviceName: "Mac A",
        updatedAt: Date(timeIntervalSince1970: 1_775_100_000)
      ),
      localSummary: TokenCostLocalSummary(
        todayTokens: 4_200,
        todayCostUSD: 1.1,
        last30DaysTokens: 39_000,
        last30DaysCostUSD: 10.8
      ),
      accountSummaries: [
        TokenCostAccountSummary(
          accountKey: "managed:acct-1",
          displayName: "alpha@example.com",
          todayTokens: 6_400,
          todayCostUSD: 2.3,
          last30DaysTokens: 72_000,
          last30DaysCostUSD: 22.1,
          sessionCount: 12,
          deviceCount: 2
        ),
        TokenCostAccountSummary(
          accountKey: "local_unknown",
          displayName: "Local / Unknown",
          todayTokens: 2_800,
          todayCostUSD: nil,
          last30DaysTokens: 46_000,
          last30DaysCostUSD: nil,
          sessionCount: 7,
          deviceCount: 1
        ),
      ],
      updatedAt: Date(timeIntervalSince1970: 1_775_100_000)
    )
  }

  private func makeFullyPricedSnapshot(dominantModelName: String = "gpt-5") -> TokenCostSnapshot {
    let base = makeSnapshot(dominantModelName: dominantModelName)

    let windows = base.windows.map { window in
      switch window.windowDays {
      case 30:
        TokenCostWindowSummary(
          windowDays: window.windowDays,
          totalTokens: window.totalTokens,
          totalCostUSD: 34.2,
          averageDailyTokens: window.averageDailyTokens,
          averageDailyCostUSD: 1.14,
          activeDayCount: window.activeDayCount,
          cacheShare: window.cacheShare,
          dominantModelName: window.dominantModelName,
          modelSummaries: window.modelSummaries,
          hourly: window.hourly,
          alerts: [],
          narrative: window.narrative,
          hasPartialPricing: false
        )
      case 7:
        TokenCostWindowSummary(
          windowDays: window.windowDays,
          totalTokens: window.totalTokens,
          totalCostUSD: window.totalCostUSD,
          averageDailyTokens: window.averageDailyTokens,
          averageDailyCostUSD: 1.21,
          activeDayCount: window.activeDayCount,
          cacheShare: window.cacheShare,
          dominantModelName: window.dominantModelName,
          modelSummaries: window.modelSummaries,
          hourly: window.hourly,
          alerts: window.alerts,
          narrative: window.narrative,
          hasPartialPricing: false
        )
      default:
        window
      }
    }

    let daily = base.daily.map { entry in
      TokenCostDailyEntry(
        date: entry.date,
        inputTokens: entry.inputTokens,
        cacheReadTokens: entry.cacheReadTokens,
        outputTokens: entry.outputTokens,
        totalTokens: entry.totalTokens,
        costUSD: 3.4,
        modelsUsed: entry.modelsUsed,
        modelBreakdowns: entry.modelBreakdowns,
        hourlyBreakdowns: entry.hourlyBreakdowns
      )
    }

    return TokenCostSnapshot(
      todayTokens: base.todayTokens,
      todayCostUSD: 3.4,
      last7DaysTokens: base.last7DaysTokens,
      last7DaysCostUSD: 8.5,
      last30DaysTokens: base.last30DaysTokens,
      last30DaysCostUSD: 34.2,
      last90DaysTokens: base.last90DaysTokens,
      last90DaysCostUSD: base.last90DaysCostUSD,
      averageDailyTokens: base.averageDailyTokens,
      averageDailyCostUSD: 1.14,
      modelSummaries: base.modelSummaries,
      hourly: base.hourly,
      alerts: [],
      narrative: base.narrative,
      windows: windows,
      hasPartialPricing: false,
      daily: daily,
      source: base.source,
      localSummary: base.localSummary,
      accountSummaries: base.accountSummaries,
      updatedAt: base.updatedAt
    )
  }
}
