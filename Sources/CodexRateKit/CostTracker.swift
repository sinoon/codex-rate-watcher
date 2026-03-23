import Foundation

// MARK: - Pricing Constants

/// Subscription pricing tiers for cost estimation.
public enum SubscriptionTier: String, Codable, Sendable {
  case plus = "plus"
  case team = "team"
  case unknown = "unknown"

  public var monthlyUSD: Double {
    switch self {
    case .plus: return 20.0
    case .team: return 25.0
    case .unknown: return 20.0  // default to Plus
    }
  }

  public var dailyUSD: Double { monthlyUSD / 30.0 }

  /// Cost per 1% of primary quota (5h window).
  /// Rough model: ~3 primary windows per day (5h active coding),
  /// so daily cost spread across ~300% total primary quota.
  public var costPerPrimaryPercent: Double {
    dailyUSD / 300.0
  }

  public init(planType: String) {
    switch planType.lowercased() {
    case "team": self = .team
    case "plus": self = .plus
    default: self = .unknown
    }
  }
}

// MARK: - Cost Record (single cycle snapshot)

/// Records the state at the end of one polling cycle, used for historical analysis.
public struct CostRecord: Codable, Sendable {
  public let timestamp: Date
  public let tier: SubscriptionTier
  /// Primary quota used percent at this moment
  public let primaryUsedPercent: Double
  /// Burn rate at this moment (percent per hour), nil if unknown
  public let burnRatePerHour: Double?
  /// Primary window reset timestamp
  public let primaryResetAt: TimeInterval
  /// Weekly quota used percent (if available)
  public let weeklyUsedPercent: Double?

  public init(
    timestamp: Date = Date(),
    tier: SubscriptionTier,
    primaryUsedPercent: Double,
    burnRatePerHour: Double?,
    primaryResetAt: TimeInterval,
    weeklyUsedPercent: Double? = nil
  ) {
    self.timestamp = timestamp
    self.tier = tier
    self.primaryUsedPercent = primaryUsedPercent
    self.burnRatePerHour = burnRatePerHour
    self.primaryResetAt = primaryResetAt
    self.weeklyUsedPercent = weeklyUsedPercent
  }
}

// MARK: - Cycle Summary

/// Summary of one primary-window cycle (5h window).
public struct CycleSummary: Codable, Sendable {
  public let resetAt: TimeInterval
  public let peakUsedPercent: Double
  public let activeMinutes: Int
  public let avgBurnRate: Double?
  public let tier: SubscriptionTier

  /// What fraction of the quota was actually consumed this cycle.
  public var utilization: Double { peakUsedPercent / 100.0 }

  /// Estimated dollar value consumed this cycle.
  public var estimatedCost: Double { peakUsedPercent * tier.costPerPrimaryPercent }
}

// MARK: - Daily Digest

/// Aggregated cost metrics for a single calendar day.
public struct DailyDigest: Codable, Sendable {
  public let date: String  // "2026-03-23"
  public let tier: SubscriptionTier
  public let cycles: [CycleSummary]
  public let totalActiveMinutes: Int
  public let avgUtilization: Double
  public let estimatedCostUSD: Double
  public let peakBurnRate: Double?
}

// MARK: - Today's Live Cost State

/// Real-time cost snapshot computed from current monitor state.
public struct LiveCostState: Sendable {
  public let tier: SubscriptionTier
  /// Current burn rate in $/hr
  public let costPerHour: Double?
  /// Estimated cost accumulated today
  public let todayCostUSD: Double
  /// Utilization rate of the current cycle (0-1)
  public let currentCycleUtilization: Double
  /// Monthly projected cost at current pace
  public let projectedMonthlyCostUSD: Double?
  /// Subscription monthly cost for reference
  public let subscriptionMonthlyUSD: Double
  /// 24h sparkline data points (hourly cost estimates, newest last)
  public let sparkline: [Double]
  /// Active hours today
  public let activeHoursToday: Double
  /// Average utilization over stored history
  public let avgUtilization: Double?

