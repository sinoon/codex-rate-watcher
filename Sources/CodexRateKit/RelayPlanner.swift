import Foundation

// MARK: - Relay Plan Data Structures

/// A single "leg" in the relay sequence — one account's contribution.
public struct RelayLeg: Sendable {
  public let profileID: UUID
  public let displayName: String
  /// When this leg starts (absolute time)
  public let startAt: Date
  /// When this leg is expected to exhaust (absolute time)
  public let estimatedExhaustAt: Date
  /// How long this leg covers (seconds)
  public var durationSeconds: TimeInterval { estimatedExhaustAt.timeIntervalSince(startAt) }
  /// Remaining percent when this leg begins
  public let startingRemainPercent: Double
  /// The burn rate used for this leg (percent per hour)
  public let burnRatePerHour: Double
  /// Reset time for this account's primary window
  public let primaryResetAt: Date
  /// Reset time for this account's weekly window (if any)
  public let weeklyResetAt: Date?

  public init(
    profileID: UUID,
    displayName: String,
    startAt: Date,
    estimatedExhaustAt: Date,
    startingRemainPercent: Double,
    burnRatePerHour: Double,
    primaryResetAt: Date,
    weeklyResetAt: Date? = nil
  ) {
    self.profileID = profileID
    self.displayName = displayName
    self.startAt = startAt
    self.estimatedExhaustAt = estimatedExhaustAt
    self.startingRemainPercent = startingRemainPercent
    self.burnRatePerHour = burnRatePerHour
    self.primaryResetAt = primaryResetAt
    self.weeklyResetAt = weeklyResetAt
  }
}

/// The complete relay plan across all accounts.
public struct RelayPlan: Sendable {
  /// Ordered sequence of relay legs (current account first)
  public let legs: [RelayLeg]
  /// When all accounts will be exhausted (nil = can survive until reset)
  public let allExhaustedAt: Date?
  /// Total relay coverage in seconds
  public let totalCoverageSeconds: TimeInterval
  /// Whether the relay can survive until the earliest primary reset
  public let canSurviveUntilReset: Bool
  /// The earliest primary reset time across all accounts
  public let earliestPrimaryReset: Date?
  /// Gap between relay exhaustion and next reset (negative = relay survives)
  public let gapToResetSeconds: TimeInterval?
  /// Strategy used for this plan
  public let strategy: RelayStrategy

  public var legCount: Int { legs.count }

  /// Human-readable summary of total coverage
  public var coverageSummary: String {
    let hours = Int(totalCoverageSeconds / 3600)
    let minutes = Int((totalCoverageSeconds.truncatingRemainder(dividingBy: 3600)) / 60)
    if hours > 0 {
      return minutes > 0 ? "\(hours)h\(minutes)m" : "\(hours)h"
    }
    return "\(max(1, minutes))m"
  }
}

/// Available relay strategies.
public enum RelayStrategy: String, Sendable {
  /// Use accounts with earliest reset time first — maximizes reset recycling
  case resetAware = "reset-aware"
  /// Use accounts with least remaining first — preserves high-capacity ones
  case greedy = "greedy"
  /// Use accounts with most remaining first — maximizes immediate runway
  case maxRunway = "max-runway"
}

/// Input data for a single account in the relay planner.
public struct RelayProfileInput: Sendable {
  public let profileID: UUID
  public let displayName: String
  public let isCurrent: Bool
  public let primaryRemainingPercent: Double
  public let primaryResetAt: TimeInterval
  public let weeklyRemainingPercent: Double?
  public let weeklyResetAt: TimeInterval?
  public let isBlocked: Bool
  public let validationError: String?

  public init(
    profileID: UUID,
    displayName: String,
    isCurrent: Bool,
    primaryRemainingPercent: Double,
    primaryResetAt: TimeInterval,
    weeklyRemainingPercent: Double? = nil,
    weeklyResetAt: TimeInterval? = nil,
    isBlocked: Bool = false,
    validationError: String? = nil
  ) {
    self.profileID = profileID
    self.displayName = displayName
    self.isCurrent = isCurrent
    self.primaryRemainingPercent = primaryRemainingPercent
    self.primaryResetAt = primaryResetAt
    self.weeklyRemainingPercent = weeklyRemainingPercent
    self.weeklyResetAt = weeklyResetAt
    self.isBlocked = isBlocked
    self.validationError = validationError
  }
}

// MARK: - Relay Planner

public enum RelayPlanner {

