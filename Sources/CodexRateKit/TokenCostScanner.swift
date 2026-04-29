import Foundation

public enum TokenCostScanner {
  private static let cacheSchemaVersion = 3
  private static let replayTokenEventThreshold = 1_000
  private static let replayCompactionEventThreshold = 100
  private static let replayDurationThresholdSeconds: TimeInterval = 60 * 60
  private static let replayTotalTokenThreshold = 100_000_000
  private static let rapidReplayTokenThreshold = 1_000_000_000

  public struct Options: Sendable {
    public var codexHomeURL: URL?
    public var managedHomesDirectoryURL: URL?
    public var cacheFileURL: URL?
    public var environment: [String: String]
    public var refreshMinIntervalSeconds: TimeInterval
    public var forceRescan: Bool

    public init(
      codexHomeURL: URL? = nil,
      managedHomesDirectoryURL: URL? = nil,
      cacheFileURL: URL? = nil,
      environment: [String: String] = ProcessInfo.processInfo.environment,
      refreshMinIntervalSeconds: TimeInterval = 60,
      forceRescan: Bool = false
    ) {
      self.codexHomeURL = codexHomeURL
      self.managedHomesDirectoryURL = managedHomesDirectoryURL
      self.cacheFileURL = cacheFileURL
      self.environment = environment
      self.refreshMinIntervalSeconds = refreshMinIntervalSeconds
      self.forceRescan = forceRescan
    }
  }

  public static func loadSnapshot(
    now: Date = Date(),
    options: Options = .init()
  ) -> TokenCostSnapshot {
    let cacheFileURL = options.cacheFileURL ?? AppPaths.tokenCostCacheFile
    let nowMilliseconds = Int64(now.timeIntervalSince1970 * 1000)
    let refreshMilliseconds = Int64(max(0, options.refreshMinIntervalSeconds) * 1000)

    var cache = options.forceRescan ? TokenCostCache() : TokenCostCacheStore.load(from: cacheFileURL)
    if cache.schemaVersion != Self.cacheSchemaVersion {
      cache = TokenCostCache()
    }

    let shouldRefresh = options.forceRescan
      || refreshMilliseconds == 0
      || cache.lastScanUnixMilliseconds == 0
      || (nowMilliseconds - cache.lastScanUnixMilliseconds) >= refreshMilliseconds

    if shouldRefresh {
      cache = refreshCache(existing: cache, nowMilliseconds: nowMilliseconds, options: options)
      TokenCostCacheStore.save(cache, to: cacheFileURL)
    }

    return buildSnapshot(from: cache, now: now)
  }

  private static func refreshCache(
    existing: TokenCostCache,
    nowMilliseconds: Int64,
    options: Options
  ) -> TokenCostCache {
    let now = Date(timeIntervalSince1970: TimeInterval(nowMilliseconds) / 1000)
    let earliest = Calendar.current.date(byAdding: .day, value: -89, to: now) ?? now
    let fileURLs = discoverSessionFiles(options: options, since: earliest, until: now).sorted { $0.path < $1.path }
    var nextCache = TokenCostCache(
      schemaVersion: Self.cacheSchemaVersion,
      lastScanUnixMilliseconds: nowMilliseconds
    )
    var seenSessionIDs: Set<String> = []

    for fileURL in fileURLs {
      let metadata = fileMetadata(for: fileURL)
      let cached = existing.files[fileURL.path]

      var fileUsage: TokenCostCachedFile
      if let cached,
         cached.modifiedAtUnixMilliseconds == metadata.modifiedAtUnixMilliseconds,
         cached.size == metadata.size {
        fileUsage = cached
      } else {
        fileUsage = parseFile(fileURL: fileURL, metadata: metadata)
      }

      if shouldExclude(fileUsage: fileUsage), !fileUsage.days.isEmpty {
        fileUsage = excludedCopy(
          of: fileUsage,
          reason: fileUsage.diagnostics?.exclusionReason ?? "cached_file_excluded"
        )
      }

      let isExcluded = shouldExclude(fileUsage: fileUsage)
      if !isExcluded, let sessionID = fileUsage.sessionID, seenSessionIDs.contains(sessionID) {
        continue
      }

      nextCache.files[fileURL.path] = fileUsage
      if !isExcluded {
        merge(days: fileUsage.days, into: &nextCache.days)
        if let sessionID = fileUsage.sessionID {
          seenSessionIDs.insert(sessionID)
        }
      }
    }

    return nextCache
  }