  public init(
    tier: SubscriptionTier,
    costPerHour: Double?,
    todayCostUSD: Double,
    currentCycleUtilization: Double,
    projectedMonthlyCostUSD: Double?,
    subscriptionMonthlyUSD: Double,
    sparkline: [Double],
    activeHoursToday: Double,
    avgUtilization: Double? = nil
  ) {
    self.tier = tier
    self.costPerHour = costPerHour
    self.todayCostUSD = todayCostUSD
    self.currentCycleUtilization = currentCycleUtilization
    self.projectedMonthlyCostUSD = projectedMonthlyCostUSD
    self.subscriptionMonthlyUSD = subscriptionMonthlyUSD
    self.sparkline = sparkline
    self.activeHoursToday = activeHoursToday
    self.avgUtilization = avgUtilization
  }
}

// MARK: - CostTracker

/// Tracks cost and usage history, persisted to disk.
/// Thread-safe: all methods are synchronous and operate on value types.
public enum CostTracker {
  private static let maxRecords = 24 * 60 * 30  // ~30 days at 1 record/min
  private static let calendar = Calendar.current

  // MARK: - Record a sample

  /// Record a cost data point from the current usage state.
  public static func record(
    tier: SubscriptionTier,
    primaryUsedPercent: Double,
    burnRatePerHour: Double?,
    primaryResetAt: TimeInterval,
    weeklyUsedPercent: Double? = nil
  ) {
    let record = CostRecord(
      tier: tier,
      primaryUsedPercent: primaryUsedPercent,
      burnRatePerHour: burnRatePerHour,
      primaryResetAt: primaryResetAt,
      weeklyUsedPercent: weeklyUsedPercent
    )

    var history = loadHistory()
    history.append(record)

    // Rolling window: keep last maxRecords
    if history.count > maxRecords {
      history = Array(history.suffix(maxRecords))
    }

    saveHistory(history)
  }

  // MARK: - Today's summary

  /// Compute today's aggregated cost summary from history.
  public static func todaySummary(
    currentTier: SubscriptionTier,
    currentBurnRate: Double?,
    currentUsedPercent: Double
  ) -> LiveCostState {
    let history = loadHistory()
    let now = Date()
    let todayStart = calendar.startOfDay(for: now)

    let todayRecords = history.filter { $0.timestamp >= todayStart }

    // -- Cost per hour --
    let costPerHour: Double? = currentBurnRate.map { rate in
      rate * currentTier.costPerPrimaryPercent
    }

    // -- Today's cost: sum up peak usage per unique reset cycle --
    let todayCost = estimateDayCost(records: todayRecords, tier: currentTier)

    // -- Current cycle utilization --
    let cycleUtil = currentUsedPercent / 100.0

    // -- Projected monthly --
    let dayOfMonth = calendar.component(.day, from: now)
    let projectedMonthly: Double?
    if dayOfMonth >= 3, todayCost > 0 {
      let allDays = dailyDigests(from: history, tier: currentTier)
      let recentDays = allDays.suffix(7)
      if !recentDays.isEmpty {
        let avgDaily = recentDays.map(\.estimatedCostUSD).reduce(0, +) / Double(recentDays.count)
        projectedMonthly = avgDaily * 30
      } else {
        projectedMonthly = todayCost * 30
      }
    } else {
      projectedMonthly = nil
    }

    // -- 24h sparkline --
    let sparkline = buildSparkline(from: history, now: now)

    // -- Active hours today --
    let activeHours = estimateActiveHours(records: todayRecords)

    // -- Avg utilization (7-day) --
    let digests = dailyDigests(from: history, tier: currentTier)
    let avgUtil: Double? = digests.isEmpty ? nil :
      digests.suffix(7).map(\.avgUtilization).reduce(0, +) / Double(min(7, digests.count))

    return LiveCostState(
      tier: currentTier,
      costPerHour: costPerHour,
      todayCostUSD: todayCost,
      currentCycleUtilization: cycleUtil,
      projectedMonthlyCostUSD: projectedMonthly,
      subscriptionMonthlyUSD: currentTier.monthlyUSD,
      sparkline: sparkline,
      activeHoursToday: activeHours,
      avgUtilization: avgUtil
    )
  }

  // MARK: - Weekly stats (for CLI)

