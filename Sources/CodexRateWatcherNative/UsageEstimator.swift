import Foundation

struct BurnEstimate {
  let timeUntilExhausted: TimeInterval?
  let percentPerHour: Double?
  let statusText: String
}

enum UsageEstimator {
  static func estimatePrimary(from samples: [UsageSample], window: LimitWindow) -> BurnEstimate {
    estimate(
      samples: samples,
      currentResetAt: window.resetAt,
      currentRemainingPercent: window.remainingPercent,
      sampleWindow: 3 * 60 * 60,
      usedPercent: { $0.primaryUsedPercent },
      resetAt: { $0.primaryResetAt }
    )
  }

  static func estimateSecondary(from samples: [UsageSample], window: LimitWindow) -> BurnEstimate {
    estimate(
      samples: samples,
      currentResetAt: window.resetAt,
      currentRemainingPercent: window.remainingPercent,
      sampleWindow: 3 * 24 * 60 * 60,
      usedPercent: { $0.secondaryUsedPercent },
      resetAt: { $0.secondaryResetAt }
    )
  }

  static func estimateReview(from samples: [UsageSample], window: LimitWindow) -> BurnEstimate {
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
      return BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "收集样本中")
    }

    let cutoff = Date().addingTimeInterval(-sampleWindow)
    let recent = sameWindow.filter { $0.capturedAt >= cutoff }
    let workingSet = recent.isEmpty ? sameWindow : recent

    guard let first = workingSet.first,
          let last = workingSet.last,
          let firstPercent = usedPercent(first),
          let lastPercent = usedPercent(last)
    else {
      return BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "收集样本中")
    }

    let elapsed = last.capturedAt.timeIntervalSince(first.capturedAt)
    guard elapsed >= 5 * 60 else {
      return BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "样本不足，稍后估算")
    }

    let delta = lastPercent - firstPercent
    guard delta > 0.2 else {
      return BurnEstimate(timeUntilExhausted: nil, percentPerHour: 0, statusText: "消耗平稳")
    }

    let percentPerHour = delta / elapsed * 3600
    guard percentPerHour > 0 else {
      return BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "消耗平稳")
    }

    let timeUntilExhausted = currentRemainingPercent / percentPerHour * 3600
    let resetRemaining = Date(timeIntervalSince1970: currentResetAt).timeIntervalSinceNow
    if resetRemaining > 0, timeUntilExhausted > resetRemaining {
      return BurnEstimate(
        timeUntilExhausted: nil,
        percentPerHour: percentPerHour,
        statusText: "按当前速率，重置前不会耗尽"
      )
    }

    return BurnEstimate(
      timeUntilExhausted: timeUntilExhausted,
      percentPerHour: percentPerHour,
      statusText: "≈\(percentPerHour.formatted(.number.precision(.fractionLength(1))))%/h"
    )
  }
}
