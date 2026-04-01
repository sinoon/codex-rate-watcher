import Foundation

public enum TokenCostScanner {
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
    let earliest = Calendar.current.date(byAdding: .day, value: -29, to: now) ?? now
    let fileURLs = discoverSessionFiles(options: options, since: earliest, until: now).sorted { $0.path < $1.path }
    var nextCache = TokenCostCache(lastScanUnixMilliseconds: nowMilliseconds)
    var seenSessionIDs: Set<String> = []

    for fileURL in fileURLs {
      let metadata = fileMetadata(for: fileURL)
      let cached = existing.files[fileURL.path]

      let fileUsage: TokenCostCachedFile
      if let cached,
         cached.modifiedAtUnixMilliseconds == metadata.modifiedAtUnixMilliseconds,
         cached.size == metadata.size {
        fileUsage = cached
      } else {
        fileUsage = parseFile(fileURL: fileURL, metadata: metadata)
      }

      if let sessionID = fileUsage.sessionID, seenSessionIDs.contains(sessionID) {
        continue
      }

      nextCache.files[fileURL.path] = fileUsage
      merge(days: fileUsage.days, into: &nextCache.days)
      if let sessionID = fileUsage.sessionID {
        seenSessionIDs.insert(sessionID)
      }
    }

    return nextCache
  }

  private static func buildSnapshot(from cache: TokenCostCache, now: Date) -> TokenCostSnapshot {
    let calendar = Calendar.current
    let todayKey = dayKey(from: now)
    let earliestDate = calendar.date(byAdding: .day, value: -29, to: now) ?? now
    let earliestKey = dayKey(from: earliestDate)

    let dayKeys = cache.days.keys.sorted().filter { $0 >= earliestKey && $0 <= todayKey }
    var dailyEntries: [TokenCostDailyEntry] = []
    var totalTokens = 0
    var totalCost: Double = 0
    var totalCostKnown = true
    var sawTokens = false
    var sawCost = false

    for dayKey in dayKeys {
      guard let models = cache.days[dayKey] else { continue }
      let sortedModels = models.keys.sorted()

      var dayInput = 0
      var dayCacheRead = 0
      var dayOutput = 0
      var dayCost = 0.0
      var dayCostKnown = true
      var breakdowns: [TokenCostModelBreakdown] = []

      for model in sortedModels {
        let bucket = models[model] ?? TokenCostBucket()
        let modelCost = TokenCostPricing.codexCostUSD(
          model: model,
          inputTokens: bucket.inputTokens,
          cachedInputTokens: bucket.cacheReadTokens,
          outputTokens: bucket.outputTokens
        )

        if modelCost == nil {
          dayCostKnown = false
        } else {
          dayCost += modelCost ?? 0
          sawCost = true
        }

        dayInput += bucket.inputTokens
        dayCacheRead += bucket.cacheReadTokens
        dayOutput += bucket.outputTokens
        breakdowns.append(
          TokenCostModelBreakdown(
            modelName: model,
            costUSD: modelCost,
            totalTokens: bucket.totalTokens
          )
        )
      }

      let dayTotalTokens = dayInput + dayOutput
      if dayTotalTokens > 0 {
        sawTokens = true
        totalTokens += dayTotalTokens
      }

      if dayCostKnown {
        totalCost += dayCost
      } else if dayTotalTokens > 0 {
        totalCostKnown = false
      }

      dailyEntries.append(
        TokenCostDailyEntry(
          date: dayKey,
          inputTokens: dayInput,
          cacheReadTokens: dayCacheRead,
          outputTokens: dayOutput,
          totalTokens: dayTotalTokens,
          costUSD: dayCostKnown ? dayCost : nil,
          modelsUsed: sortedModels,
          modelBreakdowns: sortBreakdowns(breakdowns)
        )
      )
    }

    let todayEntry = dailyEntries.last(where: { $0.date == todayKey })
    return TokenCostSnapshot(
      todayTokens: todayEntry?.totalTokens,
      todayCostUSD: todayEntry?.costUSD,
      last30DaysTokens: sawTokens ? totalTokens : nil,
      last30DaysCostUSD: totalCostKnown && sawCost ? totalCost : nil,
      daily: dailyEntries,
      updatedAt: now
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
        days: [:]
      )
    }

    var sessionID: String?
    var currentModel: String?
    var previousTotals: TokenCostRunningTotals?
    var days: [String: [String: TokenCostBucket]] = [:]

    contents.enumerateLines { line, _ in
      guard let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = object["type"] as? String else {
        return
      }

      switch type {
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
              (payload["type"] as? String) == "token_count",
              let timestamp = object["timestamp"] as? String,
              let dayKey = dayKey(fromTimestamp: timestamp) else {
          return
        }

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
        var models = days[dayKey] ?? [:]
        var bucket = models[normalizedModel] ?? TokenCostBucket()
        bucket.add(
          inputTokens: delta.inputTokens,
          cacheReadTokens: cachedInputTokens,
          outputTokens: delta.outputTokens
        )
        models[normalizedModel] = bucket
        days[dayKey] = models

      default:
        return
      }
    }

    return TokenCostCachedFile(
      path: fileURL.path,
      modifiedAtUnixMilliseconds: metadata.modifiedAtUnixMilliseconds,
      size: metadata.size,
      sessionID: sessionID,
      lastModel: currentModel,
      lastTotals: previousTotals,
      days: days
    )
  }

  private static func merge(
    days source: [String: [String: TokenCostBucket]],
    into destination: inout [String: [String: TokenCostBucket]]
  ) {
    for (dayKey, sourceModels) in source {
      var destinationModels = destination[dayKey] ?? [:]
      for (model, sourceBucket) in sourceModels {
        var destinationBucket = destinationModels[model] ?? TokenCostBucket()
        destinationBucket.add(
          inputTokens: sourceBucket.inputTokens,
          cacheReadTokens: sourceBucket.cacheReadTokens,
          outputTokens: sourceBucket.outputTokens
        )
        destinationModels[model] = destinationBucket
      }
      destination[dayKey] = destinationModels
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

  private static func dayKey(from date: Date) -> String {
    let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
  }

  private static func dayKey(fromTimestamp timestamp: String) -> String? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: timestamp) {
      return dayKey(from: date)
    }

    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: timestamp) {
      return dayKey(from: date)
    }
    return nil
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

private struct FileMetadata {
  let modifiedAtUnixMilliseconds: Int64
  let size: Int64
}