  private static func buildSnapshot(from cache: TokenCostCache, now: Date) -> TokenCostSnapshot {
    TokenCostSnapshotBuilder.buildSnapshot(days: cache.days, now: now)
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

      let totalTokens = inputTokens + outputTokens
      return TokenCostHourlyEntry(
        hour: hour,
        inputTokens: inputTokens,
        cacheReadTokens: cacheReadTokens,
        outputTokens: outputTokens,
        totalTokens: totalTokens,
        costUSD: costKnown ? cost : nil
      )
    }

    let dayTotalTokens = dayInput + dayOutput
    return TokenCostDailyEntry(
      date: dayKey,
      inputTokens: dayInput,
      cacheReadTokens: dayCacheRead,
      outputTokens: dayOutput,
      totalTokens: dayTotalTokens,
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

  private static func discoverSessionFiles(options: Options, since: Date, until: Date) -> [URL] {
    var roots: [URL] = []
    let codexHomeURL = resolvedCodexHomeURL(options: options)
    roots.append(contentsOf: sessionRoots(forHomeURL: codexHomeURL))

    let managedHomesDirectoryURL = options.managedHomesDirectoryURL ?? AppPaths.managedCodexHomesDirectory
    if let managedHomes = try? FileManager.default.contentsOfDirectory(
      at: managedHomesDirectoryURL,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) {
      for managedHome in managedHomes {
        roots.append(contentsOf: sessionRoots(forHomeURL: managedHome))
      }
    }

    var seenPaths: Set<String> = []
    var files: [URL] = []
    for root in roots where FileManager.default.fileExists(atPath: root.path) {
      for fileURL in listSessionFiles(root: root, since: since, until: until) {
        if seenPaths.insert(fileURL.path).inserted {
          files.append(fileURL)
        }
      }
    }

    return files
  }

  private static func sessionRoots(forHomeURL homeURL: URL) -> [URL] {
    [
      homeURL.appending(path: "sessions", directoryHint: .isDirectory),
      homeURL.appending(path: "archived_sessions", directoryHint: .isDirectory),
    ]
  }

  private static func listSessionFiles(root: URL, since: Date, until: Date) -> [URL] {
    var results: [URL] = []
    results.append(contentsOf: listPartitionedSessionFiles(root: root, since: since, until: until))
    results.append(contentsOf: listFlatSessionFiles(root: root, since: since, until: until))
    return results
  }

  private static func listPartitionedSessionFiles(root: URL, since: Date, until: Date) -> [URL] {
    guard FileManager.default.fileExists(atPath: root.path) else { return [] }

    var results: [URL] = []
    var date = Calendar.current.startOfDay(for: since)
    let lastDate = Calendar.current.startOfDay(for: until)

    while date <= lastDate {
      let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
      let year = String(format: "%04d", components.year ?? 1970)
      let month = String(format: "%02d", components.month ?? 1)
      let day = String(format: "%02d", components.day ?? 1)

      let dayDirectory = root
        .appending(path: year, directoryHint: .isDirectory)
        .appending(path: month, directoryHint: .isDirectory)
        .appending(path: day, directoryHint: .isDirectory)

      if let files = try? FileManager.default.contentsOfDirectory(
        at: dayDirectory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      ) {
        results.append(contentsOf: files.filter { $0.pathExtension.lowercased() == "jsonl" })
      }

      date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? lastDate.addingTimeInterval(1)
    }

    return results
  }

  private static func listFlatSessionFiles(root: URL, since: Date, until: Date) -> [URL] {
    guard let files = try? FileManager.default.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else {
      return []
    }

    let sinceKey = dayKey(from: since)
    let untilKey = dayKey(from: until)

    return files.filter { fileURL in
      guard fileURL.pathExtension.lowercased() == "jsonl" else { return false }
      guard let dayKey = dayKey(fromFilename: fileURL.lastPathComponent) else { return true }
      return dayKey >= sinceKey && dayKey <= untilKey
    }
  }

  private static func resolvedCodexHomeURL(options: Options) -> URL {
    if let codexHomeURL = options.codexHomeURL {
      return codexHomeURL
    }

    if let homePath = options.environment["CODEX_HOME"]?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !homePath.isEmpty {
      return URL(fileURLWithPath: homePath, isDirectory: true)
    }

    return FileManager.default.homeDirectoryForCurrentUser
      .appending(path: ".codex", directoryHint: .isDirectory)
  }

  private static func parseFile(fileURL: URL, metadata: FileMetadata) -> TokenCostCachedFile {
    guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
      return TokenCostCachedFile(
        path: fileURL.path,
        modifiedAtUnixMilliseconds: metadata.modifiedAtUnixMilliseconds,
        size: metadata.size,
        sessionID: nil,
        lastModel: nil,
        lastTotals: nil,
        diagnostics: TokenCostFileDiagnostics(exclusionReason: "unreadable_file"),
        days: [:]
      )
    }

    var sessionID: String?
    var currentModel: String?
    var previousTotals: TokenCostRunningTotals?
    var days: [String: TokenCostCachedDay] = [:]
    var tokenCountEvents = 0
    var compactionEvents = 0
    var firstTokenUnixMilliseconds: Int64?
    var lastTokenUnixMilliseconds: Int64?

    contents.enumerateLines { line, _ in
      guard let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = object["type"] as? String else {
        return
      }

      switch type {
      case "compacted":
        compactionEvents += 1

      case "session_meta":
        guard sessionID == nil else { return }
        let payload = object["payload"] as? [String: Any]
        sessionID = payload?["session_id"] as? String
          ?? payload?["sessionId"] as? String
          ?? payload?["id"] as? String
          ?? object["session_id"] as? String
          ?? object["sessionId"] as? String
          ?? object["id"] as? String

      case "turn_context":
        let payload = object["payload"] as? [String: Any]
        currentModel = payload?["model"] as? String
          ?? (payload?["info"] as? [String: Any])?["model"] as? String

      case "event_msg":
        guard let payload = object["payload"] as? [String: Any],
              let payloadType = payload["type"] as? String else {
          return
        }

        if payloadType == "context_compacted" {
          compactionEvents += 1
          return
        }

        guard payloadType == "token_count",
              let timestamp = object["timestamp"] as? String,
              let tokenDate = timestampDate(from: timestamp) else {
          return
        }

        let timestampParts = timestampParts(from: tokenDate)
        let tokenUnixMilliseconds = Int64(tokenDate.timeIntervalSince1970 * 1000)
        if firstTokenUnixMilliseconds == nil {
          firstTokenUnixMilliseconds = tokenUnixMilliseconds
        }
        lastTokenUnixMilliseconds = tokenUnixMilliseconds
        tokenCountEvents += 1

        let info = payload["info"] as? [String: Any]
        let resolvedModel = (info?["model"] as? String)
          ?? (info?["model_name"] as? String)
          ?? (payload["model"] as? String)
          ?? (object["model"] as? String)
          ?? currentModel
          ?? "gpt-5"

        let delta: TokenCostRunningTotals?
        if let totals = info?["total_token_usage"] as? [String: Any] {
          let nextTotals = TokenCostRunningTotals(
            inputTokens: intValue(totals["input_tokens"]),
            cachedInputTokens: intValue(totals["cached_input_tokens"] ?? totals["cache_read_input_tokens"]),
            outputTokens: intValue(totals["output_tokens"])
          )

          if let previousTotals {
            delta = TokenCostRunningTotals(
              inputTokens: max(0, nextTotals.inputTokens - previousTotals.inputTokens),
              cachedInputTokens: max(0, nextTotals.cachedInputTokens - previousTotals.cachedInputTokens),
              outputTokens: max(0, nextTotals.outputTokens - previousTotals.outputTokens)
            )
          } else {
            delta = nextTotals
          }

          previousTotals = nextTotals
        } else if let last = info?["last_token_usage"] as? [String: Any] {
          delta = TokenCostRunningTotals(
            inputTokens: max(0, intValue(last["input_tokens"])),
            cachedInputTokens: max(0, intValue(last["cached_input_tokens"] ?? last["cache_read_input_tokens"])),
            outputTokens: max(0, intValue(last["output_tokens"]))
          )
        } else {
          delta = nil
        }

        guard let delta else { return }
        if delta.inputTokens == 0 && delta.cachedInputTokens == 0 && delta.outputTokens == 0 {
          return
        }

        let normalizedModel = TokenCostPricing.normalizeCodexModel(resolvedModel)
        let cachedInputTokens = min(delta.cachedInputTokens, delta.inputTokens)

        var day = days[timestampParts.dayKey] ?? TokenCostCachedDay()
        var dayBucket = day.models[normalizedModel] ?? TokenCostBucket()
        dayBucket.add(
          inputTokens: delta.inputTokens,
          cacheReadTokens: cachedInputTokens,
          outputTokens: delta.outputTokens
        )
        day.models[normalizedModel] = dayBucket

        var hour = day.hours[timestampParts.hour] ?? TokenCostCachedHour()
        var hourBucket = hour.models[normalizedModel] ?? TokenCostBucket()
        hourBucket.add(
          inputTokens: delta.inputTokens,
          cacheReadTokens: cachedInputTokens,
          outputTokens: delta.outputTokens
        )
        hour.models[normalizedModel] = hourBucket
        day.hours[timestampParts.hour] = hour

        days[timestampParts.dayKey] = day

      default:
        return
      }
    }

    let totalTokens = totalTokens(in: days)
    let exclusionReason = exclusionReason(
      totalTokens: totalTokens,
      tokenCountEvents: tokenCountEvents,
      compactionEvents: compactionEvents,
      firstTokenUnixMilliseconds: firstTokenUnixMilliseconds,
      lastTokenUnixMilliseconds: lastTokenUnixMilliseconds
    )
    let diagnostics = TokenCostFileDiagnostics(
      tokenCountEvents: tokenCountEvents,
      compactionEvents: compactionEvents,
      firstTokenUnixMilliseconds: firstTokenUnixMilliseconds,
      lastTokenUnixMilliseconds: lastTokenUnixMilliseconds,
      totalTokens: totalTokens,
      exclusionReason: exclusionReason
    )

    return TokenCostCachedFile(
      path: fileURL.path,
      modifiedAtUnixMilliseconds: metadata.modifiedAtUnixMilliseconds,
      size: metadata.size,
      sessionID: sessionID,
      lastModel: currentModel,
      lastTotals: previousTotals,
      diagnostics: diagnostics,
      days: exclusionReason == nil ? days : [:]
    )
  }

