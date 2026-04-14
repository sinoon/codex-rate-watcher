import CryptoKit
import Foundation

struct TokenCostSyncService: @unchecked Sendable {
  private let ledgerStore: TokenCostLedgerStore

  init(ledgerStore: TokenCostLedgerStore = TokenCostLedgerStore()) {
    self.ledgerStore = ledgerStore
  }

  func buildLocalLedger(
    device: TokenCostSyncDevice,
    cacheFileURL: URL = AppPaths.tokenCostCacheFile,
    managedAccounts: ManagedCodexAccountSet,
    now: Date = Date()
  ) throws -> TokenCostSyncLedger {
    let cache = TokenCostCacheStore.load(from: cacheFileURL)
    let sessions = cache.files.values
      .filter { !$0.days.isEmpty }
      .map { cachedFile in
        let account = managedAccount(forPath: cachedFile.path, accounts: managedAccounts.accounts)
        let accountKey: String
        let accountDisplayName: String
        let sourceKind: TokenCostSyncSourceKind

        if let account {
          let normalizedEmail = account.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
          let normalizedAccountID = account.accountID?.trimmingCharacters(in: .whitespacesAndNewlines)
          accountKey = normalizedAccountID.map { "managed:\($0)" } ?? "managed:\(normalizedEmail)"
          accountDisplayName = normalizedEmail
          sourceKind = .managed
        } else {
          accountKey = "local_unknown"
          accountDisplayName = "Local / Unknown"
          sourceKind = .localUnknown
        }

        let dedupeKey: String
        if let sessionID = cachedFile.sessionID, !sessionID.isEmpty {
          dedupeKey = "session:\(sessionID)"
        } else {
          dedupeKey = "file:\(device.deviceID):\(stableHash(cachedFile.path))"
        }

        return TokenCostSyncSession(
          dedupeKey: dedupeKey,
          sessionID: cachedFile.sessionID,
          accountKey: accountKey,
          accountDisplayName: accountDisplayName,
          sourceKind: sourceKind,
          days: cachedFile.days
        )
      }
      .sorted { lhs, rhs in
        lhs.dedupeKey < rhs.dedupeKey
      }

    return TokenCostSyncLedger(
      device: device,
      updatedAt: now,
      sessions: sessions
    )
  }

  func synchronizedSnapshot(
    localSnapshot: TokenCostSnapshot,
    device: TokenCostSyncDevice,
    cacheFileURL: URL = AppPaths.tokenCostCacheFile,
    managedAccounts: ManagedCodexAccountSet,
    mirrorToICloud: Bool = true,
    now: Date = Date()
  ) throws -> TokenCostSnapshot {
    let localLedger = try buildLocalLedger(
      device: device,
      cacheFileURL: cacheFileURL,
      managedAccounts: managedAccounts,
      now: now
    )

    try? ledgerStore.saveLocalLedger(localLedger)
    if mirrorToICloud {
      try? ledgerStore.saveLedgerToICloud(localLedger)
    }

    return try mergeSnapshot(localSnapshot: localSnapshot, localLedger: localLedger, now: now)
  }

  func mergeSnapshot(
    localSnapshot: TokenCostSnapshot,
    localLedger: TokenCostSyncLedger,
    now: Date = Date()
  ) throws -> TokenCostSnapshot {
    let allLedgers = deduplicateLedgers(ledgerStore.loadICloudLedgers() + [localLedger])
    let mergedSessions = mergedSessions(from: allLedgers)

    var mergedDays: [String: TokenCostCachedDay] = [:]
    for session in mergedSessions.values {
      merge(days: session.days, into: &mergedDays)
    }

    let source = TokenCostSourceSummary(
      mode: allLedgers.count > 1 ? .iCloudMerged : .localOnly,
      syncedDeviceCount: allLedgers.count,
      localDeviceID: localLedger.device.deviceID,
      localDeviceName: localLedger.device.deviceName,
      updatedAt: allLedgers.map(\.updatedAt).max()
    )
    let localSummary = TokenCostLocalSummary(
      todayTokens: localSnapshot.todayTokens,
      todayCostUSD: localSnapshot.todayCostUSD,
      last7DaysTokens: localSnapshot.last7DaysTokens,
      last7DaysCostUSD: localSnapshot.last7DaysCostUSD,
      last30DaysTokens: localSnapshot.last30DaysTokens,
      last30DaysCostUSD: localSnapshot.last30DaysCostUSD
    )

    return TokenCostSnapshotBuilder.buildSnapshot(
      days: mergedDays,
      now: now,
      source: source,
      localSummary: localSummary,
      accountSummaries: buildAccountSummaries(from: allLedgers, now: now)
    )
  }

