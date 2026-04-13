import XCTest
@testable import CodexRateKit

final class TokenCostCLITests: XCTestCase {
  func testJSONPayloadExposesDashboardAggregates() throws {
    let snapshot = makeSnapshot()

    let payload = TokenCostCLIPayload(snapshot: snapshot)

    XCTAssertEqual(payload.last7DaysTokens, 44_000)
    XCTAssertEqual(payload.last90DaysCostUSD ?? 0, 120.25, accuracy: 0.0001)
    XCTAssertEqual(payload.averageDailyTokens ?? 0, 4_000, accuracy: 0.0001)
    XCTAssertEqual(payload.modelSummaries.map(\.modelName), ["gpt-5", "gpt-5-mini"])
    XCTAssertEqual(payload.hourly.map(\.hour), [9, 14])
    XCTAssertEqual(payload.alerts.map(\.kind), ["high_cache_share", "model_concentration"])
    XCTAssertEqual(payload.narrative.whatChanged.count, 1)
    XCTAssertEqual(payload.windows.map(\.windowDays), [7, 30, 90])
    XCTAssertTrue(payload.hasPartialPricing)
    XCTAssertEqual(payload.activeDayCount, 5)
  }

  func testJSONPayloadIncludesMergedSourceLocalAndAccountSummaries() {
    let snapshot = makeSnapshot()

    let payload = TokenCostCLIPayload(snapshot: snapshot)

    XCTAssertEqual(payload.source?.mode, .iCloudMerged)
    XCTAssertEqual(payload.source?.syncedDeviceCount, 2)
    XCTAssertEqual(payload.localSummary?.todayTokens, 4_200)
    XCTAssertEqual(payload.accountSummaries.map(\.displayName), ["alpha@example.com", "Local / Unknown"])
    XCTAssertEqual(payload.accountSummaries.first?.last30DaysTokens, 72_000)
  }

  func testRenderTextShowsExecutiveMetricsAlertsAndModelLeaderboard() {
    let snapshot = makeSnapshot()

    let report = TokenCostCLIReport.renderText(snapshot: snapshot, colorized: false)

    XCTAssertTrue(report.contains("Token Cost"))
    XCTAssertTrue(report.contains("7 Day Cost"))
    XCTAssertTrue(report.contains("90 Day Cost"))
    XCTAssertTrue(report.contains("Cache Share"))
    XCTAssertTrue(report.contains("Dominant Model"))
    XCTAssertTrue(report.contains("Alerts"))
    XCTAssertTrue(report.contains("Top Models"))
    XCTAssertTrue(report.contains("gpt-5"))
    XCTAssertTrue(report.contains("Partial pricing"))
  }

  func testRenderTextShowsAllDeviceAndLocalScope() {
    let snapshot = makeSnapshot()

    let report = TokenCostCLIReport.renderText(snapshot: snapshot, colorized: false)

    XCTAssertTrue(report.contains("All Devices"))
    XCTAssertTrue(report.contains("Local Device"))
    XCTAssertTrue(report.contains("alpha@example.com"))
  }

  func testRenderTextDoesNotDuplicateLocalDeviceSectionForLocalOnlySnapshot() {
    var snapshot = makeSnapshot()
    snapshot = TokenCostSnapshot(
      todayTokens: snapshot.todayTokens,
      todayCostUSD: snapshot.todayCostUSD,
      last7DaysTokens: snapshot.last7DaysTokens,
      last7DaysCostUSD: snapshot.last7DaysCostUSD,
      last30DaysTokens: snapshot.last30DaysTokens,
      last30DaysCostUSD: snapshot.last30DaysCostUSD,
      last90DaysTokens: snapshot.last90DaysTokens,
      last90DaysCostUSD: snapshot.last90DaysCostUSD,
      averageDailyTokens: snapshot.averageDailyTokens,
      averageDailyCostUSD: snapshot.averageDailyCostUSD,
      modelSummaries: snapshot.modelSummaries,
      hourly: snapshot.hourly,
      alerts: snapshot.alerts,
      narrative: snapshot.narrative,
      windows: snapshot.windows,
      hasPartialPricing: snapshot.hasPartialPricing,
      daily: snapshot.daily,
      source: TokenCostSourceSummary(
        mode: .localOnly,
        syncedDeviceCount: 1,
        localDeviceID: "device-a",
        localDeviceName: "Mac A",
        updatedAt: Date(timeIntervalSince1970: 1_775_100_000)
      ),
      localSummary: snapshot.localSummary,
      accountSummaries: snapshot.accountSummaries,
      updatedAt: snapshot.updatedAt
    )

    let report = TokenCostCLIReport.renderText(snapshot: snapshot, colorized: false)
    let localDeviceOccurrences = report.components(separatedBy: "Local Device").count - 1

    XCTAssertEqual(localDeviceOccurrences, 1)
  }

