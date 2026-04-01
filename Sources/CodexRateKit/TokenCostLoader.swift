import Foundation

public protocol TokenCostSnapshotLoading: Sendable {
  func loadSnapshot(now: Date) async -> TokenCostSnapshot
}

public struct LiveTokenCostSnapshotLoader: TokenCostSnapshotLoading {
  public init() {}

  public func loadSnapshot(now: Date) async -> TokenCostSnapshot {
    await Task.detached(priority: .utility) {
      TokenCostScanner.loadSnapshot(now: now)
    }.value
  }
}
