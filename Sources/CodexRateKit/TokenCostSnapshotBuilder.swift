import Foundation

enum TokenCostSnapshotBuilder {
  static func buildSnapshot(
    days: [String: TokenCostCachedDay],
    now: Date,
    source: TokenCostSourceSummary? = nil,
    localSummary: TokenCostLocalSummary? = nil,
    accountSummaries: [TokenCostAccountSummary] = []
  ) -> TokenCostSnapshot {
    let calendar = Calendar.current
    let todayKey = dayKey(from: now)
    let earliestDate = calendar.date(byAdding: .day, value: -89, to: now) ?? now
    let earliestKey = dayKey(from: earliestDate)

    let dayKeys = days.keys.sorted().filter { $0 >= earliestKey && $0 <= todayKey }
    let dailyEntries = dayKeys.compactMap { buildDailyEntry(dayKey: $0, cachedDay: days[$0]) }

    let windows = [7, 30, 90].map {
      buildWindowSummary(from: dailyEntries, windowDays: $0, now: now)
    }

    let sevenDayWindow = windows.first { $0.windowDays == 7 }
    let thirtyDayWindow = windows.first { $0.windowDays == 30 }
    let ninetyDayWindow = windows.first { $0.windowDays == 90 }
    let todayEntry = dailyEntries.last { $0.date == todayKey }

    return TokenCostSnapshot(
      todayTokens: todayEntry?.totalTokens,
      todayCostUSD: todayEntry?.costUSD,
      last7DaysTokens: sevenDayWindow?.totalTokens,
      last7DaysCostUSD: sevenDayWindow?.totalCostUSD,
      last30DaysTokens: thirtyDayWindow?.totalTokens,
      last30DaysCostUSD: thirtyDayWindow?.totalCostUSD,
      last90DaysTokens: ninetyDayWindow?.totalTokens,
      last90DaysCostUSD: ninetyDayWindow?.totalCostUSD,
      averageDailyTokens: thirtyDayWindow?.averageDailyTokens,
      averageDailyCostUSD: thirtyDayWindow?.averageDailyCostUSD,
      modelSummaries: thirtyDayWindow?.modelSummaries ?? [],
      hourly: thirtyDayWindow?.hourly ?? [],
      alerts: thirtyDayWindow?.alerts ?? [],
      narrative: thirtyDayWindow?.narrative ?? .init(),
      windows: windows,
      hasPartialPricing: thirtyDayWindow?.hasPartialPricing ?? false,
      daily: dailyEntries,
      source: source,
      localSummary: localSummary,
      accountSummaries: accountSummaries,
      updatedAt: now
    )
  }

  private static func buildDailyEntry(dayKey: String, cachedDay: TokenCostCachedDay?) -> TokenCostDailyEntry? {
    guard let cachedDay else { return nil }

    let sortedModels = cachedDay.models.keys.sorted()
    var dayInput = 0
    var dayCacheRead = 0
    var dayOutput = 0
    var dayCost = 0.0
    var dayCostKnown = true
    var breakdowns: [TokenCostModelBreakdown] = []

    for model in sortedModels {
      let bucket = cachedDay.models[model] ?? TokenCostBucket()
      let modelCost = TokenCostPricing.codexCostUSD(
        model: model,
        inputTokens: bucket.inputTokens,
        cachedInputTokens: bucket.cacheReadTokens,
        outputTokens: bucket.outputTokens
      )

      if modelCost == nil, bucket.totalTokens > 0 {
        dayCostKnown = false
      } else {
        dayCost += modelCost ?? 0
      }

      dayInput += bucket.inputTokens
      dayCacheRead += bucket.cacheReadTokens
      dayOutput += bucket.outputTokens
      breakdowns.append(
        TokenCostModelBreakdown(
          modelName: model,
          inputTokens: bucket.inputTokens,
          cacheReadTokens: bucket.cacheReadTokens,
          outputTokens: bucket.outputTokens,
          costUSD: modelCost,
          totalTokens: bucket.totalTokens
        )
      )
    }

    let hourlyBreakdowns = cachedDay.hours.keys.sorted().map { hour -> TokenCostHourlyEntry in
      let hourModels = cachedDay.hours[hour]?.models ?? [:]
      var inputTokens = 0
      var cacheReadTokens = 0
      var outputTokens = 0
      var cost = 0.0
      var costKnown = true

      for (model, bucket) in hourModels {
        inputTokens += bucket.inputTokens
        cacheReadTokens += bucket.cacheReadTokens
        outputTokens += bucket.outputTokens

        let hourCost = TokenCostPricing.codexCostUSD(
          model: model,
          inputTokens: bucket.inputTokens,
          cachedInputTokens: bucket.cacheReadTokens,
          outputTokens: bucket.outputTokens
        )
        if hourCost == nil, bucket.totalTokens > 0 {
          costKnown = false
        } else {
          cost += hourCost ?? 0
        }
      }

      return TokenCostHourlyEntry(
        hour: hour,
        inputTokens: inputTokens,
        cacheReadTokens: cacheReadTokens,
        outputTokens: outputTokens,
        totalTokens: inputTokens + outputTokens,
        costUSD: costKnown ? cost : nil
      )
    }

    let totalTokens = dayInput + dayOutput
    return TokenCostDailyEntry(
      date: dayKey,
      inputTokens: dayInput,
      cacheReadTokens: dayCacheRead,
      outputTokens: dayOutput,
      totalTokens: totalTokens,
      costUSD: dayCostKnown ? dayCost : nil,
      modelsUsed: sortedModels,
      modelBreakdowns: sortBreakdowns(breakdowns),
      hourlyBreakdowns: hourlyBreakdowns
    )
  }

