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
