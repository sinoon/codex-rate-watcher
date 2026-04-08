import Foundation

public struct UsageSnapshot: Decodable, Sendable {
  public let planType: String
  public let rateLimit: UsageLimit
  public let codeReviewRateLimit: UsageLimit
  public let credits: Credits

  enum CodingKeys: String, CodingKey {
    case planType = "plan_type"
    case rateLimit = "rate_limit"
    case codeReviewRateLimit = "code_review_rate_limit"
    case credits
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    planType = try container.decode(String.self, forKey: .planType)
    rateLimit = try container.decode(UsageLimit.self, forKey: .rateLimit)
    codeReviewRateLimit = (try? container.decodeIfPresent(UsageLimit.self, forKey: .codeReviewRateLimit))
      ?? UsageLimit.reviewFallback(from: rateLimit.primaryWindow)
    credits = try container.decode(Credits.self, forKey: .credits)
  }
}

public struct UsageLimit: Decodable, Sendable {
  public let allowed: Bool
  public let limitReached: Bool
  public let primaryWindow: LimitWindow
  public let secondaryWindow: LimitWindow?

  enum CodingKeys: String, CodingKey {
    case allowed
    case limitReached = "limit_reached"
    case primaryWindow = "primary_window"
    case secondaryWindow = "secondary_window"
  }

  public init(
    allowed: Bool,
    limitReached: Bool,
    primaryWindow: LimitWindow,
    secondaryWindow: LimitWindow? = nil
  ) {
    self.allowed = allowed
    self.limitReached = limitReached
    self.primaryWindow = primaryWindow
    self.secondaryWindow = secondaryWindow
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    allowed = try container.decode(Bool.self, forKey: .allowed)
    limitReached = try container.decode(Bool.self, forKey: .limitReached)
    primaryWindow = try container.decode(LimitWindow.self, forKey: .primaryWindow)
    secondaryWindow = try container.decodeIfPresent(LimitWindow.self, forKey: .secondaryWindow)
  }

  static func reviewFallback(from primaryWindow: LimitWindow) -> UsageLimit {
    UsageLimit(
      allowed: true,
      limitReached: false,
      primaryWindow: LimitWindow(
        usedPercent: 0,
        limitWindowSeconds: primaryWindow.limitWindowSeconds,
        resetAfterSeconds: primaryWindow.resetAfterSeconds,
        resetAt: primaryWindow.resetAt
      )
    )
  }
}

public struct LimitWindow: Decodable, Sendable {
  public let usedPercent: Double
  public let limitWindowSeconds: Int
  public let resetAfterSeconds: Int
  public let resetAt: TimeInterval

  enum CodingKeys: String, CodingKey {
    case usedPercent = "used_percent"
    case limitWindowSeconds = "limit_window_seconds"
    case resetAfterSeconds = "reset_after_seconds"
    case resetAt = "reset_at"
  }

  public init(
    usedPercent: Double,
    limitWindowSeconds: Int,
    resetAfterSeconds: Int,
    resetAt: TimeInterval
  ) {
    self.usedPercent = usedPercent
    self.limitWindowSeconds = limitWindowSeconds
    self.resetAfterSeconds = resetAfterSeconds
    self.resetAt = resetAt
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    usedPercent = try container.decode(Double.self, forKey: .usedPercent)
    limitWindowSeconds = try container.decode(Int.self, forKey: .limitWindowSeconds)
    resetAfterSeconds = try container.decode(Int.self, forKey: .resetAfterSeconds)
    resetAt = try container.decode(TimeInterval.self, forKey: .resetAt)
  }

  public var remainingPercent: Double {
    max(0, 100 - usedPercent)
  }

  public var usedPercentLabel: String {
    "\(Int(usedPercent.rounded()))%"
  }

  public var remainingPercentLabel: String {
    "\(Int(remainingPercent.rounded()))%"
  }
}

public struct Credits: Decodable, Sendable {
  public let hasCredits: Bool
  public let unlimited: Bool

  enum CodingKeys: String, CodingKey {
    case hasCredits = "has_credits"
    case unlimited
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    hasCredits = try container.decode(Bool.self, forKey: .hasCredits)
    unlimited = try container.decode(Bool.self, forKey: .unlimited)
  }
}

public struct AuthProfileUsageSummary: Codable, Sendable {
  public let planType: String
  public let isAllowed: Bool
  public let limitReached: Bool
  public let primaryUsedPercent: Double
  public let primaryResetAt: TimeInterval
  public let secondaryUsedPercent: Double?
  public let secondaryResetAt: TimeInterval?
  public let reviewUsedPercent: Double
  public let reviewResetAt: TimeInterval

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

