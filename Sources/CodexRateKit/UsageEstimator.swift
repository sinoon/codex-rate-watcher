import Foundation

public struct BurnEstimate: Sendable {
  public let timeUntilExhausted: TimeInterval?
  public let percentPerHour: Double?
  public let statusText: String

  public init(timeUntilExhausted: TimeInterval?, percentPerHour: Double?, statusText: String) {
    self.timeUntilExhausted = timeUntilExhausted
    self.percentPerHour = percentPerHour
    self.statusText = statusText
  }
}

public enum UsageEstimator {
  public static func estimatePrimary(from samples: [UsageSample], window: LimitWindow) -> BurnEstimate {
    estimate(
      samples: samples,
      currentResetAt: window.resetAt,
      currentRemainingPercent: window.remainingPercent,
      sampleWindow: 3 * 60 * 60,
      usedPercent: { $0.primaryUsedPercent },
      resetAt: { $0.primaryResetAt }
    )
  }

  public static func estimateSecondary(from samples: [UsageSample], window: LimitWindow) -> BurnEstimate {
    estimate(
      samples: samples,
      currentResetAt: window.resetAt,
      currentRemainingPercent: window.remainingPercent,
      sampleWindow: 3 * 24 * 60 * 60,
      usedPercent: { $0.secondaryUsedPercent },
      resetAt: { $0.secondaryResetAt }
    )
  }

  public static func estimateReview(from samples: [UsageSample], window: LimitWindow) -> BurnEstimate {
    estimate(
      samples: samples,
      currentResetAt: window.resetAt,
      currentRemainingPercent: window.remainingPercent,
      sampleWindow: 3 * 24 * 60 * 60,
      usedPercent: { $0.reviewUsedPercent },
      resetAt: { $0.reviewResetAt }
    )
  }

  private static func estimate(
    samples: [UsageSample],
    currentResetAt: TimeInterval,
    currentRemainingPercent: Double,
    sampleWindow: TimeInterval,
    usedPercent: (UsageSample) -> Double?,
    resetAt: (UsageSample) -> TimeInterval?
  ) -> BurnEstimate {
    let sameWindow = samples
      .filter { sample in
        guard let sampleResetAt = resetAt(sample), let percent = usedPercent(sample) else {
          return false
        }
        return abs(sampleResetAt - currentResetAt) < 1 && percent >= 0
      }
      .sorted { $0.capturedAt < $1.capturedAt }

    guard !sameWindow.isEmpty else {
      return BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "采样中")
    }

    let cutoff = Date().addingTimeInterval(-sampleWindow)
    let recent = sameWindow.filter { $0.capturedAt >= cutoff }
    let workingSet = recent.isEmpty ? sameWindow : recent

    guard let first = workingSet.first,
          let last = workingSet.last,
          let firstPercent = usedPercent(first),
          let lastPercent = usedPercent(last)
    else {
      return BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "采样中")
    }

    let elapsed = last.capturedAt.timeIntervalSince(first.capturedAt)
    guard elapsed >= 5 * 60 else {
      return BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "估算中")
    }

    let delta = lastPercent - firstPercent
    guard delta > 0.2 else {
      return BurnEstimate(timeUntilExhausted: nil, percentPerHour: 0, statusText: "平稳")
    }

    let percentPerHour = delta / elapsed * 3600
    guard percentPerHour > 0 else {
      return BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "平稳")
    }

    let timeUntilExhausted = currentRemainingPercent / percentPerHour * 3600
    let resetRemaining = Date(timeIntervalSince1970: currentResetAt).timeIntervalSinceNow
    if resetRemaining > 0, timeUntilExhausted > resetRemaining {
      return BurnEstimate(
        timeUntilExhausted: nil,
        percentPerHour: percentPerHour,
        statusText: "充足"
      )
    }

    return BurnEstimate(
      timeUntilExhausted: timeUntilExhausted,
      percentPerHour: percentPerHour,
      statusText: "≈\(percentPerHour.formatted(.number.precision(.fractionLength(1))))%/h"
    )
  }
}
