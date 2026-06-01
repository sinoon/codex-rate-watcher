import XCTest
@testable import CodexRateWatcherNative
@testable import CodexRateKit

@MainActor
final class UsageMonitorTokenCostTests: XCTestCase {

  func testRefreshPublishesTokenCostSnapshotIntoState() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let liveAuthURL = tempDir.appending(path: "auth.json")
    try Self.makeAuthData(
      email: "current@example.com",
      accountID: "acct_current",
      accessTokenSuffix: "current"
    ).write(to: liveAuthURL, options: .atomic)

    let paths = AuthProfileStorePaths(
      rootDirectory: tempDir.appending(path: "app-support", directoryHint: .isDirectory),
      profilesDirectory: tempDir.appending(path: "app-support/auth-profiles", directoryHint: .isDirectory),
      profileIndexFile: tempDir.appending(path: "app-support/profiles.json"),
      backupsDirectory: tempDir.appending(path: "app-support/auth-backups", directoryHint: .isDirectory)
    )
    let profileStore = AuthProfileStore(
      authStore: AuthStore(fileURL: liveAuthURL),
      paths: paths
    )
    let sampleStore = SampleStore(fileURL: paths.rootDirectory.appending(path: "samples.json"))

    TokenCostMonitorURLProtocol.responseStatusCode = 200
    TokenCostMonitorURLProtocol.responseData = Self.makeUsageResponseData()
    TokenCostMonitorURLProtocol.responseHandler = nil
    let sessionConfig = URLSessionConfiguration.ephemeral
    sessionConfig.protocolClasses = [TokenCostMonitorURLProtocol.self]
    let apiClient = UsageAPIClient(session: URLSession(configuration: sessionConfig))

    let expectedSnapshot = TokenCostSnapshot(
      todayTokens: 12_345,
      todayCostUSD: 1.23,
      last30DaysTokens: 67_890,
      last30DaysCostUSD: 4.56,
      daily: [],
      updatedAt: Date(timeIntervalSince1970: 1_775_000_000)
    )

    let monitor = UsageMonitor(
      authStore: AuthStore(fileURL: liveAuthURL),
      apiClient: apiClient,
      tokenCostLoader: StubTokenCostLoader(snapshot: expectedSnapshot),
      sampleStore: sampleStore,
      profileStore: profileStore
    )

    var observedState: UsageMonitor.State?
    let observerID = monitor.addObserver { state in
      observedState = state
    }
    defer { monitor.removeObserver(observerID) }

    await monitor.refresh(manual: true)

