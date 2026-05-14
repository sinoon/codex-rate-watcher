import Foundation

// Walks Claude Code session JSONL files at ~/.claude/projects/<encoded-cwd>/<id>.jsonl
// and aggregates per-day, per-hour, per-model token usage into the same
// TokenCostCachedDay shape used by the Codex pipeline.
//
// Each file is parsed once and cached by (mtime, size). Within a file, assistant
// messages are deduplicated by `message.id` because Claude Code splits a single
// assistant turn across multiple lines (one per content block) and reports the
// same `usage` object on each — naive line-by-line summation would inflate
// totals by ~2x.
public enum ClaudeCodeSessionScanner {
  private static let cacheSchemaVersion = 1
  // Match the Codex scanner's lookback so daily/window calculations align.
  private static let lookbackDays = 89

  public struct Options: Sendable {
    public var projectsRootURL: URL?
    public var cacheFileURL: URL?
    public var environment: [String: String]
    public var refreshMinIntervalSeconds: TimeInterval
    public var forceRescan: Bool

    public init(
      projectsRootURL: URL? = nil,
      cacheFileURL: URL? = nil,
      environment: [String: String] = ProcessInfo.processInfo.environment,
      refreshMinIntervalSeconds: TimeInterval = 60,
      forceRescan: Bool = false
    ) {
      self.projectsRootURL = projectsRootURL
      self.cacheFileURL = cacheFileURL
      self.environment = environment
      self.refreshMinIntervalSeconds = refreshMinIntervalSeconds
      self.forceRescan = forceRescan
    }
  }

  // Returns the merged day map for Claude Code usage. Refreshes the on-disk
  // cache when stale, then hands back days that callers can blend into the
  // unified snapshot pipeline.
  static func loadCachedDays(
    now: Date = Date(),
    options: Options = .init()
  ) -> [String: TokenCostCachedDay] {
    let cacheFileURL = options.cacheFileURL ?? AppPaths.claudeCodeTokenCostCacheFile
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

    return cache.days
  }

  public static func loadSnapshot(
    now: Date = Date(),
    options: Options = .init()
  ) -> TokenCostSnapshot {
    let days = loadCachedDays(now: now, options: options)
    return TokenCostSnapshotBuilder.buildSnapshot(days: days, now: now)
  }

  private static func refreshCache(
    existing: TokenCostCache,
    nowMilliseconds: Int64,
    options: Options
  ) -> TokenCostCache {
    let now = Date(timeIntervalSince1970: TimeInterval(nowMilliseconds) / 1000)
    let earliest = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: now) ?? now
    let earliestKey = dayKey(from: earliest)
    let untilKey = dayKey(from: now)

    let fileURLs = discoverSessionFiles(options: options).sorted { $0.path < $1.path }
    var nextCache = TokenCostCache(
      schemaVersion: Self.cacheSchemaVersion,
      lastScanUnixMilliseconds: nowMilliseconds
    )

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