  private static func buildWindowSummary(
    from dailyEntries: [TokenCostDailyEntry],
    windowDays: Int,
    now: Date
  ) -> TokenCostWindowSummary {
    let calendar = Calendar.current
    let startDate = calendar.date(byAdding: .day, value: -(windowDays - 1), to: now) ?? now
    let startKey = dayKey(from: startDate)
    let endKey = dayKey(from: now)
    let rangeEntries = dailyEntries.filter { $0.date >= startKey && $0.date <= endKey }
    let activeEntries = rangeEntries.filter { ($0.totalTokens ?? 0) > 0 }
    let totalInput = activeEntries.reduce(0) { $0 + ($1.inputTokens ?? 0) }
    let totalCacheRead = activeEntries.reduce(0) { $0 + ($1.cacheReadTokens ?? 0) }
    let totalTokensValue = activeEntries.reduce(0) { $0 + ($1.totalTokens ?? 0) }
    let hasTokens = totalTokensValue > 0
    let hasPartialPricing = activeEntries.contains { ($0.totalTokens ?? 0) > 0 && $0.costUSD == nil }
    let totalCostValue = activeEntries.reduce(0.0) { $0 + ($1.costUSD ?? 0) }
    let totalCostUSD = hasTokens ? (hasPartialPricing ? nil : totalCostValue) : nil
    let averageDailyTokens = hasTokens ? Double(totalTokensValue) / Double(windowDays) : nil
    let averageDailyCostUSD = totalCostUSD.map { $0 / Double(windowDays) }
    let cacheShare = totalInput > 0 ? Double(totalCacheRead) / Double(totalInput) : nil

    let modelSummaries = buildModelSummaries(
      from: activeEntries,
      totalTokens: totalTokensValue,
      totalCostUSD: totalCostUSD
    )
    let hourly = buildHourlyEntries(from: activeEntries)
    let dominantModelName = modelSummaries.first?.modelName
    let alerts = deriveAlerts(
      windowDays: windowDays,
      activeEntries: activeEntries,
      cacheShare: cacheShare,
      dominantModelName: dominantModelName,
      modelSummaries: modelSummaries,
      hasPartialPricing: hasPartialPricing,
      totalCostUSD: totalCostUSD
    )
    let narrative = deriveNarrative(
      windowDays: windowDays,
      activeEntries: activeEntries,
      cacheShare: cacheShare,
      dominantModelName: dominantModelName,
      modelSummaries: modelSummaries,
      hasPartialPricing: hasPartialPricing,
      totalCostUSD: totalCostUSD,
      totalTokens: hasTokens ? totalTokensValue : nil
    )

    return TokenCostWindowSummary(
      windowDays: windowDays,
      totalTokens: hasTokens ? totalTokensValue : nil,
      totalCostUSD: totalCostUSD,
      averageDailyTokens: averageDailyTokens,
      averageDailyCostUSD: averageDailyCostUSD,
      activeDayCount: activeEntries.count,
      cacheShare: cacheShare,
      dominantModelName: dominantModelName,
      modelSummaries: modelSummaries,
      hourly: hourly,
      alerts: alerts,
      narrative: narrative,
      hasPartialPricing: hasPartialPricing
    )
  }