  private func deduplicateLedgers(_ ledgers: [TokenCostSyncLedger]) -> [TokenCostSyncLedger] {
    var bestByDevice: [String: TokenCostSyncLedger] = [:]

    for ledger in ledgers {
      let existing = bestByDevice[ledger.device.deviceID]
      if existing == nil || existing!.updatedAt < ledger.updatedAt {
        bestByDevice[ledger.device.deviceID] = ledger
      }
    }

    return bestByDevice.values.sorted { lhs, rhs in
      if lhs.updatedAt != rhs.updatedAt {
        return lhs.updatedAt > rhs.updatedAt
      }
      return lhs.device.deviceID < rhs.device.deviceID
    }
  }

  private func managedAccount(forPath path: String, accounts: [ManagedCodexAccount]) -> ManagedCodexAccount? {
    let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
    return accounts.first { account in
      let home = URL(fileURLWithPath: account.managedHomePath, isDirectory: true).standardizedFileURL.path
      let prefix = home.hasSuffix("/") ? home : home + "/"
      return standardizedPath.hasPrefix(prefix)
    }
  }

  private func stableHash(_ input: String) -> String {
    let digest = SHA256.hash(data: Data(input.utf8))
    return digest.compactMap { String(format: "%02x", $0) }.joined()
  }

  private func mergedSessions(from ledgers: [TokenCostSyncLedger]) -> [String: TokenCostSyncSession] {
    var sessions: [String: (session: TokenCostSyncSession, updatedAt: Date)] = [:]

    for ledger in ledgers {
      for session in ledger.sessions {
        let existing = sessions[session.dedupeKey]
        if existing == nil || existing!.updatedAt < ledger.updatedAt {
          sessions[session.dedupeKey] = (session, ledger.updatedAt)
        }
      }
    }

    return sessions.mapValues(\.session)
  }

  private func buildAccountSummaries(from ledgers: [TokenCostSyncLedger], now: Date) -> [TokenCostAccountSummary] {
    struct AccountState {
      var displayName: String
      var days: [String: TokenCostCachedDay] = [:]
      var sessionCount = 0
      var devices: Set<String> = []
    }

    var states: [String: AccountState] = [:]

    for ledger in ledgers {
      for session in ledger.sessions {
        var state = states[session.accountKey] ?? AccountState(displayName: session.accountDisplayName)
        state.displayName = session.accountDisplayName
        state.sessionCount += 1
        state.devices.insert(ledger.device.deviceID)
        merge(days: session.days, into: &state.days)
        states[session.accountKey] = state
      }
    }

    return states.map { accountKey, state in
      let snapshot = TokenCostSnapshotBuilder.buildSnapshot(days: state.days, now: now)
      return TokenCostAccountSummary(
        accountKey: accountKey,
        displayName: state.displayName,
        todayTokens: snapshot.todayTokens,
        todayCostUSD: snapshot.todayCostUSD,
        last30DaysTokens: snapshot.last30DaysTokens,
        last30DaysCostUSD: snapshot.last30DaysCostUSD,
        sessionCount: state.sessionCount,
        deviceCount: state.devices.count
      )
    }
    .sorted { lhs, rhs in
      let lhsTokens = lhs.last30DaysTokens ?? -1
      let rhsTokens = rhs.last30DaysTokens ?? -1
      if lhsTokens != rhsTokens {
        return lhsTokens > rhsTokens
      }
      return lhs.displayName < rhs.displayName
    }
  }

  private func merge(
    days source: [String: TokenCostCachedDay],
    into destination: inout [String: TokenCostCachedDay]
  ) {
    for (dayKey, sourceDay) in source {
      var destinationDay = destination[dayKey] ?? TokenCostCachedDay()

      for (model, sourceBucket) in sourceDay.models {
        var destinationBucket = destinationDay.models[model] ?? TokenCostBucket()
        destinationBucket.add(
          inputTokens: sourceBucket.inputTokens,
          cacheReadTokens: sourceBucket.cacheReadTokens,
          outputTokens: sourceBucket.outputTokens
        )
        destinationDay.models[model] = destinationBucket
      }

      for (hourKey, sourceHour) in sourceDay.hours {
        var destinationHour = destinationDay.hours[hourKey] ?? TokenCostCachedHour()
        for (model, sourceBucket) in sourceHour.models {
          var destinationBucket = destinationHour.models[model] ?? TokenCostBucket()
          destinationBucket.add(
            inputTokens: sourceBucket.inputTokens,
            cacheReadTokens: sourceBucket.cacheReadTokens,
            outputTokens: sourceBucket.outputTokens
          )
          destinationHour.models[model] = destinationBucket
        }
        destinationDay.hours[hourKey] = destinationHour
      }

      destination[dayKey] = destinationDay
    }
  }
}