      nextCache.files[fileURL.path] = fileUsage
      let trimmedDays = fileUsage.days.filter { dayKey, _ in
        dayKey >= earliestKey && dayKey <= untilKey
      }
      merge(days: trimmedDays, into: &nextCache.days)
    }

    return nextCache
  }

  private static func discoverSessionFiles(options: Options) -> [URL] {
    let root = resolvedProjectsRootURL(options: options)
    guard FileManager.default.fileExists(atPath: root.path) else { return [] }

    var files: [URL] = []
    guard let projectDirs = try? FileManager.default.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }

    for projectDir in projectDirs {
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: projectDir.path, isDirectory: &isDirectory),
            isDirectory.boolValue else {
        continue
      }
      if let sessionFiles = try? FileManager.default.contentsOfDirectory(
        at: projectDir,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      ) {
        for fileURL in sessionFiles where fileURL.pathExtension.lowercased() == "jsonl" {
          files.append(fileURL)
        }
      }
    }

    return files
  }

  private static func resolvedProjectsRootURL(options: Options) -> URL {
    if let projectsRootURL = options.projectsRootURL {
      return projectsRootURL
    }

    if let homePath = options.environment["CLAUDE_CONFIG_DIR"]?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !homePath.isEmpty {
      return URL(fileURLWithPath: homePath, isDirectory: true)
        .appending(path: "projects", directoryHint: .isDirectory)
    }

    return FileManager.default.homeDirectoryForCurrentUser
      .appending(path: ".claude", directoryHint: .isDirectory)
      .appending(path: "projects", directoryHint: .isDirectory)
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
    var lastModel: String?
    var seenMessageIDs: Set<String> = []
    var days: [String: TokenCostCachedDay] = [:]

    contents.enumerateLines { line, _ in
      guard let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return
      }

      if sessionID == nil, let sid = object["sessionId"] as? String {
        sessionID = sid
      }

      // Only assistant turns carry token usage. user/attachment/system lines are
      // bookkeeping and have no usage payload to read.
      guard let type = object["type"] as? String, type == "assistant" else { return }
      guard let message = object["message"] as? [String: Any],
            let usage = message["usage"] as? [String: Any] else {
        return
      }

      // Claude Code emits one JSONL row per content block but every row carries
      // the same `usage` object. Skip duplicates so totals reflect a single
      // billable API turn per message id.
      let messageID = (message["id"] as? String) ?? UUID().uuidString
      guard seenMessageIDs.insert(messageID).inserted else { return }

      guard let timestampString = object["timestamp"] as? String,
            let timestamp = timestampDate(from: timestampString) else {
        return
      }

      let parts = timestampParts(from: timestamp)
      let rawModel = (message["model"] as? String) ?? "unknown"
      lastModel = rawModel
      let normalizedModel = TokenCostPricing.normalizeClaudeModel(rawModel)

      let inputTokensRaw = intValue(usage["input_tokens"])
      let cacheReadTokens = intValue(usage["cache_read_input_tokens"])
      let cacheCreationTokens = intValue(usage["cache_creation_input_tokens"])
      let outputTokens = intValue(usage["output_tokens"])
      // Anthropic returns input_tokens as the uncached portion only. We store
      // the full prompt size so the bucket's "input" matches Codex semantics.
      let totalInput = inputTokensRaw + cacheReadTokens + cacheCreationTokens

      if totalInput == 0 && outputTokens == 0 { return }

      var day = days[parts.dayKey] ?? TokenCostCachedDay()
      var dayBucket = day.models[normalizedModel] ?? TokenCostBucket()
      dayBucket.add(
        inputTokens: totalInput,
        cacheReadTokens: cacheReadTokens,
        cacheCreationTokens: cacheCreationTokens,
        outputTokens: outputTokens
      )
      day.models[normalizedModel] = dayBucket

      var hour = day.hours[parts.hour] ?? TokenCostCachedHour()
      var hourBucket = hour.models[normalizedModel] ?? TokenCostBucket()
      hourBucket.add(
        inputTokens: totalInput,
        cacheReadTokens: cacheReadTokens,
        cacheCreationTokens: cacheCreationTokens,
        outputTokens: outputTokens
      )
      hour.models[normalizedModel] = hourBucket
      day.hours[parts.hour] = hour

      days[parts.dayKey] = day
    }

    return TokenCostCachedFile(
      path: fileURL.path,
      modifiedAtUnixMilliseconds: metadata.modifiedAtUnixMilliseconds,
      size: metadata.size,
      sessionID: sessionID,
      lastModel: lastModel,
      lastTotals: nil,
      diagnostics: nil,
      days: days
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
          cacheCreationTokens: sourceBucket.cacheCreationTokens,
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
            cacheCreationTokens: sourceBucket.cacheCreationTokens,
            outputTokens: sourceBucket.outputTokens
          )
          destinationHour.models[model] = destinationBucket
        }
        destinationDay.hours[hourKey] = destinationHour
      }

      destination[dayKey] = destinationDay
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

  private static func timestampParts(from date: Date) -> TimestampParts {
    let components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: date)
    let day = String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
    return TimestampParts(dayKey: day, hour: components.hour ?? 0)
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

private struct TimestampParts {
  let dayKey: String
  let hour: Int
}

private struct FileMetadata {
  let modifiedAtUnixMilliseconds: Int64
  let size: Int64
}
