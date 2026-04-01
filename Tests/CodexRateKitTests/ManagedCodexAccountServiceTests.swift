import XCTest
@testable import CodexRateKit

final class ManagedCodexAccountServiceTests: XCTestCase {

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

  func testAuthenticateManagedAccountCreatesManagedHomeAndStoresRecord() async throws {
    let homeURL = tempDir.appending(path: "managed-home-1", directoryHint: .isDirectory)
    let store = InMemoryManagedCodexAccountStore()
    let loginRunner = StubManagedCodexLoginRunner { homePath, _ in
      let authURL = URL(fileURLWithPath: homePath, isDirectory: true).appending(path: "auth.json")
      try Self.writeAuthJSON(
        to: authURL,
        email: "first@example.com",
        accountID: "acct_first"
      )
      return .init(outcome: .success, output: "ok")
    }
    let service = ManagedCodexAccountService(
      store: store,
      homeFactory: StubManagedCodexHomeFactory(url: homeURL),
      loginRunner: loginRunner
    )

    let account = try await service.authenticateManagedAccount(timeout: 1)

    XCTAssertEqual(account.email, "first@example.com")
    XCTAssertEqual(account.accountID, "acct_first")
    XCTAssertEqual(account.managedHomePath, homeURL.path)
    XCTAssertTrue(FileManager.default.fileExists(atPath: homeURL.appending(path: "auth.json").path))
    XCTAssertEqual(store.snapshot.accounts.count, 1)
  }

  func testAuthenticateManagedAccountFailsWhenAuthHasNoEmail() async {
    let homeURL = tempDir.appending(path: "managed-home-2", directoryHint: .isDirectory)
    let store = InMemoryManagedCodexAccountStore()
    let loginRunner = StubManagedCodexLoginRunner { homePath, _ in
      let authURL = URL(fileURLWithPath: homePath, isDirectory: true).appending(path: "auth.json")
      try Self.writeAuthJSON(
        to: authURL,
        email: nil,
        accountID: "acct_missing_email"
      )
      return .init(outcome: .success, output: "ok")
    }
    let service = ManagedCodexAccountService(
      store: store,
      homeFactory: StubManagedCodexHomeFactory(url: homeURL),
      loginRunner: loginRunner
    )

    await XCTAssertThrowsErrorAsync(try await service.authenticateManagedAccount(timeout: 1)) { error in
      XCTAssertEqual(error as? ManagedCodexAccountServiceError, .missingEmail)
    }
    XCTAssertEqual(store.snapshot.accounts.count, 0)
  }

  func testAuthenticateManagedAccountDoesNotMergeDifferentAccountIDsThatShareEmail() async throws {
    let oldHomeURL = tempDir.appending(path: "managed-home-old", directoryHint: .isDirectory)
    let newHomeURL = tempDir.appending(path: "managed-home-new", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: oldHomeURL, withIntermediateDirectories: true)

    let existingAccount = ManagedCodexAccount(
      id: UUID(),
      email: "dup@example.com",
      managedHomePath: oldHomeURL.path,
      accountID: "acct_old",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 1),
      lastAuthenticatedAt: Date(timeIntervalSince1970: 1)
    )
    let store = InMemoryManagedCodexAccountStore(
      snapshot: ManagedCodexAccountSet(accounts: [existingAccount])
    )
    let loginRunner = StubManagedCodexLoginRunner { homePath, _ in
      let authURL = URL(fileURLWithPath: homePath, isDirectory: true).appending(path: "auth.json")
      try Self.writeAuthJSON(
        to: authURL,
        email: "dup@example.com",
        accountID: "acct_new"
      )
      return .init(outcome: .success, output: "ok")
    }
    let service = ManagedCodexAccountService(
      store: store,
      homeFactory: StubManagedCodexHomeFactory(url: newHomeURL),
      loginRunner: loginRunner
    )

    let updated = try await service.authenticateManagedAccount(timeout: 1)

