import Foundation

struct TokenCostRunningTotals: Codable, Equatable, Sendable {
  let inputTokens: Int
  let cachedInputTokens: Int
  let outputTokens: Int
}

struct TokenCostBucket: Codable, Equatable, Sendable {
  var inputTokens: Int
  var cacheReadTokens: Int
  var outputTokens: Int

  init(inputTokens: Int = 0, cacheReadTokens: Int = 0, outputTokens: Int = 0) {
    self.inputTokens = inputTokens
    self.cacheReadTokens = cacheReadTokens
    self.outputTokens = outputTokens
  }

  var totalTokens: Int {
    inputTokens + outputTokens
  }

  mutating func add(inputTokens: Int, cacheReadTokens: Int, outputTokens: Int) {
    self.inputTokens += inputTokens
    self.cacheReadTokens += cacheReadTokens
    self.outputTokens += outputTokens
  }
}

struct TokenCostCachedHour: Codable, Equatable, Sendable {
  var models: [String: TokenCostBucket]

  init(models: [String: TokenCostBucket] = [:]) {
    self.models = models
  }
}

struct TokenCostCachedDay: Codable, Equatable, Sendable {
  var models: [String: TokenCostBucket]
  var hours: [Int: TokenCostCachedHour]

  init(
    models: [String: TokenCostBucket] = [:],
    hours: [Int: TokenCostCachedHour] = [:]
  ) {
    self.models = models
    self.hours = hours
  }
}

struct TokenCostFileDiagnostics: Codable, Equatable, Sendable {
  let tokenCountEvents: Int
  let compactionEvents: Int
  let firstTokenUnixMilliseconds: Int64?
  let lastTokenUnixMilliseconds: Int64?
  let totalTokens: Int
  let exclusionReason: String?

  init(
    tokenCountEvents: Int = 0,
    compactionEvents: Int = 0,
    firstTokenUnixMilliseconds: Int64? = nil,
    lastTokenUnixMilliseconds: Int64? = nil,
    totalTokens: Int = 0,
    exclusionReason: String? = nil
  ) {
    self.tokenCountEvents = tokenCountEvents
    self.compactionEvents = compactionEvents
    self.firstTokenUnixMilliseconds = firstTokenUnixMilliseconds
    self.lastTokenUnixMilliseconds = lastTokenUnixMilliseconds
    self.totalTokens = totalTokens
    self.exclusionReason = exclusionReason
  }

  var isExcluded: Bool {
    exclusionReason != nil
  }
}

struct TokenCostCachedFile: Codable, Equatable, Sendable {
  let path: String
  let modifiedAtUnixMilliseconds: Int64
  let size: Int64
  let sessionID: String?
  let lastModel: String?
  let lastTotals: TokenCostRunningTotals?
  let diagnostics: TokenCostFileDiagnostics?
  let days: [String: TokenCostCachedDay]

  init(
    path: String,
    modifiedAtUnixMilliseconds: Int64,
    size: Int64,
    sessionID: String?,
    lastModel: String?,
    lastTotals: TokenCostRunningTotals?,
    diagnostics: TokenCostFileDiagnostics? = nil,
    days: [String: TokenCostCachedDay]
  ) {
    self.path = path
    self.modifiedAtUnixMilliseconds = modifiedAtUnixMilliseconds
    self.size = size
    self.sessionID = sessionID
    self.lastModel = lastModel
    self.lastTotals = lastTotals
    self.diagnostics = diagnostics
    self.days = days
  }
}

struct TokenCostCache: Codable, Equatable, Sendable {
  var schemaVersion: Int?
  var lastScanUnixMilliseconds: Int64
  var files: [String: TokenCostCachedFile]
  var days: [String: TokenCostCachedDay]

  init(
    schemaVersion: Int? = nil,
    lastScanUnixMilliseconds: Int64 = 0,
    files: [String: TokenCostCachedFile] = [:],
    days: [String: TokenCostCachedDay] = [:]
  ) {
    self.schemaVersion = schemaVersion
    self.lastScanUnixMilliseconds = lastScanUnixMilliseconds
    self.files = files
    self.days = days
  }
}

enum TokenCostCacheStore {
  static func load(from fileURL: URL) -> TokenCostCache {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return TokenCostCache()
    }

    do {
      let data = try Data(contentsOf: fileURL)
      return try JSONDecoder().decode(TokenCostCache.self, from: data)
    } catch {
      return TokenCostCache()
    }
  }

  static func save(_ cache: TokenCostCache, to fileURL: URL) {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let data = try JSONEncoder().encode(cache)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      // Token cost cache is optional runtime state.
    }
  }
}