  public init(snapshot: UsageSnapshot) {
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

  public init(from decoder: Decoder) throws {
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

public struct AuthProfileRecord: Codable, Identifiable, Sendable {
  public let id: UUID
  public var fingerprint: String
  public let snapshotFileName: String
  public var authMode: String?
  public var accountID: String?
  public var email: String?
  public let createdAt: Date
  public var lastSeenAt: Date
  public var lastValidatedAt: Date?
  public var latestUsage: AuthProfileUsageSummary?
  public var validationError: String?

  public init(
    id: UUID,
    fingerprint: String,
    snapshotFileName: String,
    authMode: String? = nil,
    accountID: String? = nil,
    email: String? = nil,
    createdAt: Date,
    lastSeenAt: Date,
    lastValidatedAt: Date? = nil,
    latestUsage: AuthProfileUsageSummary? = nil,
    validationError: String? = nil
  ) {
    self.id = id
    self.fingerprint = fingerprint
    self.snapshotFileName = snapshotFileName
    self.authMode = authMode
    self.accountID = accountID
    self.email = email
    self.createdAt = createdAt
    self.lastSeenAt = lastSeenAt
    self.lastValidatedAt = lastValidatedAt
    self.latestUsage = latestUsage
    self.validationError = validationError
  }
}

public enum AuthProfileSwitchState: Equatable, Sendable {
  case ready
  case waitingForReset
  case unavailable
  case validating
}

public struct ManagedCodexAccount: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let email: String
  public let managedHomePath: String
  public let accountID: String?
  public let createdAt: Date
  public let updatedAt: Date
  public let lastAuthenticatedAt: Date

  public init(
    id: UUID,
    email: String,
    managedHomePath: String,
    accountID: String? = nil,
    createdAt: Date,
    updatedAt: Date,
    lastAuthenticatedAt: Date
  ) {
    self.id = id
    self.email = email
    self.managedHomePath = managedHomePath
    self.accountID = accountID
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.lastAuthenticatedAt = lastAuthenticatedAt
  }
}

public struct ManagedCodexAccountSet: Codable, Equatable, Sendable {
  public let version: Int
  public let accounts: [ManagedCodexAccount]

  public init(version: Int = 1, accounts: [ManagedCodexAccount]) {
    self.version = version
    self.accounts = accounts
  }

  public func account(id: UUID) -> ManagedCodexAccount? {
    accounts.first { $0.id == id }
  }

  public func account(email: String) -> ManagedCodexAccount? {
    let normalizedEmail = Self.normalizeEmail(email)
    return accounts.first { Self.normalizeEmail($0.email) == normalizedEmail }
  }

  private static func normalizeEmail(_ email: String) -> String {
    email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}

extension AuthProfileRecord {
  public var isValid: Bool {
    validationError == nil && latestUsage != nil
  }

  public var switchState: AuthProfileSwitchState {
    if validationError != nil {
      return .unavailable
    }

    guard let latestUsage else {
      return .validating
    }

    if latestUsage.isPrimaryExhausted || latestUsage.isWeeklyExhausted {
      return .waitingForReset
    }

    if latestUsage.isBlocked {
      return .unavailable
    }

    return .ready
  }

  public var isReadyForImmediateSwitch: Bool {
    switchState == .ready
  }

  public var isWaitingForReset: Bool {
    switchState == .waitingForReset
  }

  /// Whether the subscription check failed (e.g. 402 Payment Required).
  /// These profiles should be hidden from the UI by default.
  public var isSubscriptionFailed: Bool {
    validationError != nil
  }

  /// Short account identifier: email prefix if exists, else account ID suffix
  public var accountIdentifier: String {
    if let email, !email.isEmpty {
      // Take part before @, e.g. "sinoon1218" from "sinoon1218@gmail.com"
      return email.components(separatedBy: "@").first ?? email
    }
    guard let accountID, accountID.count >= 4 else { return "????" }
    return String(accountID.suffix(4))
  }

  /// Plan badge text: "Plus" or "Team"
  public var planBadge: String {
    if let usage = latestUsage {
      return usage.planDisplayName
    }
    // Fallback: no usage data yet
    return "—"
  }

  /// Display name for UI.
  /// Plus accounts: "Plus · sinoon1218"
  /// Team accounts: "Team · sinoon1218"
  public var displayName: String {
    let plan = planBadge
    return "\(plan) · \(accountIdentifier)"
  }

  public var statusText: String {
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

  public var detailText: String {
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
  public var planDisplayName: String {
    switch planType.lowercased() {
    case "team":
      return "Team"
    case "plus":
      return "Plus"
    default:
      return planType.capitalized
    }
  }

  public var isWeeklyExhausted: Bool {
    guard let secondaryUsedPercent else { return false }
    return secondaryUsedPercent >= 100
  }

  public var isPrimaryExhausted: Bool {
    primaryUsedPercent >= 100
  }

  public var isBlocked: Bool {
    isWeeklyExhausted || isPrimaryExhausted || !isAllowed || limitReached
  }

  /// Effective overall availability percent (considering all quotas)
  /// When any quota is exhausted, this becomes 0
  public var effectiveAvailablePercent: Double {
    if isBlocked { return 0 }
    return min(primaryRemainingPercent, secondaryRemainingPercent ?? 100)
  }

  public var isRunningLow: Bool {
    if primaryRemainingPercent <= 15 {
      return true
    }

    if let secondaryUsedPercent {
      return max(0, 100 - secondaryUsedPercent) <= 15
    }

    return false
  }

  public var blockingLabel: String? {
    if isWeeklyExhausted {
      if let resetLabel = nextResetLabel(for: secondaryResetAt) {
        return "周额度耗尽 · \(resetLabel) 重置"
      }
      return "周额度耗尽"
    }
    if isPrimaryExhausted {
      let resetLabel = nextResetLabel(for: primaryResetAt)
      let weeklyLabel = secondaryRemainingPercentLabel.map { "周 \($0)" } ?? "周 --"
      if let resetLabel {
        return "5h耗尽 · \(weeklyLabel) · \(resetLabel) 重置"
      }
      return "5h耗尽 · \(weeklyLabel)"
    }
    if !isAllowed || limitReached { return "不可用" }
    return nil
  }

  public var usageSummaryText: String {
    let primaryText = "5h \(primaryRemainingPercentLabel)"
    let weeklyText: String
    if let secondaryRemainingPercentLabel {
      weeklyText = "周 \(secondaryRemainingPercentLabel)"
    } else {
      weeklyText = "周 --"
    }
    return "\(primaryText) · \(weeklyText)"
  }

  public var primaryRemainingPercent: Double {
    max(0, 100 - primaryUsedPercent)
  }

  public var primaryRemainingPercentLabel: String {
    "\(Int(primaryRemainingPercent.rounded()))%"
  }

  public var secondaryRemainingPercent: Double? {
    secondaryUsedPercent.map { max(0, 100 - $0) }
  }

  public var secondaryRemainingPercentLabel: String? {
    guard let secondaryRemainingPercent else { return nil }
    return "\(Int(secondaryRemainingPercent.rounded()))%"
  }

  public var effectiveRemainingPercent: Double {
    min(primaryRemainingPercent, secondaryRemainingPercent ?? 100)
  }

  public var switchSummaryText: String {
    let baseText = switchSummaryBaseText

    if isWeeklyExhausted || isPrimaryExhausted {
      if let resetLabel = nextBlockingResetLabel {
        return "\(baseText) · \(resetLabel) 重置"
      }
      return baseText
    }

    return baseText
  }

  public var profileListSummaryText: String {
    let baseText = switchSummaryBaseText

    guard let resetAt = nextRelevantResetAt,
          let resetSummary = QuotaTimeFormatter.resetCountdownLabel(
            for: resetAt,
            timeZone: .autoupdatingCurrent
          ) else {
      return baseText
    }

    return "\(baseText) · \(resetSummary)"
  }

  private var switchSummaryBaseText: String {
    if let blockingLabel {
      if isWeeklyExhausted {
        return "周额度耗尽"
      }
      if isPrimaryExhausted {
        let weeklyLabel = secondaryRemainingPercentLabel.map { "周 \($0)" } ?? "周 --"
        return "5h耗尽 · \(weeklyLabel)"
      }
      return blockingLabel
    }
    if let secondaryRemainingPercentLabel {
      return "5h \(primaryRemainingPercentLabel) · 周 \(secondaryRemainingPercentLabel)"
    }
    return "5h \(primaryRemainingPercentLabel)"
  }

  // MARK: - Reset time formatting

  /// The most relevant next reset label when blocked.
  /// Weekly exhausted → weekly reset; primary exhausted → primary reset.
  public var nextBlockingResetLabel: String? {
    if isWeeklyExhausted {
      return nextResetLabel(for: secondaryResetAt)
    }
    if isPrimaryExhausted {
      return nextResetLabel(for: primaryResetAt)
    }
    return nil
  }

  public var nextBlockingResetAt: TimeInterval? {
    if isWeeklyExhausted {
      return secondaryResetAt
    }
    if isPrimaryExhausted {
      return primaryResetAt
    }
    return nil
  }

  public var nextRelevantResetAt: TimeInterval? {
    if let blockingResetAt = nextBlockingResetAt {
      return blockingResetAt
    }
    return primaryResetAt
  }

  /// Format a reset timestamp into a human-readable label.
  /// - Within today: "14:30"
  /// - Tomorrow: "明天 14:30"
  /// - Further: "3月22日"
  private func nextResetLabel(for resetAt: TimeInterval?) -> String? {
    guard let resetAt else { return nil }
    return QuotaTimeFormatter.resetLabel(
      for: resetAt,
      timeZone: .autoupdatingCurrent,
      style: .chineseMonthDay
    )
  }
}

extension Date {
  public var relativeDescription: String {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: "zh_Hans_CN")
    return formatter.localizedString(for: self, relativeTo: .now)
  }
}