    XCTAssertEqual(observedState?.tokenCostSnapshot, expectedSnapshot)
  }

  func testRefreshTriggersLarkSignatureAutoSyncAfterLoadingTokenCostSnapshot() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let liveAuthURL = tempDir.appending(path: "auth.json")
    try Self.makeAuthData(
      email: "current@example.com",
      accountID: "acct_current",
      accessTokenSuffix: "current"
    ).write(to: liveAuthURL, options: .atomic)

    let paths = AuthProfileStorePaths(
      rootDirectory: tempDir.appending(path: "app-support", directoryHint: .isDirectory),
      profilesDirectory: tempDir.appending(path: "app-support/auth-profiles", directoryHint: .isDirectory),
      profileIndexFile: tempDir.appending(path: "app-support/profiles.json"),
      backupsDirectory: tempDir.appending(path: "app-support/auth-backups", directoryHint: .isDirectory)
    )
    let profileStore = AuthProfileStore(
      authStore: AuthStore(fileURL: liveAuthURL),
      paths: paths
    )
    let sampleStore = SampleStore(fileURL: paths.rootDirectory.appending(path: "samples.json"))

    TokenCostMonitorURLProtocol.responseStatusCode = 200
    TokenCostMonitorURLProtocol.responseData = Self.makeUsageResponseData()
    TokenCostMonitorURLProtocol.responseHandler = nil
    let sessionConfig = URLSessionConfiguration.ephemeral
    sessionConfig.protocolClasses = [TokenCostMonitorURLProtocol.self]
    let apiClient = UsageAPIClient(session: URLSession(configuration: sessionConfig))

    let expectedSnapshot = TokenCostSnapshot(
      todayTokens: 12_345,
      todayCostUSD: 1.23,
      last30DaysTokens: 67_890,
      last30DaysCostUSD: 4.56,
      daily: [],
      updatedAt: Date(timeIntervalSince1970: 1_775_000_000)
    )
    let autoSync = StubLarkSignatureAutoSync()

    let monitor = UsageMonitor(
      authStore: AuthStore(fileURL: liveAuthURL),
      apiClient: apiClient,
      tokenCostLoader: StubTokenCostLoader(snapshot: expectedSnapshot),
      larkSignatureAutoSync: autoSync,
      sampleStore: sampleStore,
      profileStore: profileStore
    )

    await monitor.refresh(manual: true)

    let syncedSnapshots = await autoSync.snapshots
    XCTAssertEqual(syncedSnapshots, [expectedSnapshot])
  }

  func testRefreshProactivelyRefreshesCurrentAuthWhenAccessTokenNearExpiration() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let now = Date()
    let liveAuthURL = tempDir.appending(path: "auth.json")
    let expiringData = Self.makeAuthData(
      email: "current@example.com",
      accountID: "acct_current",
      accessTokenSuffix: "expiring",
      refreshTokenSuffix: "old-refresh",
      issuedAt: now.addingTimeInterval(-9 * 24 * 60 * 60),
      expiresAt: now.addingTimeInterval(30 * 60)
    )
    let freshData = Self.makeAuthData(
      email: "current@example.com",
      accountID: "acct_current",
      accessTokenSuffix: "fresh",
      refreshTokenSuffix: "fresh-refresh",
      issuedAt: now,
      expiresAt: now.addingTimeInterval(10 * 24 * 60 * 60)
    )
    try expiringData.write(to: liveAuthURL, options: .atomic)

    let paths = AuthProfileStorePaths(
      rootDirectory: tempDir.appending(path: "app-support", directoryHint: .isDirectory),
      profilesDirectory: tempDir.appending(path: "app-support/auth-profiles", directoryHint: .isDirectory),
      profileIndexFile: tempDir.appending(path: "app-support/profiles.json"),
      backupsDirectory: tempDir.appending(path: "app-support/auth-backups", directoryHint: .isDirectory)
    )
    let profileStore = AuthProfileStore(
      authStore: AuthStore(fileURL: liveAuthURL),
      paths: paths
    )
    let sampleStore = SampleStore(fileURL: paths.rootDirectory.appending(path: "samples.json"))
    let tokenRefresher = UsageMonitorFakeTokenRefresher { _ in freshData }
    let recorder = UsageMonitorAuthorizationRecorder()

    TokenCostMonitorURLProtocol.responseStatusCode = 200
    TokenCostMonitorURLProtocol.responseData = Self.makeUsageResponseData()
    TokenCostMonitorURLProtocol.responseHandler = { request in
      recorder.append(request)
      return (200, Self.makeUsageResponseData())
    }
    let sessionConfig = URLSessionConfiguration.ephemeral
    sessionConfig.protocolClasses = [TokenCostMonitorURLProtocol.self]
    let apiClient = UsageAPIClient(session: URLSession(configuration: sessionConfig))

    let monitor = UsageMonitor(
      authStore: AuthStore(fileURL: liveAuthURL),
      apiClient: apiClient,
      tokenRefresher: tokenRefresher,
      tokenCostLoader: StubTokenCostLoader(snapshot: TokenCostSnapshot(
        todayTokens: 0,
        todayCostUSD: nil,
        last30DaysTokens: 0,
        last30DaysCostUSD: nil,
        daily: [],
        updatedAt: now
      )),
      sampleStore: sampleStore,
      profileStore: profileStore
    )

    await monitor.refresh(manual: true)

    XCTAssertEqual(tokenRefresher.calls, 1)
    XCTAssertEqual(try Data(contentsOf: liveAuthURL), freshData)
    XCTAssertTrue(recorder.authorizations.last?.contains(".fresh") == true)
  }

  nonisolated private static func makeAuthData(
    email: String,
    accountID: String,
    accessTokenSuffix: String,
    refreshTokenSuffix: String? = nil,
    issuedAt: Date? = nil,
    expiresAt: Date? = nil
  ) -> Data {
    var payloadObject: [String: Any] = [
      "https://api.openai.com/profile": ["email": email]
    ]
    if let issuedAt {
      payloadObject["iat"] = Int(issuedAt.timeIntervalSince1970)
    }
    if let expiresAt {
      payloadObject["exp"] = Int(expiresAt.timeIntervalSince1970)
    }
    let payloadData = try! JSONSerialization.data(withJSONObject: payloadObject, options: [.sortedKeys])
    let payload = payloadData.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    let jwt = "header.\(payload).\(accessTokenSuffix)"

    var tokens = [
      "access_token": jwt,
      "account_id": accountID,
    ]
    if let refreshTokenSuffix {
      tokens["refresh_token"] = "refresh_\(refreshTokenSuffix)"
    }
    let authJSON: [String: Any] = [
      "auth_mode": "chatgpt",
      "tokens": tokens,
    ]

    return try! JSONSerialization.data(withJSONObject: authJSON, options: [.prettyPrinted, .sortedKeys])
  }

  nonisolated private static func makeUsageResponseData() -> Data {
    Data(
      """
      {
        "plan_type": "plus",
        "rate_limit": {
          "allowed": true,
          "limit_reached": false,
          "primary_window": {
            "used_percent": 10,
            "limit_window_seconds": 18000,
            "reset_after_seconds": 9000,
            "reset_at": 4102444800
          },
          "secondary_window": {
            "used_percent": 15,
            "limit_window_seconds": 604800,
            "reset_after_seconds": 86400,
            "reset_at": 4102444800
          }
        },
        "code_review_rate_limit": {
          "allowed": true,
          "limit_reached": false,
          "primary_window": {
            "used_percent": 20,
            "limit_window_seconds": 18000,
            "reset_after_seconds": 9000,
            "reset_at": 4102444800
          }
        },
        "credits": {
          "has_credits": false,
          "unlimited": false
        }
      }
      """.utf8
    )
  }
}

