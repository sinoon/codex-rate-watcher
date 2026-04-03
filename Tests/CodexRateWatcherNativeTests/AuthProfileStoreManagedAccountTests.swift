import XCTest
@testable import CodexRateWatcherNative
@testable import CodexRateKit

final class AuthProfileStoreManagedAccountTests: XCTestCase {

  private var tempDir: URL!

  override func setUp() {
    super.setUp()
    tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tempDir)
    super.tearDown()
  }

  func testSyncManagedAccountCreatesProfileFromManagedHomeAuth() async throws {
    let harness = try makeHarness()
    let managedAuthData = Self.makeAuthData(email: "sync@example.com", accountID: "acct_sync", accessTokenSuffix: "sync")
    try managedAuthData.write(to: harness.managedAuthURL, options: .atomic)

    let account = ManagedCodexAccount(
      id: UUID(),
      email: "sync@example.com",
      managedHomePath: harness.managedHomeURL.path,
      accountID: "acct_sync",
      createdAt: Date(),
      updatedAt: Date(),
      lastAuthenticatedAt: Date()
    )

    let profiles = try await harness.store.syncManagedAccount(account)

    XCTAssertEqual(profiles.count, 1)
    XCTAssertEqual(profiles.first?.email, "sync@example.com")
    XCTAssertEqual(profiles.first?.accountID, "acct_sync")
    XCTAssertTrue(FileManager.default.fileExists(atPath: harness.paths.profileIndexFile.path))
  }

  func testSyncManagedAccountUpdatesExistingProfileInsteadOfDuplicating() async throws {
    let harness = try makeHarness()
    let account = ManagedCodexAccount(
      id: UUID(),
      email: "dup@example.com",
      managedHomePath: harness.managedHomeURL.path,
      accountID: "acct_dup",
      createdAt: Date(),
      updatedAt: Date(),
      lastAuthenticatedAt: Date()
    )

    try Self.makeAuthData(email: "dup@example.com", accountID: "acct_dup", accessTokenSuffix: "old")
      .write(to: harness.managedAuthURL, options: .atomic)
    _ = try await harness.store.syncManagedAccount(account)

    try Self.makeAuthData(email: "dup@example.com", accountID: "acct_dup", accessTokenSuffix: "new")
      .write(to: harness.managedAuthURL, options: .atomic)
    let profiles = try await harness.store.syncManagedAccount(account)

    XCTAssertEqual(profiles.count, 1)
    XCTAssertEqual(profiles.first?.email, "dup@example.com")
    XCTAssertEqual(profiles.first?.accountID, "acct_dup")
  }

  func testSwitchToProfilePrefersManagedHomeAuthOverSnapshot() async throws {
    let harness = try makeHarness()
    let managedData = Self.makeAuthData(email: "switch@example.com", accountID: "acct_switch", accessTokenSuffix: "managed")
    try managedData.write(to: harness.managedAuthURL, options: .atomic)

    let account = ManagedCodexAccount(
      id: UUID(),
      email: "switch@example.com",
      managedHomePath: harness.managedHomeURL.path,
      accountID: "acct_switch",
      createdAt: Date(),
      updatedAt: Date(),
      lastAuthenticatedAt: Date()
    )
    try harness.accountStore.storeAccounts(ManagedCodexAccountSet(accounts: [account]))

    let profiles = try await harness.store.syncManagedAccount(account)
    let profile = try XCTUnwrap(profiles.first)

    let staleData = Self.makeAuthData(email: "switch@example.com", accountID: "acct_switch", accessTokenSuffix: "stale")
    let snapshotURL = harness.paths.profilesDirectory.appending(path: profile.snapshotFileName)
    try staleData.write(to: snapshotURL, options: .atomic)

    try await harness.store.switchToProfile(id: profile.id)

    let currentData = try Data(contentsOf: harness.liveAuthURL)
    XCTAssertEqual(currentData, managedData)
  }

  func testValidateProfilesDoesNotOverwriteProfilesThatOnlyShareManagedEmail() async throws {
    let harness = try makeHarness()
    let sharedEmail = "same@example.com"
    let currentSnapshot = Self.makeAuthData(email: sharedEmail, accountID: "acct_current", accessTokenSuffix: "current-profile")
    let historicalSnapshot = Self.makeAuthData(email: sharedEmail, accountID: "acct_historical", accessTokenSuffix: "historical-profile")
    let managedSnapshot = Self.makeAuthData(email: sharedEmail, accountID: "acct_current", accessTokenSuffix: "managed-home")

    try managedSnapshot.write(to: harness.managedAuthURL, options: .atomic)

    let managedAccount = ManagedCodexAccount(
      id: UUID(),
      email: sharedEmail,
      managedHomePath: harness.managedHomeURL.path,
      accountID: "acct_current",
      createdAt: Date(),
      updatedAt: Date(),
      lastAuthenticatedAt: Date()
    )
    try harness.accountStore.storeAccounts(ManagedCodexAccountSet(accounts: [managedAccount]))

    let currentProfileID = UUID()
    let historicalProfileID = UUID()
    let currentProfileFile = "\(currentProfileID.uuidString).json"
    let historicalProfileFile = "\(historicalProfileID.uuidString).json"
    try FileManager.default.createDirectory(at: harness.paths.profilesDirectory, withIntermediateDirectories: true)
    try currentSnapshot.write(to: harness.paths.profilesDirectory.appending(path: currentProfileFile), options: .atomic)
    try historicalSnapshot.write(to: harness.paths.profilesDirectory.appending(path: historicalProfileFile), options: .atomic)

    let authStore = AuthStore(fileURL: harness.liveAuthURL)
    let currentEnvelope = try authStore.envelope(from: currentSnapshot)
    let historicalEnvelope = try authStore.envelope(from: historicalSnapshot)
    let now = Date()
    try Self.writeProfiles([
      AuthProfileRecord(
        id: currentProfileID,
        fingerprint: currentEnvelope.fingerprint,
        snapshotFileName: currentProfileFile,
        authMode: currentEnvelope.snapshot.authMode,
        accountID: "acct_current",
        email: sharedEmail,
        createdAt: now,
        lastSeenAt: now
      ),
      AuthProfileRecord(
        id: historicalProfileID,
        fingerprint: historicalEnvelope.fingerprint,
        snapshotFileName: historicalProfileFile,
        authMode: historicalEnvelope.snapshot.authMode,
        accountID: "acct_historical",
        email: sharedEmail,
        createdAt: now.addingTimeInterval(-60),
        lastSeenAt: now.addingTimeInterval(-60)
      ),
    ], to: harness.paths.profileIndexFile)

    _ = await harness.store.validateProfiles(using: Self.makeUsageAPIClient())

    let persistedHistorical = try Data(contentsOf: harness.paths.profilesDirectory.appending(path: historicalProfileFile))
    let persistedHistoricalEnvelope = try authStore.envelope(from: persistedHistorical)
    XCTAssertEqual(persistedHistoricalEnvelope.snapshot.accountID, "acct_historical")
  }

  func testCaptureCurrentAuthIfNeededDeduplicatesUsingSnapshotAccountID() async throws {
    let harness = try makeHarness()
    let sharedEmail = "same@example.com"
    let liveData = Self.makeAuthData(email: sharedEmail, accountID: "acct_live", accessTokenSuffix: "live")
    let duplicateData = Self.makeAuthData(email: sharedEmail, accountID: "acct_live", accessTokenSuffix: "duplicate")
    try liveData.write(to: harness.liveAuthURL, options: .atomic)

    let firstProfileID = UUID()
    let secondProfileID = UUID()
    let firstProfileFile = "\(firstProfileID.uuidString).json"
    let secondProfileFile = "\(secondProfileID.uuidString).json"
    try FileManager.default.createDirectory(at: harness.paths.profilesDirectory, withIntermediateDirectories: true)
    try duplicateData.write(to: harness.paths.profilesDirectory.appending(path: firstProfileFile), options: .atomic)
    try duplicateData.write(to: harness.paths.profilesDirectory.appending(path: secondProfileFile), options: .atomic)

    let authStore = AuthStore(fileURL: harness.liveAuthURL)
    let duplicateEnvelope = try authStore.envelope(from: duplicateData)
    let now = Date()
    try Self.writeProfiles([
      AuthProfileRecord(
        id: firstProfileID,
        fingerprint: duplicateEnvelope.fingerprint,
        snapshotFileName: firstProfileFile,
        authMode: duplicateEnvelope.snapshot.authMode,
        accountID: "stale_a",
        email: sharedEmail,
        createdAt: now,
        lastSeenAt: now
      ),
      AuthProfileRecord(
        id: secondProfileID,
        fingerprint: duplicateEnvelope.fingerprint,
        snapshotFileName: secondProfileFile,
        authMode: duplicateEnvelope.snapshot.authMode,
        accountID: "stale_b",
        email: sharedEmail,
        createdAt: now.addingTimeInterval(-60),
        lastSeenAt: now.addingTimeInterval(-60)
      ),
    ], to: harness.paths.profileIndexFile)

    let profiles = try await harness.store.captureCurrentAuthIfNeeded()

    XCTAssertEqual(profiles.count, 1)
    XCTAssertEqual(profiles.first?.accountID, "acct_live")
  }

  func testValidateProfilesKeepsCurrentLiveAuthWhenManagedHomeIsStale() async throws {
    let harness = try makeHarness()
    let liveData = Self.makeAuthData(
      email: "current@example.com",
      accountID: "acct_current",
      accessTokenSuffix: "live-current"
    )
    let staleManagedData = Self.makeAuthData(
      email: "current@example.com",
      accountID: "acct_current",
      accessTokenSuffix: "managed-stale"
    )
    try liveData.write(to: harness.liveAuthURL, options: .atomic)
    try staleManagedData.write(to: harness.managedAuthURL, options: .atomic)

    let managedAccount = ManagedCodexAccount(
      id: UUID(),
      email: "current@example.com",
      managedHomePath: harness.managedHomeURL.path,
      accountID: "acct_current",
      createdAt: Date(),
      updatedAt: Date(),
      lastAuthenticatedAt: Date()
    )
    try harness.accountStore.storeAccounts(ManagedCodexAccountSet(accounts: [managedAccount]))

    let profiles = try await harness.store.captureCurrentAuthIfNeeded()
    let profile = try XCTUnwrap(profiles.first)
    let snapshotURL = harness.paths.profilesDirectory.appending(path: profile.snapshotFileName)

    XCTAssertEqual(try Data(contentsOf: snapshotURL), liveData)

    _ = await harness.store.validateProfiles(using: Self.makeUsageAPIClient())

    XCTAssertEqual(try Data(contentsOf: snapshotURL), liveData)
    XCTAssertEqual(try Data(contentsOf: harness.managedAuthURL), liveData)
  }

  private func makeHarness() throws -> AuthProfileHarness {
    let rootURL = tempDir.appending(path: "app-support", directoryHint: .isDirectory)
    let paths = AuthProfileStorePaths(
      rootDirectory: rootURL,
      profilesDirectory: rootURL.appending(path: "auth-profiles", directoryHint: .isDirectory),
      profileIndexFile: rootURL.appending(path: "profiles.json"),
      backupsDirectory: rootURL.appending(path: "auth-backups", directoryHint: .isDirectory)
    )
    let liveAuthURL = tempDir.appending(path: "live-auth.json")
    let managedHomeURL = tempDir.appending(path: "managed-home", directoryHint: .isDirectory)
    let managedAuthURL = managedHomeURL.appending(path: "auth.json")
    try FileManager.default.createDirectory(at: managedHomeURL, withIntermediateDirectories: true)
    try Self.makeAuthData(email: "live@example.com", accountID: "acct_live", accessTokenSuffix: "live")
      .write(to: liveAuthURL, options: .atomic)

    let accountStore = InMemoryManagedAccountStore()
    let store = AuthProfileStore(
      authStore: AuthStore(fileURL: liveAuthURL),
      managedAccountStore: accountStore,
      paths: paths
    )

    return AuthProfileHarness(
      store: store,
      paths: paths,
      liveAuthURL: liveAuthURL,
      managedHomeURL: managedHomeURL,
      managedAuthURL: managedAuthURL,
      accountStore: accountStore
    )
  }

  private static func makeAuthData(
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

  private static func writeProfiles(_ profiles: [AuthProfileRecord], to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(profiles)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
  }

  private static func makeUsageAPIClient() -> UsageAPIClient {
    AuthProfileUsageAPIURLProtocol.responseStatusCode = 200
    AuthProfileUsageAPIURLProtocol.responseData = Data(
      """
      {
        "plan_type": "team",
        "rate_limit": {
          "allowed": true,
          "limit_reached": false,
          "primary_window": {
            "used_percent": 0,
            "limit_window_seconds": 18000,
            "reset_after_seconds": 9000,
            "reset_at": 4102444800
          },
          "secondary_window": {
            "used_percent": 0,
            "limit_window_seconds": 604800,
            "reset_after_seconds": 86400,
            "reset_at": 4102444800
          }
        },
        "code_review_rate_limit": {
          "allowed": true,
          "limit_reached": false,
          "primary_window": {
            "used_percent": 0,
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

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AuthProfileUsageAPIURLProtocol.self]
    return UsageAPIClient(session: URLSession(configuration: configuration))
  }
}

private struct AuthProfileHarness {
  let store: AuthProfileStore
  let paths: AuthProfileStorePaths
  let liveAuthURL: URL
  let managedHomeURL: URL
  let managedAuthURL: URL
  let accountStore: InMemoryManagedAccountStore
}

private final class InMemoryManagedAccountStore: @unchecked Sendable, ManagedCodexAccountStoring {
  var snapshot = ManagedCodexAccountSet(accounts: [])

  func loadAccounts() throws -> ManagedCodexAccountSet {
    snapshot
  }

  func storeAccounts(_ accounts: ManagedCodexAccountSet) throws {
    snapshot = accounts
  }
}

private final class AuthProfileUsageAPIURLProtocol: URLProtocol {
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
