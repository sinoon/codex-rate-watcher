import Foundation

public struct TokenCostCLIPayload: Codable, Equatable, Sendable {
  public let updatedAt: Date
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
  public let activeDayCount: Int
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

  public init(snapshot: TokenCostSnapshot) {
    self.updatedAt = snapshot.updatedAt
    self.todayTokens = snapshot.todayTokens
    self.todayCostUSD = snapshot.todayCostUSD
    self.last7DaysTokens = snapshot.last7DaysTokens
    self.last7DaysCostUSD = snapshot.last7DaysCostUSD
    self.last30DaysTokens = snapshot.last30DaysTokens
    self.last30DaysCostUSD = snapshot.last30DaysCostUSD
    self.last90DaysTokens = snapshot.last90DaysTokens
    self.last90DaysCostUSD = snapshot.last90DaysCostUSD
    self.averageDailyTokens = snapshot.averageDailyTokens
    self.averageDailyCostUSD = snapshot.averageDailyCostUSD
    self.activeDayCount = snapshot.activeDayCount
    self.modelSummaries = snapshot.modelSummaries
    self.hourly = snapshot.hourly
    self.alerts = snapshot.alerts
    self.narrative = snapshot.narrative
    self.windows = snapshot.windows
    self.hasPartialPricing = snapshot.hasPartialPricing
    self.daily = snapshot.daily
    self.source = snapshot.source
    self.localSummary = snapshot.localSummary
    self.accountSummaries = snapshot.accountSummaries
  }
}