    XCTAssertNotEqual(updated.id, existingAccount.id)
    XCTAssertEqual(updated.email, existingAccount.email)
    XCTAssertEqual(updated.accountID, "acct_new")
    XCTAssertEqual(updated.managedHomePath, newHomeURL.path)
    XCTAssertTrue(FileManager.default.fileExists(atPath: oldHomeURL.path))
    XCTAssertEqual(store.snapshot.accounts.count, 2)
  }

  func testAuthenticateManagedAccountReconcilesDuplicateAccountIDAndDeletesOldHome() async throws {
    let oldHomeURL = tempDir.appending(path: "managed-home-same-account-old", directoryHint: .isDirectory)
    let newHomeURL = tempDir.appending(path: "managed-home-same-account-new", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: oldHomeURL, withIntermediateDirectories: true)

    let existingAccount = ManagedCodexAccount(
      id: UUID(),
      email: "dup@example.com",
      managedHomePath: oldHomeURL.path,
      accountID: "acct_same",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 1),
      lastAuthenticatedAt: Date(timeIntervalSince1970: 1)
    )
    let store = InMemoryManagedCodexAccountStore(
      snapshot: ManagedCodexAccountSet(accounts: [existingAccount])
    )
    let loginRunner = StubManagedCodexLoginRunner { homePath, _ in
      let authURL = URL(fileURLWithPath: homePath, isDirectory: true).appending(path: "auth.json")
      try Self.writeAuthJSON(
        to: authURL,
        email: "dup@example.com",
        accountID: "acct_same"
      )
      return .init(outcome: .success, output: "ok")
    }
    let service = ManagedCodexAccountService(
      store: store,
      homeFactory: StubManagedCodexHomeFactory(url: newHomeURL),
      loginRunner: loginRunner
    )

    let updated = try await service.authenticateManagedAccount(timeout: 1)

    XCTAssertEqual(updated.id, existingAccount.id)
    XCTAssertEqual(updated.accountID, "acct_same")
    XCTAssertEqual(updated.managedHomePath, newHomeURL.path)
    XCTAssertFalse(FileManager.default.fileExists(atPath: oldHomeURL.path))
    XCTAssertEqual(store.snapshot.accounts.count, 1)
  }

  private static func writeAuthJSON(
    to url: URL,
    email: String?,
    accountID: String
  ) throws {
    let payloadJSON: String
    if let email {
      payloadJSON = #"{"https://api.openai.com/profile":{"email":"\#(email)"}}"#
    } else {
      payloadJSON = #"{"sub":"user_123"}"#
    }

    let payload = Data(payloadJSON.utf8).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    let jwt = "header.\(payload).sig"

    let authJSON = """
    {
      "auth_mode": "chatgpt",
      "tokens": {
        "access_token": "\(jwt)",
        "account_id": "\(accountID)"
      }
    }
    """

    try authJSON.write(to: url, atomically: true, encoding: .utf8)
  }
}

private final class InMemoryManagedCodexAccountStore: @unchecked Sendable, ManagedCodexAccountStoring {
  var snapshot: ManagedCodexAccountSet

  init(snapshot: ManagedCodexAccountSet = ManagedCodexAccountSet(accounts: [])) {
    self.snapshot = snapshot
  }

  func loadAccounts() throws -> ManagedCodexAccountSet {
    snapshot
  }

  func storeAccounts(_ accounts: ManagedCodexAccountSet) throws {
    snapshot = accounts
  }
}

private struct StubManagedCodexHomeFactory: ManagedCodexHomeProducing {
  let url: URL

  func makeHomeURL() -> URL {
    url
  }

  func validateManagedHomeForDeletion(_ url: URL) throws {
    _ = url
  }
}

private struct StubManagedCodexLoginRunner: ManagedCodexLoginRunning {
  let runHandler: @Sendable (String, TimeInterval) throws -> CodexLoginRunner.Result

  func run(homePath: String, timeout: TimeInterval) async -> CodexLoginRunner.Result {
    do {
      return try runHandler(homePath, timeout)
    } catch {
      return .init(outcome: .launchFailed(error.localizedDescription), output: error.localizedDescription)
    }
  }
}

private func XCTAssertThrowsErrorAsync<T>(
  _ expression: @autoclosure () async throws -> T,
  _ verify: (Error) -> Void
) async {
  do {
    _ = try await expression()
    XCTFail("Expected expression to throw")
  } catch {
    verify(error)
  }
}