  private static func buildModelSummaries(
    from dailyEntries: [TokenCostDailyEntry],
    totalTokens: Int,
    totalCostUSD: Double?
  ) -> [TokenCostModelSummary] {
    var states: [String: ModelAggregateState] = [:]

    for entry in dailyEntries {
      for breakdown in entry.modelBreakdowns ?? [] {
        var state = states[breakdown.modelName] ?? ModelAggregateState()
        state.inputTokens += breakdown.inputTokens ?? 0
        state.cacheReadTokens += breakdown.cacheReadTokens ?? 0
        state.outputTokens += breakdown.outputTokens ?? 0
        state.totalTokens += breakdown.totalTokens ?? 0
        if let costUSD = breakdown.costUSD {
          state.costUSD += costUSD
        } else if (breakdown.totalTokens ?? 0) > 0 {
          state.costKnown = false
        }
        states[breakdown.modelName] = state
      }
    }

    let hasPartialPricing = totalTokens > 0 && totalCostUSD == nil
    return states.map { modelName, state in
      let tokenShare = totalTokens > 0 ? Double(state.totalTokens) / Double(totalTokens) : nil
      let costValue = state.costKnown ? state.costUSD : nil
      let costShare: Double?
      if hasPartialPricing {
        costShare = nil
      } else if let totalCostUSD, totalCostUSD > 0, let costValue {
        costShare = costValue / totalCostUSD
      } else if let costValue, costValue == 0 {
        costShare = 0
      } else {
        costShare = nil
      }

      return TokenCostModelSummary(
        modelName: modelName,
        inputTokens: state.inputTokens,
        cacheReadTokens: state.cacheReadTokens,
        outputTokens: state.outputTokens,
        totalTokens: state.totalTokens,
        costUSD: costValue,
        costShare: costShare,
        tokenShare: tokenShare
      )
    }
    .sorted { lhs, rhs in
      let lhsCost = lhs.costUSD ?? -1
      let rhsCost = rhs.costUSD ?? -1
      if lhsCost != rhsCost {
        return lhsCost > rhsCost
      }
      if lhs.totalTokens != rhs.totalTokens {
        return lhs.totalTokens > rhs.totalTokens
      }
      return lhs.modelName < rhs.modelName
    }
  }

  private static func buildHourlyEntries(from dailyEntries: [TokenCostDailyEntry]) -> [TokenCostHourlyEntry] {
    var states: [Int: HourAggregateState] = [:]

    for entry in dailyEntries {
      for hourEntry in entry.hourlyBreakdowns ?? [] {
        var state = states[hourEntry.hour] ?? HourAggregateState()
        state.inputTokens += hourEntry.inputTokens ?? 0
        state.cacheReadTokens += hourEntry.cacheReadTokens ?? 0
        state.outputTokens += hourEntry.outputTokens ?? 0
        state.totalTokens += hourEntry.totalTokens ?? 0
        if let costUSD = hourEntry.costUSD {
          state.costUSD += costUSD
        } else if (hourEntry.totalTokens ?? 0) > 0 {
          state.costKnown = false
        }
        states[hourEntry.hour] = state
      }
    }

    return states.keys.sorted().map { hour in
      let state = states[hour] ?? HourAggregateState()
      return TokenCostHourlyEntry(
        hour: hour,
        inputTokens: state.inputTokens,
        cacheReadTokens: state.cacheReadTokens,
        outputTokens: state.outputTokens,
        totalTokens: state.totalTokens,
        costUSD: state.costKnown ? state.costUSD : nil
      )
    }
  }

  private static func deriveAlerts(
    windowDays: Int,
    activeEntries: [TokenCostDailyEntry],
    cacheShare: Double?,
    dominantModelName: String?,
    modelSummaries: [TokenCostModelSummary],
    hasPartialPricing: Bool,
    totalCostUSD: Double?
  ) -> [TokenCostInsight] {
    var alerts: [TokenCostInsight] = []

    if hasPartialPricing {
      alerts.append(
        TokenCostInsight(
          kind: "partial_pricing",
          title: "Partial pricing",
          message: "Some \(windowDays)D usage came from models without pricing, so dollar totals are incomplete.",
          severity: "warning"
        )
      )
    }

    if let cacheShare, cacheShare >= 0.30 {
      alerts.append(
        TokenCostInsight(
          kind: "high_cache_share",
          title: "Strong cache leverage",
          message: "Cache reads covered \(percentString(cacheShare)) of input tokens in the last \(windowDays) days.",
          severity: "positive"
        )
      )
    }

    if let dominant = modelSummaries.first,
       (dominant.costShare ?? dominant.tokenShare ?? 0) >= 0.75 {
      let share = dominant.costShare ?? dominant.tokenShare ?? 0
      alerts.append(
        TokenCostInsight(
          kind: "model_concentration",
          title: "Model concentration",
          message: "\(dominant.modelName) drove \(percentString(share)) of the visible \(windowDays)D usage mix.",
          severity: "warning"
        )
      )
    } else if let dominantModelName {
      _ = dominantModelName
    }

    let knownDailyCosts = activeEntries.compactMap(\.costUSD)
    if let peakCost = knownDailyCosts.max(),
       let totalCostUSD,
       !activeEntries.isEmpty {
      let averageActiveDayCost = totalCostUSD / Double(activeEntries.count)
      if peakCost > max(averageActiveDayCost * 1.5, 0.002),
         let spikeDay = activeEntries.first(where: { $0.costUSD == peakCost })?.date {
        alerts.append(
          TokenCostInsight(
            kind: "high_burn_day",
            title: "Burn spike",
            message: "\(spikeDay) peaked at \(TokenCostFormatting.usd(peakCost)) in a single day.",
            severity: "warning"
          )
        )
      }
    }

    return alerts
  }

