import Foundation

public struct TokenCostModelBreakdown: Codable, Equatable, Sendable {
  public let modelName: String
  public let costUSD: Double?
  public let totalTokens: Int?

  public init(modelName: String, costUSD: Double?, totalTokens: Int?) {
    self.modelName = modelName
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

  public init(
    date: String,
    inputTokens: Int?,
    cacheReadTokens: Int?,
    outputTokens: Int?,
    totalTokens: Int?,
    costUSD: Double?,
    modelsUsed: [String]?,
    modelBreakdowns: [TokenCostModelBreakdown]?
  ) {
    self.date = date
    self.inputTokens = inputTokens
    self.cacheReadTokens = cacheReadTokens
    self.outputTokens = outputTokens
    self.totalTokens = totalTokens
    self.costUSD = costUSD
    self.modelsUsed = modelsUsed
    self.modelBreakdowns = modelBreakdowns
  }
}

public struct TokenCostSnapshot: Codable, Equatable, Sendable {
  public let todayTokens: Int?
  public let todayCostUSD: Double?
  public let last30DaysTokens: Int?
  public let last30DaysCostUSD: Double?
  public let daily: [TokenCostDailyEntry]
  public let updatedAt: Date

  public init(
    todayTokens: Int?,
    todayCostUSD: Double?,
    last30DaysTokens: Int?,
    last30DaysCostUSD: Double?,
    daily: [TokenCostDailyEntry],
    updatedAt: Date
  ) {
    self.todayTokens = todayTokens
    self.todayCostUSD = todayCostUSD
    self.last30DaysTokens = last30DaysTokens
    self.last30DaysCostUSD = last30DaysCostUSD
    self.daily = daily
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
    daily.filter { ($0.totalTokens ?? 0) > 0 }.count
  }
}
