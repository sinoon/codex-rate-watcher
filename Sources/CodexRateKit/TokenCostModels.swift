import Foundation

public enum TokenCostSourceMode: String, Codable, Equatable, Sendable {
  case localOnly = "local_only"
  case iCloudMerged = "icloud_merged"
}

public struct TokenCostSourceSummary: Codable, Equatable, Sendable {
  public let mode: TokenCostSourceMode
  public let syncedDeviceCount: Int
  public let localDeviceID: String?
  public let localDeviceName: String?
  public let updatedAt: Date?

  public init(
    mode: TokenCostSourceMode,
    syncedDeviceCount: Int,
    localDeviceID: String? = nil,
    localDeviceName: String? = nil,
    updatedAt: Date? = nil
  ) {
    self.mode = mode
    self.syncedDeviceCount = syncedDeviceCount
    self.localDeviceID = localDeviceID
    self.localDeviceName = localDeviceName
    self.updatedAt = updatedAt
  }
}

public struct TokenCostLocalSummary: Codable, Equatable, Sendable {
  public let todayTokens: Int?
  public let todayCostUSD: Double?
  public let last7DaysTokens: Int?
  public let last7DaysCostUSD: Double?
  public let last30DaysTokens: Int?
  public let last30DaysCostUSD: Double?

  public init(
    todayTokens: Int?,
    todayCostUSD: Double?,
    last7DaysTokens: Int? = nil,
    last7DaysCostUSD: Double? = nil,
    last30DaysTokens: Int?,
    last30DaysCostUSD: Double?
  ) {
    self.todayTokens = todayTokens
    self.todayCostUSD = todayCostUSD
    self.last7DaysTokens = last7DaysTokens
    self.last7DaysCostUSD = last7DaysCostUSD
    self.last30DaysTokens = last30DaysTokens
    self.last30DaysCostUSD = last30DaysCostUSD
  }
}

public struct TokenCostAccountSummary: Codable, Equatable, Sendable {
  public let accountKey: String
  public let displayName: String
  public let todayTokens: Int?
  public let todayCostUSD: Double?
  public let last30DaysTokens: Int?
  public let last30DaysCostUSD: Double?
  public let sessionCount: Int
  public let deviceCount: Int

  public init(
    accountKey: String,
    displayName: String,
    todayTokens: Int?,
    todayCostUSD: Double?,
    last30DaysTokens: Int?,
    last30DaysCostUSD: Double?,
    sessionCount: Int,
    deviceCount: Int
  ) {
    self.accountKey = accountKey
    self.displayName = displayName
    self.todayTokens = todayTokens
    self.todayCostUSD = todayCostUSD
    self.last30DaysTokens = last30DaysTokens
    self.last30DaysCostUSD = last30DaysCostUSD
    self.sessionCount = sessionCount
    self.deviceCount = deviceCount
  }
}

public struct TokenCostHourlyEntry: Codable, Equatable, Sendable {
  public let hour: Int
  public let inputTokens: Int?
  public let cacheReadTokens: Int?
  public let outputTokens: Int?
  public let totalTokens: Int?
  public let costUSD: Double?

  public init(
    hour: Int,
    inputTokens: Int?,
    cacheReadTokens: Int?,
    outputTokens: Int?,
    totalTokens: Int?,
    costUSD: Double?
  ) {
    self.hour = hour
    self.inputTokens = inputTokens
    self.cacheReadTokens = cacheReadTokens
    self.outputTokens = outputTokens
    self.totalTokens = totalTokens
    self.costUSD = costUSD
  }
}

public struct TokenCostModelBreakdown: Codable, Equatable, Sendable {
  public let modelName: String
  public let inputTokens: Int?
  public let cacheReadTokens: Int?
  public let outputTokens: Int?
  public let costUSD: Double?
  public let totalTokens: Int?

  public init(
    modelName: String,
    inputTokens: Int? = nil,
    cacheReadTokens: Int? = nil,
    outputTokens: Int? = nil,
    costUSD: Double?,
    totalTokens: Int?
  ) {
    self.modelName = modelName
    self.inputTokens = inputTokens
    self.cacheReadTokens = cacheReadTokens
    self.outputTokens = outputTokens
    self.costUSD = costUSD
    self.totalTokens = totalTokens
  }
}

