import XCTest
@testable import CodexRateKit

final class TokenCostScannerTests: XCTestCase {
  private var tempDirectory: URL!

  override func setUpWithError() throws {
    tempDirectory = FileManager.default.temporaryDirectory
      .appending(path: "TokenCostScannerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
      try FileManager.default.removeItem(at: tempDirectory)
    }
  }

  func testScannerAggregatesTotalTokenUsageByDay() throws {
    let now = isoDate("2026-04-01T12:00:00+08:00")
    let codexHome = tempDirectory.appending(path: ".codex", directoryHint: .isDirectory)
    let sessionsDirectory = codexHome
      .appending(path: "sessions", directoryHint: .isDirectory)
      .appending(path: "2026", directoryHint: .isDirectory)
      .appending(path: "04", directoryHint: .isDirectory)
      .appending(path: "01", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

    let fileURL = sessionsDirectory.appending(path: "rollout-2026-04-01-1.jsonl")
    try writeLines([
      #"{"timestamp":"2026-04-01T09:00:00+08:00","type":"session_meta","payload":{"session_id":"session-1"}}"#,
      #"{"timestamp":"2026-04-01T09:00:01+08:00","type":"turn_context","payload":{"model":"gpt-5"}}"#,
      #"{"timestamp":"2026-04-01T09:00:02+08:00","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":100}}}}"#,
      #"{"timestamp":"2026-04-01T09:05:02+08:00","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1500,"cached_input_tokens":300,"output_tokens":150}}}}"#,
    ], to: fileURL)

    let snapshot = TokenCostScanner.loadSnapshot(
      now: now,
      options: .init(
        codexHomeURL: codexHome,
        managedHomesDirectoryURL: tempDirectory.appending(path: "managed-codex-homes", directoryHint: .isDirectory),
        cacheFileURL: tempDirectory.appending(path: "token-cost-cache.json"),
        refreshMinIntervalSeconds: 0
      )
    )

    XCTAssertEqual(snapshot.todayTokens, 1_650)
    XCTAssertEqual(snapshot.last30DaysTokens, 1_650)
    XCTAssertEqual(snapshot.todayCostUSD ?? 0, 0.0030375, accuracy: 0.0000001)
    XCTAssertEqual(snapshot.daily.count, 1)
    XCTAssertEqual(snapshot.daily.first?.date, "2026-04-01")
    XCTAssertEqual(snapshot.daily.first?.inputTokens, 1_500)
    XCTAssertEqual(snapshot.daily.first?.cacheReadTokens, 300)
    XCTAssertEqual(snapshot.daily.first?.outputTokens, 150)
    XCTAssertEqual(snapshot.daily.first?.modelsUsed ?? [], ["gpt-5"])
  }

  func testScannerFallsBackToLastTokenUsage() throws {
    let now = isoDate("2026-04-01T12:00:00+08:00")
    let codexHome = tempDirectory.appending(path: ".codex", directoryHint: .isDirectory)
    let sessionsDirectory = codexHome
      .appending(path: "sessions", directoryHint: .isDirectory)
      .appending(path: "2026", directoryHint: .isDirectory)
      .appending(path: "04", directoryHint: .isDirectory)
      .appending(path: "01", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

    let fileURL = sessionsDirectory.appending(path: "rollout-2026-04-01-2.jsonl")
    try writeLines([
      #"{"timestamp":"2026-04-01T10:00:00+08:00","type":"session_meta","payload":{"session_id":"session-2"}}"#,
      #"{"timestamp":"2026-04-01T10:00:01+08:00","type":"turn_context","payload":{"model":"gpt-5-mini"}}"#,
      #"{"timestamp":"2026-04-01T10:00:02+08:00","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":800,"cached_input_tokens":300,"output_tokens":40}}}}"#,
    ], to: fileURL)

    let snapshot = TokenCostScanner.loadSnapshot(
      now: now,
      options: .init(
        codexHomeURL: codexHome,
        managedHomesDirectoryURL: tempDirectory.appending(path: "managed-codex-homes", directoryHint: .isDirectory),
        cacheFileURL: tempDirectory.appending(path: "token-cost-cache.json"),
        refreshMinIntervalSeconds: 0
      )
    )

    XCTAssertEqual(snapshot.todayTokens, 840)
    XCTAssertEqual(snapshot.todayCostUSD ?? 0, 0.0002125, accuracy: 0.0000001)
    XCTAssertEqual(snapshot.daily.first?.cacheReadTokens, 300)
  }

  func testScannerPricesGPT55Sessions() throws {
    let now = isoDate("2026-04-01T12:00:00+08:00")
    let codexHome = tempDirectory.appending(path: ".codex", directoryHint: .isDirectory)
    let sessionsDirectory = codexHome
      .appending(path: "sessions", directoryHint: .isDirectory)
      .appending(path: "2026", directoryHint: .isDirectory)
      .appending(path: "04", directoryHint: .isDirectory)
      .appending(path: "01", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

    let fileURL = sessionsDirectory.appending(path: "rollout-2026-04-01-gpt55.jsonl")
    try writeLines([
      #"{"timestamp":"2026-04-01T11:00:00+08:00","type":"session_meta","payload":{"session_id":"session-gpt55"}}"#,
      #"{"timestamp":"2026-04-01T11:00:01+08:00","type":"turn_context","payload":{"model":"gpt-5.5"}}"#,
      #"{"timestamp":"2026-04-01T11:00:02+08:00","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000000,"cached_input_tokens":400000,"output_tokens":10000}}}}"#,
    ], to: fileURL)

    let snapshot = TokenCostScanner.loadSnapshot(
      now: now,
      options: .init(
        codexHomeURL: codexHome,
        managedHomesDirectoryURL: tempDirectory.appending(path: "managed-codex-homes", directoryHint: .isDirectory),
        cacheFileURL: tempDirectory.appending(path: "token-cost-cache.json"),
        refreshMinIntervalSeconds: 0
      )
    )

    XCTAssertEqual(snapshot.todayTokens, 1_010_000)
    XCTAssertEqual(snapshot.todayCostUSD ?? 0, 3.5, accuracy: 0.0000001)
    XCTAssertFalse(snapshot.hasPartialPricing)
    XCTAssertEqual(snapshot.modelSummaries.map(\.modelName), ["gpt-5.5"])
    XCTAssertEqual(snapshot.modelSummaries.first?.costUSD ?? 0, 3.5, accuracy: 0.0000001)
  }

  func testScannerIncludesManagedHomesAndDeduplicatesSessionIDs() throws {
    let now = isoDate("2026-04-01T12:00:00+08:00")
    let codexHome = tempDirectory.appending(path: ".codex", directoryHint: .isDirectory)
    let liveSessions = codexHome
      .appending(path: "sessions", directoryHint: .isDirectory)
      .appending(path: "2026", directoryHint: .isDirectory)
      .appending(path: "04", directoryHint: .isDirectory)
      .appending(path: "01", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: liveSessions, withIntermediateDirectories: true)

    let managedHomesRoot = tempDirectory.appending(path: "managed-codex-homes", directoryHint: .isDirectory)
    let managedSessions = managedHomesRoot
      .appending(path: "acct-1", directoryHint: .isDirectory)
      .appending(path: "sessions", directoryHint: .isDirectory)
      .appending(path: "2026", directoryHint: .isDirectory)
      .appending(path: "04", directoryHint: .isDirectory)
      .appending(path: "01", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: managedSessions, withIntermediateDirectories: true)

    try writeLines([
      #"{"timestamp":"2026-04-01T08:00:00+08:00","type":"session_meta","payload":{"session_id":"dup-session"}}"#,
      #"{"timestamp":"2026-04-01T08:00:01+08:00","type":"turn_context","payload":{"model":"gpt-5"}}"#,
      #"{"timestamp":"2026-04-01T08:00:02+08:00","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":0,"output_tokens":10}}}}"#,
    ], to: liveSessions.appending(path: "rollout-live.jsonl"))

    try writeLines([
      #"{"timestamp":"2026-04-01T08:00:00+08:00","type":"session_meta","payload":{"session_id":"dup-session"}}"#,
      #"{"timestamp":"2026-04-01T08:00:01+08:00","type":"turn_context","payload":{"model":"gpt-5"}}"#,
      #"{"timestamp":"2026-04-01T08:00:02+08:00","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":0,"output_tokens":10}}}}"#,
    ], to: managedSessions.appending(path: "rollout-managed.jsonl"))

    try writeLines([
      #"{"timestamp":"2026-04-01T11:00:02+08:00","type":"session_meta","payload":{"session_id":"managed-session"}}"#,
      #"{"timestamp":"2026-04-01T11:00:03+08:00","type":"turn_context","payload":{"model":"gpt-5-mini"}}"#,
      #"{"timestamp":"2026-04-01T11:00:04+08:00","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":500,"cached_input_tokens":100,"output_tokens":20}}}}"#,
    ], to: managedSessions.appending(path: "rollout-managed-2.jsonl"))

    let snapshot = TokenCostScanner.loadSnapshot(
      now: now,
      options: .init(
        codexHomeURL: codexHome,
        managedHomesDirectoryURL: managedHomesRoot,
        cacheFileURL: tempDirectory.appending(path: "token-cost-cache.json"),
        refreshMinIntervalSeconds: 0
      )
    )

    XCTAssertEqual(snapshot.todayTokens, 1_530)
    XCTAssertEqual(snapshot.daily.count, 1)
    XCTAssertEqual(snapshot.daily.first?.modelsUsed ?? [], ["gpt-5", "gpt-5-mini"])
  }

  func testScannerBuildsWindowSummariesModelLeaderboardsAndHourlyBuckets() throws {
    let now = isoDate("2026-04-01T12:00:00+08:00")
    let codexHome = tempDirectory.appending(path: ".codex", directoryHint: .isDirectory)

    let aprilDay = codexHome
      .appending(path: "sessions", directoryHint: .isDirectory)
      .appending(path: "2026", directoryHint: .isDirectory)
      .appending(path: "04", directoryHint: .isDirectory)
      .appending(path: "01", directoryHint: .isDirectory)
    let marchDay = codexHome
      .appending(path: "sessions", directoryHint: .isDirectory)
      .appending(path: "2026", directoryHint: .isDirectory)
      .appending(path: "03", directoryHint: .isDirectory)
      .appending(path: "28", directoryHint: .isDirectory)
    let januaryDay = codexHome
      .appending(path: "sessions", directoryHint: .isDirectory)
      .appending(path: "2026", directoryHint: .isDirectory)
      .appending(path: "01", directoryHint: .isDirectory)
      .appending(path: "15", directoryHint: .isDirectory)

    try FileManager.default.createDirectory(at: aprilDay, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: marchDay, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: januaryDay, withIntermediateDirectories: true)

    try writeLines([
      #"{"timestamp":"2026-04-01T09:00:00+08:00","type":"session_meta","payload":{"session_id":"session-30d-gpt5"}}"#,
      #"{"timestamp":"2026-04-01T09:00:01+08:00","type":"turn_context","payload":{"model":"gpt-5"}}"#,
      #"{"timestamp":"2026-04-01T09:00:02+08:00","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":100}}}}"#,
      #"{"timestamp":"2026-04-01T14:30:00+08:00","type":"session_meta","payload":{"session_id":"session-30d-mini"}}"#,
      #"{"timestamp":"2026-04-01T14:30:01+08:00","type":"turn_context","payload":{"model":"gpt-5-mini"}}"#,
      #"{"timestamp":"2026-04-01T14:30:02+08:00","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":500,"cached_input_tokens":100,"output_tokens":50}}}}"#,
    ], to: aprilDay.appending(path: "rollout-2026-04-01.jsonl"))

    try writeLines([
      #"{"timestamp":"2026-03-28T09:15:00+08:00","type":"session_meta","payload":{"session_id":"session-7d-gpt5"}}"#,
      #"{"timestamp":"2026-03-28T09:15:01+08:00","type":"turn_context","payload":{"model":"gpt-5"}}"#,
      #"{"timestamp":"2026-03-28T09:15:02+08:00","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":2000,"cached_input_tokens":1000,"output_tokens":200}}}}"#,
    ], to: marchDay.appending(path: "rollout-2026-03-28.jsonl"))

    try writeLines([
      #"{"timestamp":"2026-01-15T22:00:00+08:00","type":"session_meta","payload":{"session_id":"session-90d-nano"}}"#,
      #"{"timestamp":"2026-01-15T22:00:01+08:00","type":"turn_context","payload":{"model":"gpt-5-nano"}}"#,
      #"{"timestamp":"2026-01-15T22:00:02+08:00","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":3000,"cached_input_tokens":1000,"output_tokens":300}}}}"#,
    ], to: januaryDay.appending(path: "rollout-2026-01-15.jsonl"))

    let snapshot = TokenCostScanner.loadSnapshot(
      now: now,
      options: .init(
        codexHomeURL: codexHome,
        managedHomesDirectoryURL: tempDirectory.appending(path: "managed-codex-homes", directoryHint: .isDirectory),
        cacheFileURL: tempDirectory.appending(path: "token-cost-cache.json"),
        refreshMinIntervalSeconds: 0
      )
    )

    XCTAssertEqual(snapshot.todayTokens, 1_650)
    XCTAssertEqual(snapshot.last7DaysTokens, 3_850)
    XCTAssertEqual(snapshot.last30DaysTokens, 3_850)
    XCTAssertEqual(snapshot.last90DaysTokens, 7_150)
    XCTAssertEqual(snapshot.last7DaysCostUSD ?? 0, 0.0056025, accuracy: 0.0000001)
    XCTAssertEqual(snapshot.last90DaysCostUSD ?? 0, 0.0058275, accuracy: 0.0000001)
    XCTAssertEqual(snapshot.averageDailyTokens ?? 0, 128.3333333, accuracy: 0.0001)
    XCTAssertEqual(snapshot.averageDailyCostUSD ?? 0, 0.00018675, accuracy: 0.0000001)

    let sevenDayWindow = try XCTUnwrap(snapshot.windowSummary(days: 7))
    XCTAssertEqual(sevenDayWindow.totalTokens, 3_850)
    XCTAssertEqual(sevenDayWindow.activeDayCount, 2)
    XCTAssertEqual(sevenDayWindow.dominantModelName, "gpt-5")
    XCTAssertEqual(sevenDayWindow.cacheShare ?? 0, 0.3714285, accuracy: 0.0001)

    let thirtyDayModels = snapshot.modelSummaries
    XCTAssertEqual(thirtyDayModels.map(\.modelName), ["gpt-5", "gpt-5-mini"])
    XCTAssertEqual(thirtyDayModels.first?.inputTokens, 3_000)
    XCTAssertEqual(thirtyDayModels.first?.cacheReadTokens, 1_200)
    XCTAssertEqual(thirtyDayModels.first?.outputTokens, 300)
    XCTAssertEqual(thirtyDayModels.first?.totalTokens, 3_300)
    XCTAssertEqual(thirtyDayModels.first?.costUSD ?? 0, 0.0054, accuracy: 0.0000001)
    XCTAssertEqual(thirtyDayModels.first?.costShare ?? 0, 0.9638545, accuracy: 0.0001)
    XCTAssertEqual(thirtyDayModels.first?.tokenShare ?? 0, 0.8571428, accuracy: 0.0001)

    XCTAssertEqual(snapshot.hourly.map(\.hour), [9, 14])
    XCTAssertEqual(snapshot.hourly.first?.totalTokens, 3_300)
    XCTAssertEqual(snapshot.hourly.first?.costUSD ?? 0, 0.0054, accuracy: 0.0000001)

    XCTAssertTrue(snapshot.alerts.contains { $0.kind == "high_cache_share" })
    XCTAssertTrue(snapshot.alerts.contains { $0.kind == "model_concentration" })
    XCTAssertTrue(snapshot.narrative.whatChanged.contains { $0.contains("30D") })
    XCTAssertTrue(snapshot.narrative.whatHelped.contains { $0.contains("cache") })
    XCTAssertTrue(snapshot.narrative.whatToWatch.contains { $0.contains("gpt-5") })
  }

  func testScannerSurfacesPartialPricingAcrossSnapshotAlertsAndNarrative() throws {
    let now = isoDate("2026-04-01T12:00:00+08:00")
    let codexHome = tempDirectory.appending(path: ".codex", directoryHint: .isDirectory)
    let sessionsDirectory = codexHome
      .appending(path: "sessions", directoryHint: .isDirectory)
      .appending(path: "2026", directoryHint: .isDirectory)
      .appending(path: "04", directoryHint: .isDirectory)
      .appending(path: "01", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

    try writeLines([
      #"{"timestamp":"2026-04-01T09:00:00+08:00","type":"session_meta","payload":{"session_id":"session-known"}}"#,
      #"{"timestamp":"2026-04-01T09:00:01+08:00","type":"turn_context","payload":{"model":"gpt-5"}}"#,
      #"{"timestamp":"2026-04-01T09:00:02+08:00","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":0,"output_tokens":100}}}}"#,
      #"{"timestamp":"2026-04-01T10:00:00+08:00","type":"session_meta","payload":{"session_id":"session-unknown"}}"#,
      #"{"timestamp":"2026-04-01T10:00:01+08:00","type":"turn_context","payload":{"model":"mystery-model"}}"#,
      #"{"timestamp":"2026-04-01T10:00:02+08:00","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":300,"cached_input_tokens":0,"output_tokens":30}}}}"#,
    ], to: sessionsDirectory.appending(path: "rollout-partial-pricing.jsonl"))

    let snapshot = TokenCostScanner.loadSnapshot(
      now: now,
      options: .init(
        codexHomeURL: codexHome,
        managedHomesDirectoryURL: tempDirectory.appending(path: "managed-codex-homes", directoryHint: .isDirectory),
        cacheFileURL: tempDirectory.appending(path: "token-cost-cache.json"),
        refreshMinIntervalSeconds: 0
      )
    )

    XCTAssertTrue(snapshot.hasPartialPricing)
    XCTAssertNil(snapshot.last30DaysCostUSD)
    XCTAssertEqual(snapshot.last30DaysTokens, 1_430)
    XCTAssertNil(snapshot.modelSummaries.first { $0.modelName == "mystery-model" }?.costShare)
    XCTAssertTrue(snapshot.alerts.contains { $0.kind == "partial_pricing" })
    XCTAssertTrue(snapshot.narrative.whatToWatch.contains { $0.contains("pricing") })
  }

  func testScannerExcludesRapidCompactionReplayLogs() throws {
    let now = isoDate("2026-04-01T12:00:00+08:00")
    let codexHome = tempDirectory.appending(path: ".codex", directoryHint: .isDirectory)
    let sessionsDirectory = codexHome
      .appending(path: "sessions", directoryHint: .isDirectory)
      .appending(path: "2026", directoryHint: .isDirectory)
      .appending(path: "04", directoryHint: .isDirectory)
      .appending(path: "01", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

    let normalFile = sessionsDirectory.appending(path: "rollout-normal.jsonl")
    try writeLines([
      #"{"timestamp":"2026-04-01T09:00:00+08:00","type":"session_meta","payload":{"session_id":"normal-session"}}"#,
      #"{"timestamp":"2026-04-01T09:00:01+08:00","type":"turn_context","payload":{"model":"gpt-5"}}"#,
      #"{"timestamp":"2026-04-01T09:00:02+08:00","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":100}}}}"#,
    ], to: normalFile)

    var replayLines = [
      #"{"timestamp":"2026-04-01T10:00:00+08:00","type":"session_meta","payload":{"session_id":"replay-session"}}"#,
      #"{"timestamp":"2026-04-01T10:00:00+08:00","type":"turn_context","payload":{"model":"gpt-5.4"}}"#,
    ]
    for index in 1...1_001 {
      if index % 5 == 0 {
        replayLines.append(#"{"timestamp":"2026-04-01T10:00:00+08:00","type":"compacted","payload":{}}"#)
        replayLines.append(#"{"timestamp":"2026-04-01T10:00:00+08:00","type":"event_msg","payload":{"type":"context_compacted"}}"#)
      }
      replayLines.append(
        #"{"timestamp":"2026-04-01T10:00:00+08:00","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(index * 100_000),"cached_input_tokens":\#(index * 90_000),"output_tokens":\#(index * 10)}}}}"#
      )
    }
    let replayFile = sessionsDirectory.appending(path: "rollout-replay.jsonl")
    try writeLines(replayLines, to: replayFile)

    let cacheFileURL = tempDirectory.appending(path: "token-cost-cache.json")
    let snapshot = TokenCostScanner.loadSnapshot(
      now: now,
      options: .init(
        codexHomeURL: codexHome,
        managedHomesDirectoryURL: tempDirectory.appending(path: "managed-codex-homes", directoryHint: .isDirectory),
        cacheFileURL: cacheFileURL,
        refreshMinIntervalSeconds: 0
      )
    )

    XCTAssertEqual(snapshot.todayTokens, 1_100)
    XCTAssertEqual(snapshot.last30DaysTokens, 1_100)

    let cache = TokenCostCacheStore.load(from: cacheFileURL)
    let replayCacheFile = cache.files.values.first { $0.path.hasSuffix("/rollout-replay.jsonl") }
    let replayDiagnostics = replayCacheFile?.diagnostics
    XCTAssertEqual(replayDiagnostics?.exclusionReason, "rapid_compaction_replay")
    XCTAssertTrue(replayCacheFile?.days.isEmpty ?? false)
  }

  func testScannerKeepsLongRunningHighVolumeSessions() throws {
    let now = isoDate("2026-04-03T12:00:00+08:00")
    let codexHome = tempDirectory.appending(path: ".codex", directoryHint: .isDirectory)
    let sessionsDirectory = codexHome
      .appending(path: "sessions", directoryHint: .isDirectory)
      .appending(path: "2026", directoryHint: .isDirectory)
      .appending(path: "04", directoryHint: .isDirectory)
      .appending(path: "01", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let start = isoDate("2026-04-01T00:00:00+08:00")

    var lines = [
      #"{"timestamp":"2026-04-01T00:00:00+08:00","type":"session_meta","payload":{"session_id":"long-session"}}"#,
      #"{"timestamp":"2026-04-01T00:00:00+08:00","type":"turn_context","payload":{"model":"gpt-5.4"}}"#,
    ]
    for index in 1...1_001 {
      let timestamp = formatter.string(from: start.addingTimeInterval(TimeInterval(index * 120)))
      if index % 5 == 0 {
        lines.append(#"{"timestamp":"\#(timestamp)","type":"compacted","payload":{}}"#)
        lines.append(#"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"context_compacted"}}"#)
      }
      lines.append(
        #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(index * 2_500_000),"cached_input_tokens":\#(index * 2_000_000),"output_tokens":\#(index * 10_000)}}}}"#
      )
    }

    let fileURL = sessionsDirectory.appending(path: "rollout-long-session.jsonl")
    try writeLines(lines, to: fileURL)

    let cacheFileURL = tempDirectory.appending(path: "token-cost-cache.json")
    let snapshot = TokenCostScanner.loadSnapshot(
      now: now,
      options: .init(
        codexHomeURL: codexHome,
        managedHomesDirectoryURL: tempDirectory.appending(path: "managed-codex-homes", directoryHint: .isDirectory),
        cacheFileURL: cacheFileURL,
        refreshMinIntervalSeconds: 0
      )
    )

    XCTAssertEqual(snapshot.last30DaysTokens, 2_512_510_000)

    let cache = TokenCostCacheStore.load(from: cacheFileURL)
    let cachedFile = cache.files.values.first { $0.path.hasSuffix("/rollout-long-session.jsonl") }
    XCTAssertNil(cachedFile?.diagnostics?.exclusionReason)
    XCTAssertFalse(cachedFile?.days.isEmpty ?? true)
  }

  private func writeLines(_ lines: [String], to fileURL: URL) throws {
    let payload = lines.joined(separator: "\n") + "\n"
    try payload.write(to: fileURL, atomically: true, encoding: .utf8)
  }

  private func isoDate(_ string: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: string) {
      return date
    }

    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: string)!
  }
}
