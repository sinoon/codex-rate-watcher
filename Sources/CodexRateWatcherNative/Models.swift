import Foundation

struct UsageSnapshot: Decodable {
  let planType: String
  let rateLimit: UsageLimit
  let codeReviewRateLimit: UsageLimit
  let credits: Credits

  enum CodingKeys: String, CodingKey {
    case planType = "plan_type"
    case rateLimit = "rate_limit"
    case codeReviewRateLimit = "code_review_rate_limit"
    case credits
  }
}

struct UsageLimit: Decodable {
  let allowed: Bool
  let limitReached: Bool
  let primaryWindow: LimitWindow
  let secondaryWindow: LimitWindow?

  enum CodingKeys: String, CodingKey {
    case allowed
    case limitReached = "limit_reached"
    case primaryWindow = "primary_window"
    case secondaryWindow = "secondary_window"
  }
}

struct LimitWindow: Decodable {
  let usedPercent: Double
  let limitWindowSeconds: Int
  let resetAfterSeconds: Int
  let resetAt: TimeInterval

  enum CodingKeys: String, CodingKey {
    case usedPercent = "used_percent"
    case limitWindowSeconds = "limit_window_seconds"
    case resetAfterSeconds = "reset_after_seconds"
    case resetAt = "reset_at"
  }

  var remainingPercent: Double {
    max(0, 100 - usedPercent)
  }

  var usedPercentLabel: String {
    "\(Int(usedPercent.rounded()))%"
  }

  var remainingPercentLabel: String {
    "\(Int(remainingPercent.rounded()))%"
  }
}

struct Credits: Decodable {
  let hasCredits: Bool
  let unlimited: Bool

  enum CodingKeys: String, CodingKey {
    case hasCredits = "has_credits"
    case unlimited
  }
}

struct AuthProfileUsageSummary: Codable {
  let planType: String
  let isAllowed: Bool
  let limitReached: Bool
  let primaryUsedPercent: Double
  let primaryResetAt: TimeInterval
  let secondaryUsedPercent: Double?
  let secondaryResetAt: TimeInterval?
  let reviewUsedPercent: Double
  let reviewResetAt: TimeInterval

  enum CodingKeys: String, CodingKey {
    case planType
    case isAllowed
    case limitReached
    case primaryUsedPercent
    case primaryResetAt
    case secondaryUsedPercent
    case secondaryResetAt
    case reviewUsedPercent
    case reviewResetAt
  }

  init(snapshot: UsageSnapshot) {
    planType = snapshot.planType
    isAllowed = snapshot.rateLimit.allowed
    limitReached = snapshot.rateLimit.limitReached
    primaryUsedPercent = snapshot.rateLimit.primaryWindow.usedPercent
    primaryResetAt = snapshot.rateLimit.primaryWindow.resetAt
    secondaryUsedPercent = snapshot.rateLimit.secondaryWindow?.usedPercent
    secondaryResetAt = snapshot.rateLimit.secondaryWindow?.resetAt
    reviewUsedPercent = snapshot.codeReviewRateLimit.primaryWindow.usedPercent
    reviewResetAt = snapshot.codeReviewRateLimit.primaryWindow.resetAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    planType = try container.decode(String.self, forKey: .planType)
    isAllowed = try container.decodeIfPresent(Bool.self, forKey: .isAllowed) ?? true
    limitReached = try container.decodeIfPresent(Bool.self, forKey: .limitReached) ?? false
    primaryUsedPercent = try container.decode(Double.self, forKey: .primaryUsedPercent)
    primaryResetAt = try container.decode(TimeInterval.self, forKey: .primaryResetAt)
    secondaryUsedPercent = try container.decodeIfPresent(Double.self, forKey: .secondaryUsedPercent)
    secondaryResetAt = try container.decodeIfPresent(TimeInterval.self, forKey: .secondaryResetAt)
    reviewUsedPercent = try container.decode(Double.self, forKey: .reviewUsedPercent)
    reviewResetAt = try container.decode(TimeInterval.self, forKey: .reviewResetAt)
  }
}

struct AuthProfileRecord: Codable, Identifiable {
  let id: UUID
  let fingerprint: String
  let snapshotFileName: String
  var authMode: String?
  var accountID: String?
  var email: String?
  let createdAt: Date
  var lastSeenAt: Date
  var lastValidatedAt: Date?
  var latestUsage: AuthProfileUsageSummary?
  var validationError: String?
}

extension AuthProfileRecord {
  var isValid: Bool {
    validationError == nil && latestUsage != nil
  }

  /// Whether the subscription check failed (e.g. 402 Payment Required).
  /// These profiles should be hidden from the UI by default.
  var isSubscriptionFailed: Bool {
    validationError != nil
  }

  /// Short account identifier: email prefix if exists, else account ID suffix
  var accountIdentifier: String {
    if let email, !email.isEmpty {
      // Take part before @, e.g. "sinoon1218" from "sinoon1218@gmail.com"
      return email.components(separatedBy: "@").first ?? email
    }
    guard let accountID, accountID.count >= 4 else { return "????" }
    return String(accountID.suffix(4))
  }

  /// Plan badge text: "Plus" or "Team"
  var planBadge: String {
    if let usage = latestUsage {
      return usage.planDisplayName
    }
    // Fallback: no usage data yet
    return "—"
  }

