import Foundation

public enum AppPaths {
  public static let rootDirectory: URL = {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return appSupport.appending(path: "CodexRateWatcherNative")
  }()

  public static let samplesFile = rootDirectory.appending(path: "samples.json")
  public static let profilesDirectory = rootDirectory.appending(path: "auth-profiles")
  public static let profileIndexFile = rootDirectory.appending(path: "profiles.json")
  public static let backupsDirectory = rootDirectory.appending(path: "auth-backups")
  public static let managedCodexHomesDirectory = rootDirectory.appending(path: "managed-codex-homes")
  public static let managedCodexAccountsFile = rootDirectory.appending(path: "managed-codex-accounts.json")
  public static let tokenCostCacheFile = rootDirectory.appending(path: "token-cost-cache.json")
  public static let tokenCostDeviceFile = rootDirectory.appending(path: "token-cost-device.json")
  public static let tokenCostLocalLedgerFile = rootDirectory.appending(path: "token-cost-ledger.json")
  public static let larkSignatureSyncConfigFile = rootDirectory.appending(path: "lark-signature-sync.json")

  public static let iCloudDriveRootDirectory: URL = {
    FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library", directoryHint: .isDirectory)
      .appending(path: "Mobile Documents", directoryHint: .isDirectory)
      .appending(path: "com~apple~CloudDocs", directoryHint: .isDirectory)
      .appending(path: "Codex Rate Watcher", directoryHint: .isDirectory)
  }()

  public static let iCloudLedgerDirectory = iCloudDriveRootDirectory.appending(path: "token-ledgers")
}

public struct UsageSample: Codable, Sendable {
  public let capturedAt: Date
  public let primaryUsedPercent: Double
  public let primaryResetAt: TimeInterval
  public let secondaryUsedPercent: Double?
  public let secondaryResetAt: TimeInterval?
  public let reviewUsedPercent: Double
  public let reviewResetAt: TimeInterval

  public init(
    capturedAt: Date,
    primaryUsedPercent: Double,
    primaryResetAt: TimeInterval,
    secondaryUsedPercent: Double? = nil,
    secondaryResetAt: TimeInterval? = nil,
    reviewUsedPercent: Double,
    reviewResetAt: TimeInterval
  ) {
    self.capturedAt = capturedAt
    self.primaryUsedPercent = primaryUsedPercent
    self.primaryResetAt = primaryResetAt
    self.secondaryUsedPercent = secondaryUsedPercent
    self.secondaryResetAt = secondaryResetAt
    self.reviewUsedPercent = reviewUsedPercent
    self.reviewResetAt = reviewResetAt
  }
}