private struct StubTokenCostLoader: TokenCostSnapshotLoading {
  let snapshot: TokenCostSnapshot

  func loadSnapshot(now _: Date) async -> TokenCostSnapshot {
    snapshot
  }
}

private actor StubLarkSignatureAutoSync: LarkSignatureAutoSyncing {
  private(set) var snapshots: [TokenCostSnapshot] = []

  func syncIfNeeded(snapshot: TokenCostSnapshot, now _: Date) async {
    snapshots.append(snapshot)
  }
}

private final class UsageMonitorFakeTokenRefresher: AuthTokenRefreshing, @unchecked Sendable {
  nonisolated(unsafe) private(set) var calls = 0
  private let handler: @Sendable (Data) throws -> Data

  init(handler: @escaping @Sendable (Data) throws -> Data) {
    self.handler = handler
  }

  func refresh(currentAuthData: Data) async throws -> Data {
    calls += 1
    return try handler(currentAuthData)
  }
}

private final class UsageMonitorAuthorizationRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String] = []

  var authorizations: [String] {
    lock.lock()
    defer { lock.unlock() }
    return values
  }

  func append(_ request: URLRequest) {
    lock.lock()
    values.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
    lock.unlock()
  }
}

private final class TokenCostMonitorURLProtocol: URLProtocol {
  nonisolated(unsafe) static var responseStatusCode = 200
  nonisolated(unsafe) static var responseData = Data()
  nonisolated(unsafe) static var responseHandler: (@Sendable (URLRequest) -> (Int, Data))?

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let responsePayload = Self.responseHandler?(request) ?? (Self.responseStatusCode, Self.responseData)
    let response = HTTPURLResponse(
      url: request.url ?? URL(string: "https://example.com")!,
      statusCode: responsePayload.0,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: responsePayload.1)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