  public static func weeklyStats(tier: SubscriptionTier) -> [DailyDigest] {
    let history = loadHistory()
    let digests = dailyDigests(from: history, tier: tier)
    return Array(digests.suffix(7))
  }

  // MARK: - Private helpers

  private static func estimateDayCost(records: [CostRecord], tier: SubscriptionTier) -> Double {
    // Group records by resetAt (each reset cycle)
    var cyclesPeak: [TimeInterval: Double] = [:]
    for r in records {
      let key = r.primaryResetAt
      cyclesPeak[key] = max(cyclesPeak[key] ?? 0, r.primaryUsedPercent)
    }
    // Sum the peak usage of each cycle × cost per percent
    return cyclesPeak.values.reduce(0) { $0 + $1 * tier.costPerPrimaryPercent }
  }

  private static func estimateActiveHours(records: [CostRecord]) -> Double {
    guard records.count >= 2 else { return 0 }

    var activeMinutes = 0
    for i in 1..<records.count {
      let prev = records[i - 1]
      let curr = records[i]
      let gap = curr.timestamp.timeIntervalSince(prev.timestamp)
      // Consider "active" if usage increased AND gap < 5 min
      if gap < 300, curr.primaryUsedPercent > prev.primaryUsedPercent + 0.1 {
        activeMinutes += Int(gap / 60)
      }
    }
    return Double(activeMinutes) / 60.0
  }

  private static func buildSparkline(from history: [CostRecord], now: Date) -> [Double] {
    // 24 data points, one per hour for the last 24h
    var points = [Double](repeating: 0, count: 24)
    let oneDayAgo = now.addingTimeInterval(-24 * 3600)

    let recent = history.filter { $0.timestamp >= oneDayAgo }

    for record in recent {
      let hoursAgo = now.timeIntervalSince(record.timestamp) / 3600
      let bucket = 23 - min(23, Int(hoursAgo))
      if let rate = record.burnRatePerHour, rate > 0 {
        points[bucket] = max(points[bucket], rate * record.tier.costPerPrimaryPercent)
      }
    }
    return points
  }

  private static func dailyDigests(from history: [CostRecord], tier: SubscriptionTier) -> [DailyDigest] {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"

    let grouped = Dictionary(grouping: history) { fmt.string(from: $0.timestamp) }

    return grouped.keys.sorted().map { dateStr in
      let records = grouped[dateStr]!
      let dayCost = estimateDayCost(records: records, tier: tier)
      let activeHrs = estimateActiveHours(records: records)

      // Cycle summaries
      let cycleGroups = Dictionary(grouping: records) { $0.primaryResetAt }
      let cycles = cycleGroups.map { (resetAt, cycleRecords) -> CycleSummary in
        let peak = cycleRecords.map(\.primaryUsedPercent).max() ?? 0
        let rates = cycleRecords.compactMap(\.burnRatePerHour)
        let avgRate = rates.isEmpty ? nil : rates.reduce(0, +) / Double(rates.count)
        return CycleSummary(
          resetAt: resetAt,
          peakUsedPercent: peak,
          activeMinutes: Int(estimateActiveHours(records: cycleRecords) * 60),
          avgBurnRate: avgRate,
          tier: tier
        )
      }

      let avgUtil = cycles.isEmpty ? 0 : cycles.map(\.utilization).reduce(0, +) / Double(cycles.count)
      let peakRate = records.compactMap(\.burnRatePerHour).max()

      return DailyDigest(
        date: dateStr,
        tier: tier,
        cycles: cycles,
        totalActiveMinutes: Int(activeHrs * 60),
        avgUtilization: avgUtil,
        estimatedCostUSD: dayCost,
        peakBurnRate: peakRate
      )
    }
  }

  // MARK: - Persistence

  private static func loadHistory() -> [CostRecord] {
    let url = AppPaths.costHistoryFile
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    do {
      let data = try Data(contentsOf: url)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return try decoder.decode([CostRecord].self, from: data)
    } catch {
      return []
    }
  }

  private static func saveHistory(_ records: [CostRecord]) {
    let url = AppPaths.costHistoryFile
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      let data = try encoder.encode(records)
      try data.write(to: url, options: .atomic)
    } catch {
      // Silently fail — cost tracking is non-critical
    }
  }
}