  private static func deriveNarrative(
    windowDays: Int,
    activeEntries: [TokenCostDailyEntry],
    cacheShare: Double?,
    dominantModelName: String?,
    modelSummaries: [TokenCostModelSummary],
    hasPartialPricing: Bool,
    totalCostUSD: Double?,
    totalTokens: Int?
  ) -> TokenCostNarrative {
    guard !activeEntries.isEmpty else {
      return TokenCostNarrative(
        whatChanged: ["No local Codex usage landed in the last \(windowDays) days."],
        whatHelped: ["The dashboard will populate after local Codex sessions write token logs."],
        whatToWatch: ["Run Codex locally to start collecting cost analytics."]
      )
    }

    var whatChanged: [String] = []
    var whatHelped: [String] = []
    var whatToWatch: [String] = []

    if let totalCostUSD {
      whatChanged.append(
        "\(windowDays)D spend reached \(TokenCostFormatting.usd(totalCostUSD)) across \(activeEntries.count) active days."
      )
    } else if let totalTokens {
      whatChanged.append(
        "\(windowDays)D activity reached \(TokenCostFormatting.tokenCount(totalTokens)) tokens, with partial pricing coverage."
      )
    }

    if let dominantModelName,
       let dominant = modelSummaries.first,
       let share = dominant.costShare ?? dominant.tokenShare {
      whatChanged.append(
        "\(dominantModelName) remained the dominant model at \(percentString(share)) of the visible mix."
      )
    }

    if let cacheShare, cacheShare > 0 {
      whatHelped.append("Local cache reads covered \(percentString(cacheShare)) of input tokens.")
    } else {
      whatHelped.append("No meaningful cache reuse showed up in the current window.")
    }

    if hasPartialPricing {
      whatToWatch.append("pricing is incomplete because at least one active model is missing a rate card.")
    }

    if let dominant = modelSummaries.first,
       (dominant.costShare ?? dominant.tokenShare ?? 0) >= 0.75 {
      whatToWatch.append("\(dominant.modelName) is carrying most of the spend mix right now.")
    }

    if whatToWatch.isEmpty {
      whatToWatch.append("Watch for burn concentration when one model starts dominating the window.")
    }

    return TokenCostNarrative(
      whatChanged: whatChanged,
      whatHelped: whatHelped,
      whatToWatch: whatToWatch
    )
  }

  private static func sortBreakdowns(_ breakdowns: [TokenCostModelBreakdown]) -> [TokenCostModelBreakdown] {
    breakdowns.sorted { lhs, rhs in
      let lhsCost = lhs.costUSD ?? -1
      let rhsCost = rhs.costUSD ?? -1
      if lhsCost != rhsCost {
        return lhsCost > rhsCost
      }

      let lhsTokens = lhs.totalTokens ?? -1
      let rhsTokens = rhs.totalTokens ?? -1
      if lhsTokens != rhsTokens {
        return lhsTokens > rhsTokens
      }

      return lhs.modelName < rhs.modelName
    }
  }

  static func dayKey(from date: Date) -> String {
    let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
  }

  private static func percentString(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))%"
  }
}

private struct ModelAggregateState {
  var inputTokens = 0
  var cacheReadTokens = 0
  var outputTokens = 0
  var totalTokens = 0
  var costUSD = 0.0
  var costKnown = true
}

private struct HourAggregateState {
  var inputTokens = 0
  var cacheReadTokens = 0
  var outputTokens = 0
  var totalTokens = 0
  var costUSD = 0.0
  var costKnown = true
}
