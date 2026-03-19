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
    "\(Int(remainingPercent.rounded()))% left"
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

  var displayName: String {
    if let accountID, !accountID.isEmpty {
      if accountID.count <= 12 {
        return "Account \(accountID)"
      }
      let prefix = accountID.prefix(6)
      let suffix = accountID.suffix(4)
      return "Account \(prefix)...\(suffix)"
    }

    return "Profile \(fingerprint.prefix(8))"
  }

  var statusText: String {
    if let validationError {
      return validationError
    }

    guard let latestUsage else {
      return "Waiting for validation"
    }

    if let blockingLabel = latestUsage.blockingLabel {
      return "\(latestUsage.planType.uppercased()) · \(blockingLabel)"
    }

    return "\(latestUsage.planType.uppercased()) · \(latestUsage.primaryRemainingPercentLabel)"
  }

  var detailText: String {
    var parts: [String] = []

    if let latestUsage {
      parts.append(latestUsage.usageSummaryText)
    }

    if let authMode, !authMode.isEmpty {
      parts.append(authMode)
    }

    if let lastValidatedAt {
      parts.append("validated \(lastValidatedAt.relativeDescription)")
    }

    parts.append("seen \(lastSeenAt.relativeDescription)")
    return parts.joined(separator: " · ")
  }
}

extension AuthProfileUsageSummary {
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

  var blockingLabel: String? {
    if isWeeklyExhausted {
      return "Weekly exhausted"
    }

    if isPrimaryExhausted {
      return "5h exhausted"
    }

    if !isAllowed || limitReached {
      return "Blocked"
    }

    return nil
  }

  var usageSummaryText: String {
    let primaryText = "5h \(primaryRemainingPercentLabel)"
    let weeklyText: String
    if let secondaryUsedPercent {
      weeklyText = "W \(Int(max(0, 100 - secondaryUsedPercent).rounded()))% left"
    } else {
      weeklyText = "W -- left"
    }
    return "\(primaryText) · \(weeklyText)"
  }

  var primaryRemainingPercent: Double {
    max(0, 100 - primaryUsedPercent)
  }

  var primaryRemainingPercentLabel: String {
    "\(Int(primaryRemainingPercent.rounded()))% left"
  }
}

extension Date {
  var relativeDescription: String {
    RelativeDateTimeFormatter().localizedString(for: self, relativeTo: .now)
  }
}