public struct TokenCostDailyEntry: Codable, Equatable, Sendable {
  public let date: String
  public let inputTokens: Int?
  public let cacheReadTokens: Int?
  public let outputTokens: Int?
  public let totalTokens: Int?
  public let costUSD: Double?
  public let modelsUsed: [String]?
  public let modelBreakdowns: [TokenCostModelBreakdown]?
  public let hourlyBreakdowns: [TokenCostHourlyEntry]?

  public init(
    date: String,
    inputTokens: Int?,
    cacheReadTokens: Int?,
    outputTokens: Int?,
    totalTokens: Int?,
    costUSD: Double?,
    modelsUsed: [String]?,
    modelBreakdowns: [TokenCostModelBreakdown]?,
    hourlyBreakdowns: [TokenCostHourlyEntry]? = nil
  ) {
    self.date = date
    self.inputTokens = inputTokens
    self.cacheReadTokens = cacheReadTokens
    self.outputTokens = outputTokens
    self.totalTokens = totalTokens
    self.costUSD = costUSD
    self.modelsUsed = modelsUsed
    self.modelBreakdowns = modelBreakdowns
    self.hourlyBreakdowns = hourlyBreakdowns
  }
}

public struct TokenCostModelSummary: Codable, Equatable, Sendable {
  public let modelName: String
  public let inputTokens: Int
  public let cacheReadTokens: Int
  public let outputTokens: Int
  public let totalTokens: Int
  public let costUSD: Double?
  public let costShare: Double?
  public let tokenShare: Double?

  public init(
    modelName: String,
    inputTokens: Int,
    cacheReadTokens: Int,
    outputTokens: Int,
    totalTokens: Int,
    costUSD: Double?,
    costShare: Double?,
    tokenShare: Double?
  ) {
    self.modelName = modelName
    self.inputTokens = inputTokens
    self.cacheReadTokens = cacheReadTokens
    self.outputTokens = outputTokens
    self.totalTokens = totalTokens
    self.costUSD = costUSD
    self.costShare = costShare
    self.tokenShare = tokenShare
  }
}

public struct TokenCostInsight: Codable, Equatable, Sendable {
  public let kind: String
  public let title: String
  public let message: String
  public let severity: String

  public init(kind: String, title: String, message: String, severity: String) {
    self.kind = kind
    self.title = title
    self.message = message
    self.severity = severity
  }
}

public struct TokenCostNarrative: Codable, Equatable, Sendable {
  public let whatChanged: [String]
  public let whatHelped: [String]
  public let whatToWatch: [String]

  public init(
    whatChanged: [String] = [],
    whatHelped: [String] = [],
    whatToWatch: [String] = []
  ) {
    self.whatChanged = whatChanged
    self.whatHelped = whatHelped
    self.whatToWatch = whatToWatch
  }
}

public struct TokenCostWindowSummary: Codable, Equatable, Sendable {
  public let windowDays: Int
  public let totalTokens: Int?
  public let totalCostUSD: Double?
  public let averageDailyTokens: Double?
  public let averageDailyCostUSD: Double?
  public let activeDayCount: Int
  public let cacheShare: Double?
  public let dominantModelName: String?
  public let modelSummaries: [TokenCostModelSummary]
  public let hourly: [TokenCostHourlyEntry]
  public let alerts: [TokenCostInsight]
  public let narrative: TokenCostNarrative
  public let hasPartialPricing: Bool

