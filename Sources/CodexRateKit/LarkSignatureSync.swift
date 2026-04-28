import Foundation

public enum LarkSignatureFormatter {
  public static func summary(
    snapshot: TokenCostSnapshot,
    label: String = "Codex",
    useLocalSummary: Bool = false,
    timeZone: TimeZone = .autoupdatingCurrent,
    maxLength: Int = 200
  ) -> String {
    let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
    let sourceLabel = sourceLabel(for: snapshot, useLocalSummary: useLocalSummary)
    let todayTokens = useLocalSummary ? (snapshot.localSummary?.todayTokens ?? snapshot.todayTokens) : snapshot.todayTokens
    let todayCost = useLocalSummary ? (snapshot.localSummary?.todayCostUSD ?? snapshot.todayCostUSD) : snapshot.todayCostUSD
    let last7Tokens = useLocalSummary ? (snapshot.localSummary?.last7DaysTokens ?? snapshot.last7DaysTokens) : snapshot.last7DaysTokens
    let last7Cost = useLocalSummary ? (snapshot.localSummary?.last7DaysCostUSD ?? snapshot.last7DaysCostUSD) : snapshot.last7DaysCostUSD
    let last30Tokens = useLocalSummary ? (snapshot.localSummary?.last30DaysTokens ?? snapshot.last30DaysTokens) : snapshot.last30DaysTokens
    let last30Cost = useLocalSummary ? (snapshot.localSummary?.last30DaysCostUSD ?? snapshot.last30DaysCostUSD) : snapshot.last30DaysCostUSD
    let updatedAt = updatedTimeLabel(snapshot.updatedAt, timeZone: timeZone)

    var parts: [String] = []
    if !trimmedLabel.isEmpty {
      let header = [trimmedLabel, sourceLabel]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
      if !header.isEmpty {
        parts.append(header)
      }
    }

    let hasAnyUsage = todayTokens != nil || todayCost != nil || last7Tokens != nil || last7Cost != nil || last30Tokens != nil || last30Cost != nil
    if !hasAnyUsage {
      parts.append("暂无 token 数据")
      parts.append(updatedAt)
      return fitted(parts: parts, maxLength: maxLength)
    }

    let todayLabel = trimmedLabel.isEmpty ? "Token 今日" : "今日"
    if let todayPart = metricPart(windowLabel: todayLabel, tokens: todayTokens, costUSD: todayCost) {
      parts.append(todayPart)
    }
    if let sevenDayPart = metricPart(windowLabel: "7天", tokens: last7Tokens, costUSD: last7Cost) {
      parts.append(sevenDayPart)
    }
    if let thirtyDayPart = metricPart(windowLabel: "30天", tokens: last30Tokens, costUSD: last30Cost) {
      parts.append(thirtyDayPart)
    }

    return fitted(parts: parts, maxLength: maxLength)
  }

  private static func sourceLabel(for snapshot: TokenCostSnapshot, useLocalSummary: Bool) -> String {
    if useLocalSummary {
      return "本机"
    }
    if snapshot.source?.mode == .iCloudMerged {
      return "全设备"
    }
    return "本机"
  }

  private static func metricPart(windowLabel: String, tokens: Int?, costUSD: Double?) -> String? {
    let tokenPart = tokens.map(TokenCostFormatting.tokenCount)
    let costPart = costUSD.map(compactUSD)

    let detail: String?
    switch (tokenPart, costPart) {
    case let (.some(tokenPart), .some(costPart)):
      detail = "\(tokenPart)/\(costPart)"
    case let (.some(tokenPart), .none):
      detail = tokenPart
    case let (.none, .some(costPart)):
      detail = costPart
    case (.none, .none):
      detail = nil
    }

    guard let detail else {
      return nil
    }
    return "\(windowLabel)\(detail)"
  }

  private static func compactUSD(_ value: Double) -> String {
    let absolute = abs(value)
    let sign = value < 0 ? "-" : ""

    switch absolute {
    case 1_000_000...:
      return sign + "$" + compactNumber(absolute / 1_000_000, suffix: "m")
    case 1_000...:
      return sign + "$" + compactNumber(absolute / 1_000, suffix: "k")
    case 10...:
      return sign + "$" + String(Int(absolute.rounded()))
    case 1...:
      return sign + "$" + decimalString(absolute, maximumFractionDigits: 1)
    default:
      return sign + "$" + decimalString(absolute, maximumFractionDigits: 2)
    }
  }

  private static func compactNumber(_ value: Double, suffix: String) -> String {
    decimalString(value, maximumFractionDigits: 1) + suffix
  }

  private static func decimalString(_ value: Double, maximumFractionDigits: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = maximumFractionDigits
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(maximumFractionDigits)f", value)
  }

  private static func updatedTimeLabel(_ date: Date, timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.timeZone = timeZone
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
  }

  private static func fitted(parts: [String], maxLength: Int) -> String {
    var working = parts
    var text = working.joined(separator: " · ")
    if text.count <= maxLength {
      return text
    }

    if working.count > 3 {
      working.removeFirst()
      text = working.joined(separator: " · ")
    }
    if text.count <= maxLength {
      return text
    }

    return String(text.prefix(maxLength))
  }
}

public enum LarkSlotSyncError: LocalizedError, Equatable {
  case invalidResponse
  case httpError(statusCode: Int, message: String)

  public var errorDescription: String? {
    switch self {
    case .invalidResponse:
      return "飞书 slot 接口返回了非 HTTP 响应。"
    case .httpError(let statusCode, let message):
      return Self.friendlyMessage(statusCode: statusCode, raw: message)
    }
  }

