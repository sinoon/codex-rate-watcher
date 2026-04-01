import XCTest
@testable import CodexRateWatcherNative
@testable import CodexRateKit

@MainActor
final class UsageMonitorManagedAccountTests: XCTestCase {

  func testAddManagedAccountKeepsCurrentProfileActive() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let liveAuthURL = tempDir.appending(path: "live-auth.json")
    let currentAuthData = Self.makeAuthData(email: "current@example.com", accountID: "acct_current", accessTokenSuffix: "current")
    try currentAuthData.write(to: liveAuthURL, options: .atomic)

    let paths = AuthProfileStorePaths(
      rootDirectory: tempDir.appending(path: "app-support", directoryHint: .isDirectory),
      profilesDirectory: tempDir.appending(path: "app-support/auth-profiles", directoryHint: .isDirectory),
      profileIndexFile: tempDir.appending(path: "app-support/profiles.json"),
      backupsDirectory: tempDir.appending(path: "app-support/auth-backups", directoryHint: .isDirectory)
    )
    let managedStore = InMemoryManagedMonitorAccountStore()
    let profileStore = AuthProfileStore(
      authStore: AuthStore(fileURL: liveAuthURL),
      managedAccountStore: managedStore,
      paths: paths
    )
    let existingProfiles = try await profileStore.captureCurrentAuthIfNeeded()
    let currentProfileID = try XCTUnwrap(existingProfiles.first?.id)

    let managedHomeURL = tempDir.appending(path: "managed-home", directoryHint: .isDirectory)
    let loginRunner = UsageMonitorStubManagedLoginRunner { homePath, _ in
      let authURL = URL(fileURLWithPath: homePath, isDirectory: true).appending(path: "auth.json")
      let addedAuthData = Self.makeAuthData(email: "added@example.com", accountID: "acct_added", accessTokenSuffix: "added")
      try addedAuthData.write(to: authURL, options: .atomic)
      return .init(outcome: .success, output: "ok")
    }
    let service = ManagedCodexAccountService(
      store: managedStore,
      homeFactory: UsageMonitorStubManagedHomeFactory(url: managedHomeURL),
      loginRunner: loginRunner
    )
    UsageMonitorURLProtocol.responseStatusCode = 200
    UsageMonitorURLProtocol.responseData = Self.makeUsageResponseData()
    let sessionConfig = URLSessionConfiguration.ephemeral
    sessionConfig.protocolClasses = [UsageMonitorURLProtocol.self]
    let apiClient = UsageAPIClient(session: URLSession(configuration: sessionConfig))

    let monitor = UsageMonitor(
      authStore: AuthStore(fileURL: liveAuthURL),
      apiClient: apiClient,
      profileStore: profileStore,
      managedAccountService: service
    )

    var observedState: UsageMonitor.State?
    let observerID = monitor.addObserver { state in
      observedState = state
    }
    defer { monitor.removeObserver(observerID) }

    _ = try await monitor.addManagedAccount(timeout: 1)

    XCTAssertEqual(observedState?.activeProfileID, currentProfileID)
    XCTAssertEqual(observedState?.profiles.count, 2)
    XCTAssertTrue(observedState?.profiles.contains(where: { $0.email == "added@example.com" }) == true)
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

private final class InMemoryManagedMonitorAccountStore: @unchecked Sendable, ManagedCodexAccountStoring {
  var snapshot = ManagedCodexAccountSet(accounts: [])

  func loadAccounts() throws -> ManagedCodexAccountSet {
    snapshot
  }

  func storeAccounts(_ accounts: ManagedCodexAccountSet) throws {
    snapshot = accounts
  }
}

private struct UsageMonitorStubManagedHomeFactory: ManagedCodexHomeProducing {
  let url: URL

  func makeHomeURL() -> URL {
    url
  }

  func validateManagedHomeForDeletion(_ url: URL) throws {
    _ = url
  }
}

private struct UsageMonitorStubManagedLoginRunner: ManagedCodexLoginRunning {
  let runHandler: @Sendable (String, TimeInterval) throws -> CodexLoginRunner.Result

  func run(homePath: String, timeout: TimeInterval) async -> CodexLoginRunner.Result {
    do {
      return try runHandler(homePath, timeout)
    } catch {
      return .init(outcome: .launchFailed(error.localizedDescription), output: error.localizedDescription)
    }
  }
}

private final class UsageMonitorURLProtocol: URLProtocol {
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
