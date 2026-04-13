import Foundation

public protocol TokenCostSnapshotLoading: Sendable {
  func loadSnapshot(now: Date) async -> TokenCostSnapshot
}

public struct LiveTokenCostSnapshotLoader: TokenCostSnapshotLoading {
  private let syncService: TokenCostSyncService
  private let deviceStore: TokenCostDeviceStore
  private let managedAccountStore: ManagedCodexAccountStoring
  private let mirrorToICloud: Bool

  public init() {
    self.syncService = TokenCostSyncService()
    self.deviceStore = TokenCostDeviceStore()
    self.managedAccountStore = FileManagedCodexAccountStore()
    self.mirrorToICloud = true
  }

  init(
    syncService: TokenCostSyncService,
    deviceStore: TokenCostDeviceStore,
    managedAccountStore: ManagedCodexAccountStoring,
    mirrorToICloud: Bool
  ) {
    self.syncService = syncService
    self.deviceStore = deviceStore
    self.managedAccountStore = managedAccountStore
    self.mirrorToICloud = mirrorToICloud
  }

  public func loadSnapshot(now: Date) async -> TokenCostSnapshot {
    await Task.detached(priority: .utility) {
      let localSnapshot = TokenCostScanner.loadSnapshot(now: now)
      let managedAccounts = (try? managedAccountStore.loadAccounts()) ?? ManagedCodexAccountSet(accounts: [])
      guard let device = try? deviceStore.loadOrCreateDevice(now: now) else {
        return localSnapshot
      }

      do {
        return try syncService.synchronizedSnapshot(
          localSnapshot: localSnapshot,
          device: device,
          managedAccounts: managedAccounts,
          mirrorToICloud: mirrorToICloud,
          now: now
        )
      } catch {
        return TokenCostSnapshot(
          todayTokens: localSnapshot.todayTokens,
          todayCostUSD: localSnapshot.todayCostUSD,
          last7DaysTokens: localSnapshot.last7DaysTokens,
          last7DaysCostUSD: localSnapshot.last7DaysCostUSD,
          last30DaysTokens: localSnapshot.last30DaysTokens,
          last30DaysCostUSD: localSnapshot.last30DaysCostUSD,
          last90DaysTokens: localSnapshot.last90DaysTokens,
          last90DaysCostUSD: localSnapshot.last90DaysCostUSD,
          averageDailyTokens: localSnapshot.averageDailyTokens,
          averageDailyCostUSD: localSnapshot.averageDailyCostUSD,
          modelSummaries: localSnapshot.modelSummaries,
          hourly: localSnapshot.hourly,
          alerts: localSnapshot.alerts,
          narrative: localSnapshot.narrative,
          windows: localSnapshot.windows,
          hasPartialPricing: localSnapshot.hasPartialPricing,
          daily: localSnapshot.daily,
          source: TokenCostSourceSummary(
            mode: .localOnly,
            syncedDeviceCount: 1,
            localDeviceID: device.deviceID,
            localDeviceName: device.deviceName,
            updatedAt: localSnapshot.updatedAt
          ),
          localSummary: TokenCostLocalSummary(
            todayTokens: localSnapshot.todayTokens,
            todayCostUSD: localSnapshot.todayCostUSD,
            last30DaysTokens: localSnapshot.last30DaysTokens,
            last30DaysCostUSD: localSnapshot.last30DaysCostUSD
          ),
          accountSummaries: [],
          updatedAt: localSnapshot.updatedAt
        )
      }
    }.value
  }
}
