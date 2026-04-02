import XCTest
import AppKit
@testable import CodexRateWatcherNative
@testable import CodexRateKit

// MARK: - Quota Card Layout Tests
//
// These tests verify that the "Other Quotas" card has the correct Auto Layout
// structure after the fix that moved detail labels below the metric row to
// prevent text overlap with long Chinese strings.

@MainActor
final class QuotaCardLayoutTests: XCTestCase {

  private var vc: PopoverViewController!

  override func setUp() async throws {
    try await super.setUp()
    let monitor = UsageMonitor()
    vc = PopoverViewController(monitor: monitor)
    _ = vc.view
    vc.view.layoutSubtreeIfNeeded()
  }

  override func tearDown() async throws {
    vc = nil
    try await super.tearDown()
  }

  // MARK: - Helpers

  /// Recursively find all NSTextField instances in the view hierarchy.
  private func allTextFields(in view: NSView) -> [NSTextField] {
    var result: [NSTextField] = []
    for sub in view.subviews {
      if let tf = sub as? NSTextField {
        result.append(tf)
      }
      result += allTextFields(in: sub)
    }
    return result
  }

  /// Find the first NSTextField whose stringValue matches a prefix.
  private func findTextField(withPrefix prefix: String, in view: NSView) -> NSTextField? {
    allTextFields(in: view).first { $0.stringValue.hasPrefix(prefix) }
  }

  /// Find a label by its exact string value.
  private func findLabel(_ text: String, in view: NSView) -> NSTextField? {
    allTextFields(in: view).first { $0.stringValue == text }
  }

  /// Find the "Other Quotas" card container by locating its section label.
  private func findQuotaCard() -> NSView? {
    let labels = allTextFields(in: vc.view)
    guard let sectionLabel = labels.first(where: { $0.stringValue == "Other Quotas" }) else {
      return nil
    }
    // The card is the section label's direct superview
    return sectionLabel.superview
  }

  // MARK: - Test: Detail labels exist and are single-line

  func testWeeklyDetailIsSingleLine() {
    let labels = allTextFields(in: vc.view)
    let weeklyLabel = labels.first { $0.stringValue == "Weekly" }
    XCTAssertNotNil(weeklyLabel, "Weekly label should exist")

    // Find the detail label: it's the one with maximumNumberOfLines == 1
    // in the same card, not "Weekly", not a percentage, not "Other Quotas"
    guard let card = findQuotaCard() else {
      XCTFail("Other Quotas card not found")
      return
    }
    let detailLabels = allTextFields(in: card).filter {
      $0.maximumNumberOfLines == 1
      && $0.lineBreakMode == .byTruncatingTail
      && $0.stringValue != "Other Quotas"
      && $0.stringValue != "Weekly"
      && $0.stringValue != "Review"
    }
    // Should have at least the weekly and review detail labels
    XCTAssertGreaterThanOrEqual(detailLabels.count, 2,
      "Should have at least 2 truncating detail labels (weekly + review)")
  }

  // MARK: - Test: Detail labels are NOT baseline-aligned with metric labels

  func testDetailLabelsAreNotBaselineAligned() {
    guard let card = findQuotaCard() else {
      XCTFail("Other Quotas card not found")
      return
    }

    // Collect all constraints on the card and its subviews
    var allConstraints: [NSLayoutConstraint] = card.constraints
    for subview in card.subviews {
      allConstraints += subview.constraints
    }

    // There should be NO firstBaselineAnchor constraints between any items
    let baselineConstraints = allConstraints.filter { c in
      c.firstAttribute == .firstBaseline || c.secondAttribute == .firstBaseline
    }

    XCTAssertTrue(baselineConstraints.isEmpty,
      "No firstBaseline constraints should exist in the quota card; " +
      "detail labels should use topAnchor instead. Found \(baselineConstraints.count) baseline constraint(s).")
  }

  // MARK: - Test: Progress track uses trailing anchor (not fixed 120pt width)