  private static func friendlyMessage(statusCode: Int, raw: String) -> String {
    switch statusCode {
    case 400:
      if raw.contains("invalid_slot") {
        return "slotId 无效，或不属于当前用户 (400)"
      }
      return "请求参数不合法 (400)"
    case 401:
      return "credential 无效或已失效，请重新登录 (401)"
    case 429:
      return "写入过于频繁，请稍后再试 (429)"
    default:
      if raw.isEmpty {
        return "请求失败 (\(statusCode))"
      }
      let short = raw.count > 80 ? String(raw.prefix(80)) + "…" : raw
      return "请求失败 (\(statusCode))：\(short)"
    }
  }
}

public struct LarkSlotClient: @unchecked Sendable {
  private let baseURL: URL
  private let session: URLSession
  private let encoder = JSONEncoder()

  public init(
    baseURL: URL = URL(string: "https://l.garyyang.work")!,
    session: URLSession = RateWatcherURLSessionFactory.shared
  ) {
    self.baseURL = baseURL
    self.session = session
  }

  public func updateSlot(
    credential: String,
    slotID: String,
    value: String
  ) async throws {
    let endpoint = baseURL.appending(path: "api/slot/update")
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
    request.httpBody = try encoder.encode(UpdatePayload(slotId: slotID, value: value))

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw LarkSlotSyncError.invalidResponse
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      let message = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      throw LarkSlotSyncError.httpError(statusCode: httpResponse.statusCode, message: message)
    }
  }

  private struct UpdatePayload: Codable {
    let slotId: String
    let value: String
  }
}

public struct LarkSignatureAutoSyncConfig: Codable, Equatable, Sendable {
  public var enabled: Bool
  public var credential: String
  public var slotID: String
  public var label: String
  public var baseURL: String
  public var useLocalSummary: Bool
  public var lastSyncedValue: String?
  public var lastSyncedAt: Date?

  public init(
    enabled: Bool = false,
    credential: String = "",
    slotID: String = "",
    label: String = "",
    baseURL: String = "https://l.garyyang.work",
    useLocalSummary: Bool = false,
    lastSyncedValue: String? = nil,
    lastSyncedAt: Date? = nil
  ) {
    self.enabled = enabled
    self.credential = credential
    self.slotID = slotID
    self.label = label
    self.baseURL = baseURL
    self.useLocalSummary = useLocalSummary
    self.lastSyncedValue = lastSyncedValue
    self.lastSyncedAt = lastSyncedAt
  }

  public var isConfigured: Bool {
    enabled && !credential.isEmpty && !slotID.isEmpty
  }
}

public actor LarkSignatureAutoSyncStore {
  private let fileURL: URL
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  private let fileManager = FileManager.default

  public init(fileURL: URL = AppPaths.larkSignatureSyncConfigFile) {
    self.fileURL = fileURL
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
  }

  public func load() -> LarkSignatureAutoSyncConfig {
    guard let data = try? Data(contentsOf: fileURL),
          let config = try? decoder.decode(LarkSignatureAutoSyncConfig.self, from: data) else {
      return LarkSignatureAutoSyncConfig()
    }
    return config
  }

  public func save(_ config: LarkSignatureAutoSyncConfig) {
    let directory = fileURL.deletingLastPathComponent()
    try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    guard let data = try? encoder.encode(config) else { return }
    try? data.write(to: fileURL, options: .atomic)
  }

  public func disable() {
    save(LarkSignatureAutoSyncConfig())
  }
}

public protocol LarkSignatureAutoSyncing: Sendable {
  func syncIfNeeded(snapshot: TokenCostSnapshot, now: Date) async
}

public struct NoopLarkSignatureAutoSyncService: LarkSignatureAutoSyncing {
  public init() {}

  public func syncIfNeeded(snapshot _: TokenCostSnapshot, now _: Date) async {}
}

public actor LarkSignatureAutoSyncService: LarkSignatureAutoSyncing {
  private let store: LarkSignatureAutoSyncStore
  private let clientFactory: @Sendable (URL) -> LarkSlotClient
  private let minSyncInterval: TimeInterval
  private let timeZone: TimeZone

  public init(
    store: LarkSignatureAutoSyncStore = LarkSignatureAutoSyncStore(),
    clientFactory: @escaping @Sendable (URL) -> LarkSlotClient = { baseURL in
      LarkSlotClient(baseURL: baseURL)
    },
    minSyncInterval: TimeInterval = 60,
    timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .autoupdatingCurrent
  ) {
    self.store = store
    self.clientFactory = clientFactory
    self.minSyncInterval = minSyncInterval
    self.timeZone = timeZone
  }

  public func syncIfNeeded(snapshot: TokenCostSnapshot, now: Date = Date()) async {
    var config = await store.load()
    guard config.isConfigured else { return }

    let value = LarkSignatureFormatter.summary(
      snapshot: snapshot,
      label: config.label,
      useLocalSummary: config.useLocalSummary,
      timeZone: timeZone
    )

    if value == config.lastSyncedValue {
      return
    }

    if let lastSyncedAt = config.lastSyncedAt,
       now.timeIntervalSince(lastSyncedAt) < minSyncInterval {
      return
    }

    guard let baseURL = URL(string: config.baseURL) else { return }

    do {
      try await clientFactory(baseURL).updateSlot(
        credential: config.credential,
        slotID: config.slotID,
        value: value
      )
      config.lastSyncedValue = value
      config.lastSyncedAt = now
      await store.save(config)
    } catch {
      // Keep auto-sync best-effort; UI refresh should not fail because Lark sync failed.
      config.lastSyncedAt = now
      await store.save(config)
      return
    }
  }
}
