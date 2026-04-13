import Foundation

enum TokenCostSyncSourceKind: String, Codable, Equatable, Sendable {
  case managed
  case localUnknown = "local_unknown"
}

struct TokenCostSyncDevice: Codable, Equatable, Sendable {
  let deviceID: String
  let deviceName: String
  let createdAt: Date

  init(deviceID: String, deviceName: String, createdAt: Date) {
    self.deviceID = deviceID
    self.deviceName = deviceName
    self.createdAt = createdAt
  }
}

struct TokenCostSyncSession: Codable, Equatable, Sendable {
  let dedupeKey: String
  let sessionID: String?
  let accountKey: String
  let accountDisplayName: String
  let sourceKind: TokenCostSyncSourceKind
  let days: [String: TokenCostCachedDay]

  init(
    dedupeKey: String,
    sessionID: String?,
    accountKey: String,
    accountDisplayName: String,
    sourceKind: TokenCostSyncSourceKind,
    days: [String: TokenCostCachedDay]
  ) {
    self.dedupeKey = dedupeKey
    self.sessionID = sessionID
    self.accountKey = accountKey
    self.accountDisplayName = accountDisplayName
    self.sourceKind = sourceKind
    self.days = days
  }
}

struct TokenCostSyncLedger: Codable, Equatable, Sendable {
  let version: Int
  let device: TokenCostSyncDevice
  let updatedAt: Date
  let sessions: [TokenCostSyncSession]

  init(
    version: Int = 1,
    device: TokenCostSyncDevice,
    updatedAt: Date,
    sessions: [TokenCostSyncSession]
  ) {
    self.version = version
    self.device = device
    self.updatedAt = updatedAt
    self.sessions = sessions
  }
}