  public init(
    windowDays: Int,
    totalTokens: Int?,
    totalCostUSD: Double?,
    averageDailyTokens: Double?,
    averageDailyCostUSD: Double?,
    activeDayCount: Int,
    cacheShare: Double?,
    dominantModelName: String?,
    modelSummaries: [TokenCostModelSummary],
    hourly: [TokenCostHourlyEntry],
    alerts: [TokenCostInsight],
    narrative: TokenCostNarrative,
    hasPartialPricing: Bool
  ) {
    self.windowDays = windowDays
    self.totalTokens = totalTokens
    self.totalCostUSD = totalCostUSD
    self.averageDailyTokens = averageDailyTokens
    self.averageDailyCostUSD = averageDailyCostUSD
    self.activeDayCount = activeDayCount
    self.cacheShare = cacheShare
    self.dominantModelName = dominantModelName
    self.modelSummaries = modelSummaries
    self.hourly = hourly
    self.alerts = alerts
    self.narrative = narrative
    self.hasPartialPricing = hasPartialPricing
  }
}

public struct TokenCostSnapshot: Codable, Equatable, Sendable {
  public let todayTokens: Int?
  public let todayCostUSD: Double?
  public let last7DaysTokens: Int?
  public let last7DaysCostUSD: Double?
  public let last30DaysTokens: Int?
  public let last30DaysCostUSD: Double?
  public let last90DaysTokens: Int?
  public let last90DaysCostUSD: Double?
  public let averageDailyTokens: Double?
  public let averageDailyCostUSD: Double?
  public let modelSummaries: [TokenCostModelSummary]
  public let hourly: [TokenCostHourlyEntry]
  public let alerts: [TokenCostInsight]
  public let narrative: TokenCostNarrative
  public let windows: [TokenCostWindowSummary]
  public let hasPartialPricing: Bool
  public let daily: [TokenCostDailyEntry]
  public let source: TokenCostSourceSummary?
  public let localSummary: TokenCostLocalSummary?
  public let accountSummaries: [TokenCostAccountSummary]
  public let updatedAt: Date

  public init(
    todayTokens: Int?,
    todayCostUSD: Double?,
    last7DaysTokens: Int? = nil,
    last7DaysCostUSD: Double? = nil,
    last30DaysTokens: Int?,
    last30DaysCostUSD: Double?,
    last90DaysTokens: Int? = nil,
    last90DaysCostUSD: Double? = nil,
    averageDailyTokens: Double? = nil,
    averageDailyCostUSD: Double? = nil,
    modelSummaries: [TokenCostModelSummary] = [],
    hourly: [TokenCostHourlyEntry] = [],
    alerts: [TokenCostInsight] = [],
    narrative: TokenCostNarrative = .init(),
    windows: [TokenCostWindowSummary] = [],
    hasPartialPricing: Bool = false,
    daily: [TokenCostDailyEntry],
    source: TokenCostSourceSummary? = nil,
    localSummary: TokenCostLocalSummary? = nil,
    accountSummaries: [TokenCostAccountSummary] = [],
    updatedAt: Date
  ) {
    self.todayTokens = todayTokens
    self.todayCostUSD = todayCostUSD
    self.last7DaysTokens = last7DaysTokens
    self.last7DaysCostUSD = last7DaysCostUSD
    self.last30DaysTokens = last30DaysTokens
    self.last30DaysCostUSD = last30DaysCostUSD
    self.last90DaysTokens = last90DaysTokens
    self.last90DaysCostUSD = last90DaysCostUSD
    self.averageDailyTokens = averageDailyTokens
    self.averageDailyCostUSD = averageDailyCostUSD
    self.modelSummaries = modelSummaries
    self.hourly = hourly
    self.alerts = alerts
    self.narrative = narrative
    self.windows = windows
    self.hasPartialPricing = hasPartialPricing
    self.daily = daily
    self.source = source
    self.localSummary = localSummary
    self.accountSummaries = accountSummaries
    self.updatedAt = updatedAt
  }
}

extension TokenCostSnapshot {
  public var hasAnyData: Bool {
    if todayTokens != nil || last30DaysTokens != nil {
      return true
    }
    return daily.contains { ($0.totalTokens ?? 0) > 0 }
  }

  public var activeDayCount: Int {
    windowSummary(days: 30)?.activeDayCount
      ?? daily.filter { ($0.totalTokens ?? 0) > 0 }.count
  }

  public func windowSummary(days: Int) -> TokenCostWindowSummary? {
    windows.first { $0.windowDays == days }
  }
}