public enum TokenCostCLIReport {
  public static func jsonData(snapshot: TokenCostSnapshot) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return try encoder.encode(TokenCostCLIPayload(snapshot: snapshot))
  }

  public static func renderText(snapshot: TokenCostSnapshot, colorized: Bool = true) -> String {
    let styles = CLIStyles(colorized: colorized)
    var lines: [String] = []

    lines.append("")
    lines.append("\(styles.bold)💰 Token Cost\(styles.reset)")
    lines.append("\(styles.dim)────────────────────────────────────────\(styles.reset)")
    lines.append("")

    if !snapshot.hasAnyData {
      lines.append("  \(styles.dim)No local session data yet. Run Codex to collect session logs.\(styles.reset)")
      lines.append("")
      return lines.joined(separator: "\n")
    }

    let sourceMode = snapshot.source?.mode == .iCloudMerged ? "All Devices" : "Local Device"
    lines.append("  \(styles.bold)\(sourceMode)\(styles.reset)")
    lines.append("  \(styles.dim)Today Cost:\(styles.reset)     \(styles.bold)\(usd(snapshot.todayCostUSD))\(styles.reset)")
    lines.append("  \(styles.dim)Today Tokens:\(styles.reset)   \(tokenCount(snapshot.todayTokens))")
    lines.append("  \(styles.dim)7 Day Cost:\(styles.reset)     \(styles.bold)\(usd(snapshot.last7DaysCostUSD))\(styles.reset)")
    lines.append("  \(styles.dim)30 Day Cost:\(styles.reset)    \(styles.bold)\(usd(snapshot.last30DaysCostUSD))\(styles.reset)")
    lines.append("  \(styles.dim)90 Day Cost:\(styles.reset)    \(styles.bold)\(usd(snapshot.last90DaysCostUSD))\(styles.reset)")
    lines.append("  \(styles.dim)Average Day:\(styles.reset)    \(averageLabel(snapshot: snapshot))")
    lines.append("  \(styles.dim)Active Days:\(styles.reset)    \(snapshot.activeDayCount)")
    lines.append("  \(styles.dim)Cache Share:\(styles.reset)    \(cacheShareLabel(snapshot))")
    lines.append("  \(styles.dim)Dominant Model:\(styles.reset) \(snapshot.modelSummaries.first?.modelName ?? "—")")

    if let source = snapshot.source {
      lines.append("  \(styles.dim)Synced Devices:\(styles.reset) \(source.syncedDeviceCount)")
    }

    if snapshot.source?.mode == .iCloudMerged, let localSummary = snapshot.localSummary {
      lines.append("")
      lines.append("  \(styles.bold)Local Device\(styles.reset)")
      lines.append("  \(styles.dim)Today Cost:\(styles.reset)     \(styles.bold)\(usd(localSummary.todayCostUSD))\(styles.reset)")
      lines.append("  \(styles.dim)Today Tokens:\(styles.reset)   \(tokenCount(localSummary.todayTokens))")
      lines.append("  \(styles.dim)30 Day Cost:\(styles.reset)    \(styles.bold)\(usd(localSummary.last30DaysCostUSD))\(styles.reset)")
      lines.append("  \(styles.dim)30 Day Tokens:\(styles.reset)  \(tokenCount(localSummary.last30DaysTokens))")
    }

    if snapshot.hasPartialPricing {
      lines.append("  \(styles.yellow)Partial pricing: some active models are missing rate cards.\(styles.reset)")
    }

    if !snapshot.alerts.isEmpty {
      lines.append("")
      lines.append("  \(styles.bold)Alerts\(styles.reset)")
      for alert in snapshot.alerts.prefix(3) {
        lines.append("  • \(alert.title): \(alert.message)")
      }
    }

    if !snapshot.modelSummaries.isEmpty {
      lines.append("")
      lines.append("  \(styles.bold)Top Models\(styles.reset)")
      lines.append("  \(styles.dim)Model          Cost        Tokens      Share\(styles.reset)")
      for model in snapshot.modelSummaries.prefix(5) {
        let share = percent(model.costShare ?? model.tokenShare)
        lines.append(
          "  \(pad(model.modelName, to: 14)) \(pad(usd(model.costUSD), to: 10)) \(pad(TokenCostFormatting.tokenCount(model.totalTokens), to: 11)) \(share)"
        )
      }
    }

    if !snapshot.accountSummaries.isEmpty {
      lines.append("")
      lines.append("  \(styles.bold)Accounts\(styles.reset)")
      lines.append("  \(styles.dim)Account                30D Cost     30D Tokens   Sessions\(styles.reset)")
      for account in snapshot.accountSummaries.prefix(5) {
        lines.append(
          "  \(pad(account.displayName, to: 22)) \(pad(usd(account.last30DaysCostUSD), to: 12)) \(pad(tokenCount(account.last30DaysTokens), to: 12)) \(account.sessionCount)"
        )
      }
    }

    let recentDaily = snapshot.daily.suffix(7)
    if !recentDaily.isEmpty {
      lines.append("")
      lines.append("  \(styles.bold)Recent Daily Breakdown\(styles.reset)")
      lines.append("  \(styles.dim)Date         Cost        Tokens      Models\(styles.reset)")
      for entry in recentDaily {
        let models = (entry.modelsUsed ?? []).joined(separator: ",")
        lines.append(
          "  \(entry.date)  \(pad(usd(entry.costUSD), to: 10))  \(pad(tokenCount(entry.totalTokens), to: 11)) \(models)"
        )
      }
    }

    if !snapshot.narrative.whatToWatch.isEmpty {
      lines.append("")
      lines.append("  \(styles.bold)What To Watch\(styles.reset)")
      for item in snapshot.narrative.whatToWatch.prefix(2) {
        lines.append("  • \(item)")
      }
    }

    lines.append("")
    return lines.joined(separator: "\n")
  }

  private static func averageLabel(snapshot: TokenCostSnapshot) -> String {
    let averageCost = snapshot.averageDailyCostUSD.map {
      TokenCostFormatting.usd($0, minimumFractionDigits: 2, maximumFractionDigits: 2)
    } ?? "—"
    let averageTokens = snapshot.averageDailyTokens.map {
      TokenCostFormatting.tokenCount(Int($0.rounded()))
    } ?? "—"
    return "\(averageCost) · \(averageTokens)"
  }

  private static func cacheShareLabel(_ snapshot: TokenCostSnapshot) -> String {
    let cacheShare = snapshot.windowSummary(days: 30)?.cacheShare
    return percent(cacheShare)
  }

  private static func usd(_ value: Double?) -> String {
    guard let value else { return "—" }
    return TokenCostFormatting.usd(value, minimumFractionDigits: 2, maximumFractionDigits: 2)
  }

  private static func tokenCount(_ value: Int?) -> String {
    guard let value else { return "—" }
    return TokenCostFormatting.tokenCount(value)
  }

  private static func percent(_ value: Double?) -> String {
    guard let value else { return "—" }
    return "\(Int((value * 100).rounded()))%"
  }

  private static func pad(_ value: String, to width: Int) -> String {
    value.padding(toLength: width, withPad: " ", startingAt: 0)
  }
}

private struct CLIStyles {
  let bold: String
  let dim: String
  let yellow: String
  let reset: String

  init(colorized: Bool) {
    if colorized {
      bold = "\u{001B}[1m"
      dim = "\u{001B}[2m"
      yellow = "\u{001B}[33m"
      reset = "\u{001B}[0m"
    } else {
      bold = ""
      dim = ""
      yellow = ""
      reset = ""
    }
  }
}
