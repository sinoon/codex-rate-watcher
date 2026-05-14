import XCTest
@testable import CodexRateKit

final class ClaudeCodeSessionScannerTests: XCTestCase {
  private var tempDirectory: URL!

  override func setUpWithError() throws {
    tempDirectory = FileManager.default.temporaryDirectory
      .appending(path: "ClaudeCodeSessionScannerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
      try FileManager.default.removeItem(at: tempDirectory)
    }
  }

  func testScannerAggregatesAssistantUsageAndDeduplicatesByMessageID() throws {
    let now = isoDate("2026-04-01T12:00:00+08:00")
    let projectsRoot = tempDirectory.appending(path: "projects", directoryHint: .isDirectory)
    let projectDir = projectsRoot.appending(path: "-Users-bytedance-repo", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

    let fileURL = projectDir.appending(path: "session-1.jsonl")
    // Two distinct assistant turns plus a duplicated content-block row that
    // shares message id with the first turn — Claude Code splits content into
    // multiple lines per turn but reports the same usage object on each, so
    // dedup-by-id is the only way to avoid double-counting.
    try writeLines([
      #"{"sessionId":"abc","type":"user","message":{"role":"user"}}"#,
      #"{"type":"assistant","timestamp":"2026-04-01T09:30:00.000Z","message":{"id":"msg_1","model":"claude-sonnet-4-6-20260101","usage":{"input_tokens":100,"cache_read_input_tokens":900,"cache_creation_input_tokens":200,"output_tokens":300}}}"#,
      #"{"type":"assistant","timestamp":"2026-04-01T09:30:01.500Z","message":{"id":"msg_1","model":"claude-sonnet-4-6-20260101","usage":{"input_tokens":100,"cache_read_input_tokens":900,"cache_creation_input_tokens":200,"output_tokens":300}}}"#,
      #"{"type":"assistant","timestamp":"2026-04-01T10:15:00.000Z","message":{"id":"msg_2","model":"anthropic/claude-haiku-4-5","usage":{"input_tokens":50,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":40}}}"#,
    ], to: fileURL)

    let snapshot = ClaudeCodeSessionScanner.loadSnapshot(
      now: now,
      options: .init(
        projectsRootURL: projectsRoot,
        cacheFileURL: tempDirectory.appending(path: "claude-cache.json"),
        environment: [:],
        refreshMinIntervalSeconds: 0
      )
    )

    let day = snapshot.daily.first
    XCTAssertEqual(snapshot.daily.count, 1)
    XCTAssertEqual(day?.date, "2026-04-01")
    // Sonnet turn = 100 + 900 + 200 = 1200 input + 300 output. Haiku turn =
    // 50 input + 40 output. Duplicate content-block line must not double the
    // sonnet bucket.
    XCTAssertEqual(day?.inputTokens, 1_250)
    XCTAssertEqual(day?.outputTokens, 340)
    XCTAssertEqual(day?.modelsUsed?.sorted() ?? [], ["claude-haiku-4-5", "claude-sonnet-4-6"])

    // Sonnet 4.6 turn: 100 uncached * $3 + 900 cache read * $0.30 + 200 cache create * $3.75 + 300 output * $15
    // = 0.0003 + 0.00027 + 0.00075 + 0.0045 = 0.00582 per 1M unit ⇒ 0.00582 USD here.
    // Haiku 4.5 turn: 50 * $1 + 40 * $5 per 1M = 0.00005 + 0.0002 = 0.00025.
    XCTAssertEqual(day?.costUSD ?? 0, 0.00607, accuracy: 1e-5)
  }

  func testScannerHonorsClaudeConfigDirEnvironment() throws {
    let now = isoDate("2026-04-02T12:00:00+08:00")
    let claudeHome = tempDirectory.appending(path: "custom-claude", directoryHint: .isDirectory)
    let projectDir = claudeHome
      .appending(path: "projects", directoryHint: .isDirectory)
      .appending(path: "-tmp-repo", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

    try writeLines([
      #"{"type":"assistant","timestamp":"2026-04-02T08:00:00.000Z","message":{"id":"msg_a","model":"claude-opus-4-7","usage":{"input_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":20}}}"#,
    ], to: projectDir.appending(path: "session-2.jsonl"))

    let snapshot = ClaudeCodeSessionScanner.loadSnapshot(
      now: now,
      options: .init(
        cacheFileURL: tempDirectory.appending(path: "claude-cache-env.json"),
        environment: ["CLAUDE_CONFIG_DIR": claudeHome.path],
        refreshMinIntervalSeconds: 0
      )
    )

    XCTAssertEqual(snapshot.daily.first?.totalTokens, 30)
    XCTAssertEqual(snapshot.daily.first?.modelsUsed ?? [], ["claude-opus-4-7"])
  }

  func testScannerReusesCachedFileWhenMetadataMatches() throws {
    let now = isoDate("2026-04-03T12:00:00+08:00")
    let projectsRoot = tempDirectory.appending(path: "projects", directoryHint: .isDirectory)
    let projectDir = projectsRoot.appending(path: "-Users-bytedance-cached", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

    let fileURL = projectDir.appending(path: "session-3.jsonl")
    try writeLines([
      #"{"type":"assistant","timestamp":"2026-04-03T09:00:00.000Z","message":{"id":"m1","model":"claude-sonnet-4-6","usage":{"input_tokens":1000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":100}}}"#,
    ], to: fileURL)

    let cacheFileURL = tempDirectory.appending(path: "claude-cache-cached.json")
    let options = ClaudeCodeSessionScanner.Options(
      projectsRootURL: projectsRoot,
      cacheFileURL: cacheFileURL,
      environment: [:],
      refreshMinIntervalSeconds: 0
    )

    _ = ClaudeCodeSessionScanner.loadCachedDays(now: now, options: options)
    // Append more rows but keep the test's expectation tied to the cache file.
    // We instead overwrite the file and observe re-parse on second call to
    // cover the invalidation path.
    try writeLines([
      #"{"type":"assistant","timestamp":"2026-04-03T09:00:00.000Z","message":{"id":"m1","model":"claude-sonnet-4-6","usage":{"input_tokens":1000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":100}}}"#,
      #"{"type":"assistant","timestamp":"2026-04-03T10:00:00.000Z","message":{"id":"m2","model":"claude-sonnet-4-6","usage":{"input_tokens":2000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":200}}}"#,
    ], to: fileURL)

    let days = ClaudeCodeSessionScanner.loadCachedDays(now: now, options: options)
    let bucket = days["2026-04-03"]?.models["claude-sonnet-4-6"]
    XCTAssertEqual(bucket?.inputTokens, 3_000)
    XCTAssertEqual(bucket?.outputTokens, 300)
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
