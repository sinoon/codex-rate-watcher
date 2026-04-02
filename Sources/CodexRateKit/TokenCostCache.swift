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

struct TokenCostCachedFile: Codable, Equatable, Sendable {
  let path: String
  let modifiedAtUnixMilliseconds: Int64
  let size: Int64
  let sessionID: String?
  let lastModel: String?
  let lastTotals: TokenCostRunningTotals?
  let days: [String: TokenCostCachedDay]
}

struct TokenCostCache: Codable, Equatable, Sendable {
  var lastScanUnixMilliseconds: Int64
  var files: [String: TokenCostCachedFile]
  var days: [String: TokenCostCachedDay]

  init(
    lastScanUnixMilliseconds: Int64 = 0,
    files: [String: TokenCostCachedFile] = [:],
    days: [String: TokenCostCachedDay] = [:]
  ) {
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