  private static func merge(
    days source: [String: TokenCostCachedDay],
    into destination: inout [String: TokenCostCachedDay]
  ) {
    for (dayKey, sourceDay) in source {
      var destinationDay = destination[dayKey] ?? TokenCostCachedDay()

      for (model, sourceBucket) in sourceDay.models {
        var destinationBucket = destinationDay.models[model] ?? TokenCostBucket()
        destinationBucket.add(
          inputTokens: sourceBucket.inputTokens,
          cacheReadTokens: sourceBucket.cacheReadTokens,
          outputTokens: sourceBucket.outputTokens
        )
        destinationDay.models[model] = destinationBucket
      }

      for (hourKey, sourceHour) in sourceDay.hours {
        var destinationHour = destinationDay.hours[hourKey] ?? TokenCostCachedHour()
        for (model, sourceBucket) in sourceHour.models {
          var destinationBucket = destinationHour.models[model] ?? TokenCostBucket()
          destinationBucket.add(
            inputTokens: sourceBucket.inputTokens,
            cacheReadTokens: sourceBucket.cacheReadTokens,
            outputTokens: sourceBucket.outputTokens
          )
          destinationHour.models[model] = destinationBucket
        }
        destinationDay.hours[hourKey] = destinationHour
      }

      destination[dayKey] = destinationDay
    }
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

  private static func shouldExclude(fileUsage: TokenCostCachedFile) -> Bool {
    fileUsage.diagnostics?.isExcluded == true
  }

  private static func excludedCopy(of fileUsage: TokenCostCachedFile, reason: String) -> TokenCostCachedFile {
    let existingDiagnostics = fileUsage.diagnostics
    let diagnostics = TokenCostFileDiagnostics(
      tokenCountEvents: existingDiagnostics?.tokenCountEvents ?? 0,
      compactionEvents: existingDiagnostics?.compactionEvents ?? 0,
      firstTokenUnixMilliseconds: existingDiagnostics?.firstTokenUnixMilliseconds,
      lastTokenUnixMilliseconds: existingDiagnostics?.lastTokenUnixMilliseconds,
      totalTokens: existingDiagnostics?.totalTokens ?? totalTokens(in: fileUsage.days),
      exclusionReason: reason
    )

    return TokenCostCachedFile(
      path: fileUsage.path,
      modifiedAtUnixMilliseconds: fileUsage.modifiedAtUnixMilliseconds,
      size: fileUsage.size,
      sessionID: fileUsage.sessionID,
      lastModel: fileUsage.lastModel,
      lastTotals: fileUsage.lastTotals,
      diagnostics: diagnostics,
      days: [:]
    )
  }

  private static func exclusionReason(
    totalTokens: Int,
    tokenCountEvents: Int,
    compactionEvents: Int,
    firstTokenUnixMilliseconds: Int64?,
    lastTokenUnixMilliseconds: Int64?
  ) -> String? {
    guard let firstTokenUnixMilliseconds,
          let lastTokenUnixMilliseconds else {
      return nil
    }

    let durationSeconds = TimeInterval(max(0, lastTokenUnixMilliseconds - firstTokenUnixMilliseconds)) / 1000
    let looksLikeRapidReplay = durationSeconds <= replayDurationThresholdSeconds
      && totalTokens >= replayTotalTokenThreshold
      && tokenCountEvents >= replayTokenEventThreshold

    if looksLikeRapidReplay && compactionEvents >= replayCompactionEventThreshold {
      return "rapid_compaction_replay"
    }

    if looksLikeRapidReplay && totalTokens >= rapidReplayTokenThreshold {
      return "rapid_token_replay"
    }

    return nil
  }

  private static func totalTokens(in days: [String: TokenCostCachedDay]) -> Int {
    days.values.reduce(0) { dayTotal, day in
      dayTotal + day.models.values.reduce(0) { modelTotal, bucket in
        modelTotal + bucket.totalTokens
      }
    }
  }

  private static func dayKey(from date: Date) -> String {
    let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
  }

  private static func timestampDate(from timestamp: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: timestamp) {
      return date
    }

    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: timestamp)
  }

  private static func timestampParts(from timestamp: String) -> TimestampParts? {
    timestampDate(from: timestamp).map(timestampParts(from:))
  }

  private static func timestampParts(from date: Date) -> TimestampParts {
    let components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: date)
    let day = String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
    return TimestampParts(dayKey: day, hour: components.hour ?? 0)
  }

  private static func dayKey(fromFilename filename: String) -> String? {
    guard let match = filename.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) else {
      return nil
    }
    return String(filename[match])
  }

  private static func intValue(_ value: Any?) -> Int {
    if let number = value as? NSNumber {
      return number.intValue
    }
    if let string = value as? String, let number = Int(string) {
      return number
    }
    return 0
  }

  private static func percentString(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))%"
  }

  private static func fileMetadata(for fileURL: URL) -> FileMetadata {
    let attributes = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)) ?? [:]
    let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0

    return FileMetadata(
      modifiedAtUnixMilliseconds: Int64(modifiedAt * 1000),
      size: size
    )
  }
}

private struct TimestampParts {
  let dayKey: String
  let hour: Int
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

private struct FileMetadata {
  let modifiedAtUnixMilliseconds: Int64
  let size: Int64
}
