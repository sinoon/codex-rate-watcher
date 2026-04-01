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

    TokenCostMonitorURLProtocol.responseStatusCode = 200
    TokenCostMonitorURLProtocol.responseData = Self.makeUsageResponseData()
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
      tokenCostLoader: StubTokenCostLoader(snapshot: expectedSnapshot)
    )

    var observedState: UsageMonitor.State?
    let observerID = monitor.addObserver { state in
      observedState = state
    }
    defer { monitor.removeObserver(observerID) }

    await monitor.refresh(manual: true)

    XCTAssertEqual(observedState?.tokenCostSnapshot, expectedSnapshot)
  }

  nonisolated private static func makeAuthData(
    email: String,
    accountID: String,
    accessTokenSuffix: String
  ) -> Data {
    let payloadJSON = #"{"https://api.openai.com/profile":{"email":"\#(email)"}}"#
    let payload = Data(payloadJSON.utf8).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    let jwt = "header.\(payload).\(accessTokenSuffix)"

    let authJSON = """
    {
      "auth_mode": "chatgpt",
      "tokens": {
        "access_token": "\(jwt)",
        "account_id": "\(accountID)"
      }
    }
    """

    return Data(authJSON.utf8)
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

private final class TokenCostMonitorURLProtocol: URLProtocol {
  nonisolated(unsafe) static var responseStatusCode = 200
  nonisolated(unsafe) static var responseData = Data()

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let response = HTTPURLResponse(
      url: request.url ?? URL(string: "https://example.com")!,
      statusCode: Self.responseStatusCode,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Self.responseData)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