  /// Display name for UI.
  /// Plus accounts: "Plus · sinoon1218"
  /// Team accounts: "Team · sinoon1218"
  var displayName: String {
    let plan = planBadge
    return "\(plan) · \(accountIdentifier)"
  }

  var statusText: String {
    if let validationError {
      return validationError
    }

    guard let latestUsage else {
      return "校验中"
    }

    if let blockingLabel = latestUsage.blockingLabel {
      return blockingLabel
    }

    if latestUsage.isRunningLow {
      return "即将耗尽"
    }

    return "可用"
  }

  var detailText: String {
    var parts: [String] = []

    if let latestUsage {
      parts.append(latestUsage.planDisplayName)
      parts.append(latestUsage.usageSummaryText)
    }

    if let lastValidatedAt {
      parts.append("\(lastValidatedAt.relativeDescription)校验")
    } else {
      parts.append("未校验")
    }

    return parts.joined(separator: " · ")
  }
}

extension AuthProfileUsageSummary {
  var planDisplayName: String {
    switch planType.lowercased() {
    case "team":
      return "Team"
    case "plus":
      return "Plus"
    default:
      return planType.capitalized
    }
  }

  var isWeeklyExhausted: Bool {
    guard let secondaryUsedPercent else { return false }
    return secondaryUsedPercent >= 100
  }

  var isPrimaryExhausted: Bool {
    primaryUsedPercent >= 100
  }

  var isBlocked: Bool {
    isWeeklyExhausted || isPrimaryExhausted || !isAllowed || limitReached
  }

  /// Effective overall availability percent (considering all quotas)
  /// When any quota is exhausted, this becomes 0
  var effectiveAvailablePercent: Double {
    if isBlocked { return 0 }
    return min(primaryRemainingPercent, secondaryRemainingPercent ?? 100)
  }

  var isRunningLow: Bool {
    if primaryRemainingPercent <= 15 {
      return true
    }

    if let secondaryUsedPercent {
      return max(0, 100 - secondaryUsedPercent) <= 15
    }

    return false
  }

  var blockingLabel: String? {
    if isWeeklyExhausted {
      if let resetLabel = nextResetLabel(for: secondaryResetAt) {
        return "周额度耗尽，\(resetLabel) 重置"
      }
      return "周额度已耗尽"
    }
    if isPrimaryExhausted {
      let resetLabel = nextResetLabel(for: primaryResetAt)
      if let resetLabel {
        return "5h 耗尽，\(resetLabel) 重置"
      }
      return "5h 额度已耗尽"
    }
    if !isAllowed || limitReached { return "不可用" }
    return nil
  }

  var usageSummaryText: String {
    let primaryText = "5h \(primaryRemainingPercentLabel)"
    let weeklyText: String
    if let secondaryRemainingPercentLabel {
      weeklyText = "周 \(secondaryRemainingPercentLabel)"
    } else {
      weeklyText = "周 --"
    }
    return "\(primaryText) · \(weeklyText)"
  }

  var primaryRemainingPercent: Double {
    max(0, 100 - primaryUsedPercent)
  }

  var primaryRemainingPercentLabel: String {
    "\(Int(primaryRemainingPercent.rounded()))%"
  }

  var secondaryRemainingPercent: Double? {
    secondaryUsedPercent.map { max(0, 100 - $0) }
  }

  var secondaryRemainingPercentLabel: String? {
    guard let secondaryRemainingPercent else { return nil }
    return "\(Int(secondaryRemainingPercent.rounded()))%"
  }

  var effectiveRemainingPercent: Double {
    min(primaryRemainingPercent, secondaryRemainingPercent ?? 100)
  }

  var switchSummaryText: String {
    if isBlocked, let resetText = nextBlockingResetLabel {
      return "\(resetText) 重置"
    }
    if let secondaryRemainingPercentLabel {
      return "5h \(primaryRemainingPercentLabel) · 周 \(secondaryRemainingPercentLabel)"
    }
    return "5h \(primaryRemainingPercentLabel)"
  }

  // MARK: - Reset time formatting

  /// The most relevant next reset label when blocked.
  /// Weekly exhausted → weekly reset; primary exhausted → primary reset.
  var nextBlockingResetLabel: String? {
    if isWeeklyExhausted {
      return nextResetLabel(for: secondaryResetAt)
    }
    if isPrimaryExhausted {
      return nextResetLabel(for: primaryResetAt)
    }
    return nil
  }

  /// Format a reset timestamp into a human-readable label.
  /// - Within today: "14:30"
  /// - Tomorrow: "明天 14:30"
  /// - Further: "3月22日"
  private func nextResetLabel(for resetAt: TimeInterval?) -> String? {
    guard let resetAt else { return nil }
    let date = Date(timeIntervalSince1970: resetAt)
    let now = Date()

    // Already past
    guard date > now else { return nil }

    let calendar = Calendar.current
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_Hans_CN")

    if calendar.isDateInToday(date) {
      formatter.dateFormat = "HH:mm"
      return formatter.string(from: date)
    } else if calendar.isDateInTomorrow(date) {
      formatter.dateFormat = "HH:mm"
      return "明天 \(formatter.string(from: date))"
    } else {
      formatter.dateFormat = "M月d日"
      return formatter.string(from: date)
    }
  }
}

extension Date {
  var relativeDescription: String {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: "zh_Hans_CN")
    return formatter.localizedString(for: self, relativeTo: .now)
  }
}
