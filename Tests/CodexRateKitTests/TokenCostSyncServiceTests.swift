import XCTest
@testable import CodexRateKit

final class TokenCostSyncServiceTests: XCTestCase {
  private var tempDirectory: URL!

  override func setUpWithError() throws {
    tempDirectory = FileManager.default.temporaryDirectory
      .appending(path: "TokenCostSyncServiceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
      try FileManager.default.removeItem(at: tempDirectory)
    }
  }

  func testDeviceStoreReturnsStableIdentity() throws {
    let fileURL = tempDirectory.appending(path: "token-cost-device.json")
    let store = TokenCostDeviceStore(fileURL: fileURL)

    let first = try store.loadOrCreateDevice()
    let second = try store.loadOrCreateDevice()

    XCTAssertEqual(first.deviceID, second.deviceID)
    XCTAssertEqual(first.deviceName, second.deviceName)
    XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
  }

  func testLedgerStoreRoundTripsDeviceLedger() throws {
    let directoryURL = tempDirectory.appending(path: "ledgers", directoryHint: .isDirectory)
    let store = TokenCostLedgerStore(localLedgerFileURL: tempDirectory.appending(path: "local.json"), iCloudLedgerDirectoryURL: directoryURL)

    let ledger = TokenCostSyncLedger(
      version: 1,
      device: TokenCostSyncDevice(
        deviceID: "device-a",
        deviceName: "Mac A",
        createdAt: isoDate("2026-04-13T10:00:00+08:00")
      ),
      updatedAt: isoDate("2026-04-13T10:05:00+08:00"),
      sessions: [
        TokenCostSyncSession(
          dedupeKey: "session:abc",
          sessionID: "abc",
          accountKey: "managed:acct-1",
          accountDisplayName: "alpha@example.com",
          sourceKind: .managed,
          days: [
            "2026-04-13": TokenCostCachedDay(
              models: [
                "gpt-5": TokenCostBucket(inputTokens: 1000, cacheReadTokens: 200, outputTokens: 100),
              ]
            ),
          ]
        ),
      ]
    )

    try store.saveLocalLedger(ledger)
    try store.saveLedgerToICloud(ledger)
    let loadedLocal = try XCTUnwrap(store.loadLocalLedger())
    let loadedCloud = try XCTUnwrap(store.loadICloudLedgers().first)

    XCTAssertEqual(loadedLocal, ledger)
    XCTAssertEqual(loadedCloud, ledger)
  }