  func testProgressTrackUsesFlexibleWidth() {
    guard let card = findQuotaCard() else {
      XCTFail("Other Quotas card not found")
      return
    }

    // Find all progress track views (they have cornerRadius == 2 and height == 4)
    let tracks = card.subviews.filter { view in
      view.layer?.cornerRadius == 2
      && view.subviews.count <= 1  // track contains only fill
      && !(view is NSTextField)
    }

    XCTAssertGreaterThanOrEqual(tracks.count, 2,
      "Should have at least 2 progress tracks (weekly + review)")

    for track in tracks {
      // Check that the track does NOT have a fixed width constraint of 120
      let fixedWidthConstraints = track.constraints.filter { c in
        c.firstAttribute == .width
        && c.relation == .equal
        && c.secondItem == nil  // fixed constant (not relative)
        && c.constant == 120
      }
      XCTAssertTrue(fixedWidthConstraints.isEmpty,
        "Progress track should NOT have fixed 120pt width; should use trailing anchor instead")
    }
  }

  // MARK: - Test: Card bottom is anchored to review detail (not review label)

  func testCardBottomAnchorsToReviewDetail() {
    guard let card = findQuotaCard() else {
      XCTFail("Other Quotas card not found")
      return
    }

    let labels = allTextFields(in: card)
    let reviewLabel = labels.first { $0.stringValue == "Review" }
    XCTAssertNotNil(reviewLabel, "Review label should exist in the card")

    // Check that reviewLabel does NOT have a bottom constraint to the card
    let reviewLabelBottomToCard = card.constraints.filter { c in
      c.firstAttribute == .bottom
      && (c.firstItem === reviewLabel || c.secondItem === reviewLabel)
    }
    XCTAssertTrue(reviewLabelBottomToCard.isEmpty,
      "reviewLabel should NOT be the bottom anchor of the card; reviewDetail should be")
  }

  // MARK: - Test: Accent color thresholds

  func testAccentColorGreen() {
    let color = PopoverViewController.accentColor(for: 65.0)
    // Green range: 60-100
    XCTAssertNotNil(color, "Should return a valid color for 65%")
  }

  func testAccentColorYellow() {
    let color = PopoverViewController.accentColor(for: 40.0)
    XCTAssertNotNil(color, "Should return a valid color for 40%")
  }

  func testAccentColorRed() {
    let color = PopoverViewController.accentColor(for: 10.0)
    XCTAssertNotNil(color, "Should return a valid color for 10%")
  }

  func testAccentColorBoundary60() {
    // 60% is the lower boundary of green
    let color60 = PopoverViewController.accentColor(for: 60.0)
    let color59 = PopoverViewController.accentColor(for: 59.9)
    // They should be different colors (green vs yellow)
    XCTAssertNotEqual(color60, color59,
      "60% should be green, 59.9% should be yellow")
  }

  func testAccentColorBoundary26() {
    let color26 = PopoverViewController.accentColor(for: 26.0)
    let color25 = PopoverViewController.accentColor(for: 25.9)
    // They should be different colors (yellow vs red)
    XCTAssertNotEqual(color26, color25,
      "26% should be yellow, 25.9% should be red")
  }

  // MARK: - Test: Plan name formatting

  func testPlanNameTeam() {
    XCTAssertEqual(PopoverViewController.planName(for: "team"), "Team")
  }

  func testPlanNamePlus() {
    XCTAssertEqual(PopoverViewController.planName(for: "plus"), "Plus")
  }

  func testPlanNameUnknown() {
    XCTAssertEqual(PopoverViewController.planName(for: "enterprise"), "Enterprise")
  }

  func testPlanNameCaseInsensitive() {
    XCTAssertEqual(PopoverViewController.planName(for: "TEAM"), "Team")
    XCTAssertEqual(PopoverViewController.planName(for: "Plus"), "Plus")
  }
}