  private func makeSnapshot() -> TokenCostSnapshot {
    let windows = [
      TokenCostWindowSummary(
        windowDays: 7,
        totalTokens: 44_000,
        totalCostUSD: 8.75,
        averageDailyTokens: 6_285.7142,
        averageDailyCostUSD: 1.25,
        activeDayCount: 4,
        cacheShare: 0.42,
        dominantModelName: "gpt-5",
        modelSummaries: [],
        hourly: [],
        alerts: [],
        narrative: .init(),
        hasPartialPricing: false
      ),
      TokenCostWindowSummary(
        windowDays: 30,
        totalTokens: 120_000,
        totalCostUSD: nil,
        averageDailyTokens: 4_000,
        averageDailyCostUSD: nil,
        activeDayCount: 5,
        cacheShare: 0.38,
        dominantModelName: "gpt-5",
        modelSummaries: [],
        hourly: [],
        alerts: [],
        narrative: .init(),
        hasPartialPricing: true
      ),
      TokenCostWindowSummary(
        windowDays: 90,
        totalTokens: 210_000,
        totalCostUSD: 120.25,
        averageDailyTokens: 2_333.3333,
        averageDailyCostUSD: 1.3361,
        activeDayCount: 12,
        cacheShare: 0.31,
        dominantModelName: "gpt-5",
        modelSummaries: [],
        hourly: [],
        alerts: [],
        narrative: .init(),
        hasPartialPricing: false
      ),
    ]

    return TokenCostSnapshot(
      todayTokens: 8_000,
      todayCostUSD: 1.75,
      last7DaysTokens: 44_000,
      last7DaysCostUSD: 8.75,
      last30DaysTokens: 120_000,
      last30DaysCostUSD: nil,
      last90DaysTokens: 210_000,
      last90DaysCostUSD: 120.25,
      averageDailyTokens: 4_000,
      averageDailyCostUSD: nil,
      modelSummaries: [
        TokenCostModelSummary(
          modelName: "gpt-5",
          inputTokens: 80_000,
          cacheReadTokens: 32_000,
          outputTokens: 12_000,
          totalTokens: 92_000,
          costUSD: 26.5,
          costShare: nil,
          tokenShare: 0.7666
        ),
        TokenCostModelSummary(
          modelName: "gpt-5-mini",
          inputTokens: 24_000,
          cacheReadTokens: 8_000,
          outputTokens: 4_000,
          totalTokens: 28_000,
          costUSD: 2.8,
          costShare: nil,
          tokenShare: 0.2333
        ),
      ],
      hourly: [
        TokenCostHourlyEntry(hour: 9, inputTokens: 30_000, cacheReadTokens: 11_000, outputTokens: 5_000, totalTokens: 35_000, costUSD: 8.2),
        TokenCostHourlyEntry(hour: 14, inputTokens: 21_000, cacheReadTokens: 7_000, outputTokens: 3_000, totalTokens: 24_000, costUSD: nil),
      ],
      alerts: [
        TokenCostInsight(
          kind: "high_cache_share",
          title: "Strong cache leverage",
          message: "Cache covered 38% of input tokens.",
          severity: "positive"
        ),
        TokenCostInsight(
          kind: "model_concentration",
          title: "Model concentration",
          message: "gpt-5 dominates the current mix.",
          severity: "warning"
        ),
      ],
      narrative: TokenCostNarrative(
        whatChanged: ["30D volume remained elevated with several dense days."],
        whatHelped: ["Cache stayed healthy throughout the window."],
        whatToWatch: ["pricing is incomplete because one model is missing a rate card."]
      ),
      windows: windows,
      hasPartialPricing: true,
      daily: [
        TokenCostDailyEntry(
          date: "2026-04-01",
          inputTokens: 8_000,
          cacheReadTokens: 3_000,
          outputTokens: 1_200,
          totalTokens: 9_200,
          costUSD: nil,
          modelsUsed: ["gpt-5", "gpt-5-mini"],
          modelBreakdowns: [],
          hourlyBreakdowns: []
        ),
      ],
      source: TokenCostSourceSummary(
        mode: .iCloudMerged,
        syncedDeviceCount: 2,
        localDeviceID: "device-a",
        localDeviceName: "Mac A",
        updatedAt: Date(timeIntervalSince1970: 1_775_100_000)
      ),
      localSummary: TokenCostLocalSummary(
        todayTokens: 4_200,
        todayCostUSD: 0.98,
        last30DaysTokens: 38_500,
        last30DaysCostUSD: 9.4
      ),
      accountSummaries: [
        TokenCostAccountSummary(
          accountKey: "managed:acct-1",
          displayName: "alpha@example.com",
          todayTokens: 3_200,
          todayCostUSD: 0.77,
          last30DaysTokens: 72_000,
          last30DaysCostUSD: 18.6,
          sessionCount: 14,
          deviceCount: 2
        ),
        TokenCostAccountSummary(
          accountKey: "local_unknown",
          displayName: "Local / Unknown",
          todayTokens: 1_000,
          todayCostUSD: 0.21,
          last30DaysTokens: 48_000,
          last30DaysCostUSD: nil,
          sessionCount: 8,
          deviceCount: 1
        ),
      ],
      updatedAt: Date(timeIntervalSince1970: 1_775_100_000)
    )
  }
}