  func testSyncServiceMergesDeviceLedgersIntoAllDeviceSnapshot() throws {
    let iCloudDirectoryURL = tempDirectory.appending(path: "icloud/token-ledgers", directoryHint: .isDirectory)
    let ledgerStore = TokenCostLedgerStore(
      localLedgerFileURL: tempDirectory.appending(path: "local-ledger.json"),
      iCloudLedgerDirectoryURL: iCloudDirectoryURL
    )
    let service = TokenCostSyncService(ledgerStore: ledgerStore)

    let now = isoDate("2026-04-13T12:00:00+08:00")
    let localSnapshot = TokenCostSnapshot(
      todayTokens: 1_100,
      todayCostUSD: 0.22,
      last7DaysTokens: 1_100,
      last7DaysCostUSD: 0.22,
      last30DaysTokens: 1_100,
      last30DaysCostUSD: 0.22,
      daily: [
        TokenCostDailyEntry(
          date: "2026-04-13",
          inputTokens: 1_000,
          cacheReadTokens: 200,
          outputTokens: 100,
          totalTokens: 1_100,
          costUSD: 0.22,
          modelsUsed: ["gpt-5"],
          modelBreakdowns: [],
          hourlyBreakdowns: []
        ),
      ],
      updatedAt: now
    )

    let device = TokenCostSyncDevice(
      deviceID: "device-a",
      deviceName: "Mac A",
      createdAt: isoDate("2026-04-13T09:00:00+08:00")
    )
    let localLedger = TokenCostSyncLedger(
      version: 1,
      device: device,
      updatedAt: now,
      sessions: [
        TokenCostSyncSession(
          dedupeKey: "session:local-1",
          sessionID: "local-1",
          accountKey: "local_unknown",
          accountDisplayName: "Local / Unknown",
          sourceKind: .localUnknown,
          days: [
            "2026-04-13": TokenCostCachedDay(
              models: [
                "gpt-5": TokenCostBucket(inputTokens: 1000, cacheReadTokens: 200, outputTokens: 100),
              ]
            ),
          ]
        ),
      ]
    )
    let remoteLedger = TokenCostSyncLedger(
      version: 1,
      device: TokenCostSyncDevice(
        deviceID: "device-b",
        deviceName: "Mac B",
        createdAt: isoDate("2026-04-12T08:00:00+08:00")
      ),
      updatedAt: now,
      sessions: [
        TokenCostSyncSession(
          dedupeKey: "session:managed-1",
          sessionID: "managed-1",
          accountKey: "managed:acct-1",
          accountDisplayName: "alpha@example.com",
          sourceKind: .managed,
          days: [
            "2026-04-13": TokenCostCachedDay(
              models: [
                "gpt-5-mini": TokenCostBucket(inputTokens: 400, cacheReadTokens: 100, outputTokens: 40),
              ]
            ),
          ]
        ),
      ]
    )

    try ledgerStore.saveLedgerToICloud(localLedger)
    try ledgerStore.saveLedgerToICloud(remoteLedger)

    let merged = try service.mergeSnapshot(
      localSnapshot: localSnapshot,
      localLedger: localLedger,
      now: now
    )

    XCTAssertEqual(merged.todayTokens, 1_540)
    XCTAssertEqual(merged.last30DaysTokens, 1_540)
    XCTAssertEqual(merged.localSummary?.todayTokens, 1_100)
    XCTAssertEqual(merged.source?.mode, .iCloudMerged)
    XCTAssertEqual(merged.source?.syncedDeviceCount, 2)
    XCTAssertEqual(merged.accountSummaries.map(\.displayName), ["Local / Unknown", "alpha@example.com"])
    XCTAssertEqual(merged.accountSummaries.first?.last30DaysTokens, 1_100)
    XCTAssertEqual(merged.accountSummaries.last?.last30DaysTokens, 440)
  }

  func testBuildLocalLedgerMapsManagedAndLocalSessionsFromCache() throws {
    let cacheFileURL = tempDirectory.appending(path: "token-cost-cache.json")
    let service = TokenCostSyncService(ledgerStore: TokenCostLedgerStore(
      localLedgerFileURL: tempDirectory.appending(path: "local-ledger.json"),
      iCloudLedgerDirectoryURL: tempDirectory.appending(path: "icloud", directoryHint: .isDirectory)
    ))
    let managedHome = tempDirectory.appending(path: "managed-codex-homes/acct-1", directoryHint: .isDirectory)
    let managedFile = managedHome.appending(path: "sessions/2026/04/13/managed.jsonl")
    let localFile = tempDirectory.appending(path: ".codex/sessions/2026/04/13/local.jsonl")

    let cache = TokenCostCache(
      lastScanUnixMilliseconds: 1_000,
      files: [
        managedFile.path: TokenCostCachedFile(
          path: managedFile.path,
          modifiedAtUnixMilliseconds: 1_000,
          size: 100,
          sessionID: "managed-1",
          lastModel: "gpt-5",
          lastTotals: nil,
          days: [
            "2026-04-13": TokenCostCachedDay(
              models: ["gpt-5": TokenCostBucket(inputTokens: 500, cacheReadTokens: 100, outputTokens: 50)]
            ),
          ]
        ),
        localFile.path: TokenCostCachedFile(
          path: localFile.path,
          modifiedAtUnixMilliseconds: 1_000,
          size: 100,
          sessionID: "local-1",
          lastModel: "gpt-5-mini",
          lastTotals: nil,
          days: [
            "2026-04-13": TokenCostCachedDay(
              models: ["gpt-5-mini": TokenCostBucket(inputTokens: 200, cacheReadTokens: 50, outputTokens: 20)]
            ),
          ]
        ),
      ],
      days: [:]
    )
    TokenCostCacheStore.save(cache, to: cacheFileURL)

    let ledger = try service.buildLocalLedger(
      device: TokenCostSyncDevice(deviceID: "device-a", deviceName: "Mac A", createdAt: isoDate("2026-04-13T09:00:00+08:00")),
      cacheFileURL: cacheFileURL,
      managedAccounts: ManagedCodexAccountSet(accounts: [
        ManagedCodexAccount(
          id: UUID(),
          email: "alpha@example.com",
          managedHomePath: managedHome.path,
          accountID: "acct-1",
          createdAt: isoDate("2026-04-13T08:00:00+08:00"),
          updatedAt: isoDate("2026-04-13T08:00:00+08:00"),
          lastAuthenticatedAt: isoDate("2026-04-13T08:00:00+08:00")
        ),
      ]),
      now: isoDate("2026-04-13T12:00:00+08:00")
    )

    XCTAssertEqual(ledger.sessions.count, 2)
    XCTAssertEqual(ledger.sessions.first(where: { $0.sessionID == "managed-1" })?.accountDisplayName, "alpha@example.com")
    XCTAssertEqual(ledger.sessions.first(where: { $0.sessionID == "managed-1" })?.sourceKind, .managed)
    XCTAssertEqual(ledger.sessions.first(where: { $0.sessionID == "local-1" })?.accountDisplayName, "Local / Unknown")
    XCTAssertEqual(ledger.sessions.first(where: { $0.sessionID == "local-1" })?.sourceKind, .localUnknown)
  }