  /// Build a relay plan from available profiles.
  ///
  /// - Parameters:
  ///   - profiles: All known account profiles with their latest usage data.
  ///   - currentBurnRate: The current account's burn rate in percent/hour.
  ///     Falls back to a conservative default (18%/h) if nil.
  ///   - strategy: The relay ordering strategy. Defaults to `.resetAware`.
  /// - Returns: A `RelayPlan` describing the relay sequence and total coverage.
  public static func plan(
    profiles: [RelayProfileInput],
    currentBurnRate: Double?,
    strategy: RelayStrategy = .resetAware
  ) -> RelayPlan {
    let burnRate = currentBurnRate ?? 18.0  // Conservative default
    let now = Date()

    // Filter to usable profiles only
    let usable = profiles.filter { profile in
      profile.validationError == nil
        && !profile.isBlocked
        && effectiveRemaining(profile) > 0
    }

    guard !usable.isEmpty, burnRate > 0 else {
      return RelayPlan(
        legs: [],
        allExhaustedAt: now,
        totalCoverageSeconds: 0,
        canSurviveUntilReset: false,
        earliestPrimaryReset: profiles.map { Date(timeIntervalSince1970: $0.primaryResetAt) }.min(),
        gapToResetSeconds: nil,
        strategy: strategy
      )
    }

    // Separate current account from others
    let currentProfile = usable.first(where: \.isCurrent)
    let otherProfiles = usable.filter { !$0.isCurrent }

    // Sort other profiles based on strategy
    let sortedOthers = sortByStrategy(otherProfiles, strategy: strategy)

    // Build the ordered queue: current first, then sorted others
    var queue: [RelayProfileInput] = []
    if let current = currentProfile {
      queue.append(current)
    }
    queue.append(contentsOf: sortedOthers)

    // Build relay legs
    var legs: [RelayLeg] = []
    var cursor = now

    for profile in queue {
      let remaining = effectiveRemaining(profile)
      guard remaining > 0, burnRate > 0 else { continue }

      let timeLeftSeconds = (remaining / burnRate) * 3600
      let exhaustAt = cursor.addingTimeInterval(timeLeftSeconds)

      let leg = RelayLeg(
        profileID: profile.profileID,
        displayName: profile.displayName,
        startAt: cursor,
        estimatedExhaustAt: exhaustAt,
        startingRemainPercent: remaining,
        burnRatePerHour: burnRate,
        primaryResetAt: Date(timeIntervalSince1970: profile.primaryResetAt),
        weeklyResetAt: profile.weeklyResetAt.map { Date(timeIntervalSince1970: $0) }
      )
      legs.append(leg)
      cursor = exhaustAt
    }

    let totalCoverage = cursor.timeIntervalSince(now)
    let earliestPrimaryReset = usable.map { Date(timeIntervalSince1970: $0.primaryResetAt) }
      .filter { $0 > now }
      .min()

    let canSurvive: Bool
    let gap: TimeInterval?
    if let reset = earliestPrimaryReset {
      gap = cursor.timeIntervalSince(reset)
      canSurvive = cursor >= reset  // relay lasts until or beyond reset
    } else {
      gap = nil
      canSurvive = false
    }

    return RelayPlan(
      legs: legs,
      allExhaustedAt: canSurvive ? nil : cursor,
      totalCoverageSeconds: totalCoverage,
      canSurviveUntilReset: canSurvive,
      earliestPrimaryReset: earliestPrimaryReset,
      gapToResetSeconds: gap,
      strategy: strategy
    )
  }

  /// Convenience: build RelayProfileInput from AuthProfileRecord + activeProfileID.
  public static func inputs(
    from profiles: [AuthProfileRecord],
    activeProfileID: UUID?
  ) -> [RelayProfileInput] {
    profiles.compactMap { profile -> RelayProfileInput? in
      guard let usage = profile.latestUsage else { return nil }
      return RelayProfileInput(
        profileID: profile.id,
        displayName: profile.displayName,
        isCurrent: profile.id == activeProfileID,
        primaryRemainingPercent: usage.primaryRemainingPercent,
        primaryResetAt: usage.primaryResetAt,
        weeklyRemainingPercent: usage.secondaryRemainingPercent,
        weeklyResetAt: usage.secondaryResetAt,
        isBlocked: usage.isBlocked,
        validationError: profile.validationError
      )
    }
  }

  /// The next leg to switch to (excluding the current leg).
  public static func nextLeg(in plan: RelayPlan) -> RelayLeg? {
    guard plan.legs.count > 1 else { return nil }
    return plan.legs[1]
  }

  /// Whether the current account is about to exhaust and we should switch.
  /// Returns the next leg to switch to, or nil if no switch is needed.
  public static func shouldAutoRelay(
    plan: RelayPlan,
    preemptSeconds: TimeInterval = 300  // switch 5 min before exhaustion
  ) -> RelayLeg? {
    guard let currentLeg = plan.legs.first,
          plan.legs.count > 1 else {
      return nil
    }

    let timeUntilExhaust = currentLeg.estimatedExhaustAt.timeIntervalSinceNow
    if timeUntilExhaust <= preemptSeconds && timeUntilExhaust > 0 {
      return plan.legs[1]
    }

    return nil
  }

  // MARK: - Private Helpers

  /// Effective remaining percent considering both primary and weekly windows.
  private static func effectiveRemaining(_ profile: RelayProfileInput) -> Double {
    let primary = profile.primaryRemainingPercent
    let weekly = profile.weeklyRemainingPercent ?? 100
    return min(primary, weekly)
  }

  /// Sort profiles based on the chosen strategy.
  private static func sortByStrategy(
    _ profiles: [RelayProfileInput],
    strategy: RelayStrategy
  ) -> [RelayProfileInput] {
    switch strategy {
    case .resetAware:
      // Use accounts whose primary window resets soonest first.
      // Rationale: after they exhaust, they'll reset and be available again.
      return profiles.sorted { a, b in
        if a.primaryResetAt != b.primaryResetAt {
          return a.primaryResetAt < b.primaryResetAt
        }
        // Tiebreak: less remaining first (use them up since they reset soon)
        return effectiveRemaining(a) < effectiveRemaining(b)
      }

    case .greedy:
      // Use accounts with least remaining first — preserve heavy hitters.
      return profiles.sorted {
        effectiveRemaining($0) < effectiveRemaining($1)
      }

    case .maxRunway:
      // Use accounts with most remaining first — maximize immediate runway.
      return profiles.sorted {
        effectiveRemaining($0) > effectiveRemaining($1)
      }
    }
  }
}