  func testSynchronizedSnapshotReturnsLocalOnlyMetadataWhenNoRemoteLedgerExists() throws {
    let cacheFileURL = tempDirectory.appending(path: "token-cost-cache.json")
    let ledgerStore = TokenCostLedgerStore(
      localLedgerFileURL: tempDirectory.appending(path: "local-ledger.json"),
      iCloudLedgerDirectoryURL: tempDirectory.appending(path: "icloud/token-ledgers", directoryHint: .isDirectory)
    )
    let service = TokenCostSyncService(ledgerStore: ledgerStore)
    let now = isoDate("2026-04-13T12:00:00+08:00")

    let cache = TokenCostCache(
      lastScanUnixMilliseconds: 1_000,
      files: [
        tempDirectory.appending(path: ".codex/sessions/2026/04/13/local.jsonl").path: TokenCostCachedFile(
          path: tempDirectory.appending(path: ".codex/sessions/2026/04/13/local.jsonl").path,
          modifiedAtUnixMilliseconds: 1_000,
          size: 100,
          sessionID: "local-1",
          lastModel: "gpt-5",
          lastTotals: nil,
          days: [
            "2026-04-13": TokenCostCachedDay(
              models: ["gpt-5": TokenCostBucket(inputTokens: 900, cacheReadTokens: 100, outputTokens: 90)]
            ),
          ]
        ),
      ],
      days: [
        "2026-04-13": TokenCostCachedDay(
          models: ["gpt-5": TokenCostBucket(inputTokens: 900, cacheReadTokens: 100, outputTokens: 90)]
        ),
      ]
    )
    TokenCostCacheStore.save(cache, to: cacheFileURL)

    let localSnapshot = TokenCostSnapshotBuilder.buildSnapshot(days: cache.days, now: now)
    let merged = try service.synchronizedSnapshot(
      localSnapshot: localSnapshot,
      device: TokenCostSyncDevice(deviceID: "device-a", deviceName: "Mac A", createdAt: now),
      cacheFileURL: cacheFileURL,
      managedAccounts: ManagedCodexAccountSet(accounts: []),
      mirrorToICloud: false,
      now: now
    )

    XCTAssertEqual(merged.source?.mode, .localOnly)
    XCTAssertEqual(merged.source?.syncedDeviceCount, 1)
    XCTAssertEqual(merged.localSummary?.todayTokens, 990)
    XCTAssertEqual(merged.todayTokens, 990)
    XCTAssertEqual(merged.accountSummaries.map(\.displayName), ["Local / Unknown"])
  }

  private func isoDate(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)!
  }
}
