import XCTest
@testable import CodexRateKit

final class AuthStoreTests: XCTestCase {

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

  // MARK: - Load Valid Auth

  func testLoadValidAuth() throws {
    // JWT payload: {"https://api.openai.com/profile":{"email":"test@example.com"}}
    // base64url encoded: eyJodHRwczovL2FwaS5vcGVuYWkuY29tL3Byb2ZpbGUiOnsiZW1haWwiOiJ0ZXN0QGV4YW1wbGUuY29tIn19
    let jwt = "eyJhbGciOiJSUzI1NiJ9.eyJodHRwczovL2FwaS5vcGVuYWkuY29tL3Byb2ZpbGUiOnsiZW1haWwiOiJ0ZXN0QGV4YW1wbGUuY29tIn19.fakesignature"

    let authJSON = """
    {
      "auth_mode": "browser",
      "tokens": {
        "access_token": "\(jwt)",
        "account_id": "acct_12345"
      }
    }
    """

    let fileURL = tempDir.appending(path: "auth.json")
    try authJSON.write(to: fileURL, atomically: true, encoding: .utf8)

    let store = AuthStore(fileURL: fileURL)
    let snapshot = try store.load()

    XCTAssertFalse(snapshot.accessToken.isEmpty)
    XCTAssertEqual(snapshot.accessToken, jwt)
    XCTAssertEqual(snapshot.accountID, "acct_12345")
    XCTAssertEqual(snapshot.authMode, "browser")
    XCTAssertEqual(snapshot.email, "test@example.com")
  }

  // MARK: - Email extraction from JWT

  func testJWTEmailExtraction() throws {
    // Another JWT with different email
    // Payload: {"https://api.openai.com/profile":{"email":"user@company.org"}}
    // base64url: eyJodHRwczovL2FwaS5vcGVuYWkuY29tL3Byb2ZpbGUiOnsiZW1haWwiOiJ1c2VyQGNvbXBhbnkub3JnIn19
    let jwt = "eyJhbGciOiJSUzI1NiJ9.eyJodHRwczovL2FwaS5vcGVuYWkuY29tL3Byb2ZpbGUiOnsiZW1haWwiOiJ1c2VyQGNvbXBhbnkub3JnIn19.sig"

    let authJSON = """
    {
      "auth_mode": "browser",
      "tokens": {
        "access_token": "\(jwt)",
        "account_id": "acct_99999"
      }
    }
    """

    let fileURL = tempDir.appending(path: "auth.json")
    try authJSON.write(to: fileURL, atomically: true, encoding: .utf8)

    let store = AuthStore(fileURL: fileURL)
    let snapshot = try store.load()
    XCTAssertEqual(snapshot.email, "user@company.org")
  }

  // MARK: - JWT without email

  func testJWTWithoutEmail() throws {
    // Payload: {"sub":"user123"} — no profile/email claim
    // base64url: eyJzdWIiOiJ1c2VyMTIzIn0
    let jwt = "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ1c2VyMTIzIn0.sig"

    let authJSON = """
    {
      "auth_mode": "api_key",
      "tokens": {
        "access_token": "\(jwt)",
        "account_id": "acct_555"
      }
    }
    """

    let fileURL = tempDir.appending(path: "auth.json")
    try authJSON.write(to: fileURL, atomically: true, encoding: .utf8)

    let store = AuthStore(fileURL: fileURL)
    let snapshot = try store.load()
    XCTAssertNil(snapshot.email)
    XCTAssertEqual(snapshot.authMode, "api_key")
  }

  // MARK: - Missing Token

  func testLoadMissingToken() throws {
    let authJSON = """
    {
      "auth_mode": "browser",
      "tokens": {
        "access_token": "",
        "account_id": "acct_12345"
      }
    }
    """

    let fileURL = tempDir.appending(path: "auth.json")
    try authJSON.write(to: fileURL, atomically: true, encoding: .utf8)

    let store = AuthStore(fileURL: fileURL)
    XCTAssertThrowsError(try store.load()) { error in
      XCTAssertTrue(error is AuthStoreError)
      if let authError = error as? AuthStoreError {
        switch authError {
        case .missingToken:
          break  // expected
        default:
          XCTFail("Expected missingToken, got \(authError)")
        }
      }
    }
  }

  func testLoadMissingTokenNull() throws {
    let authJSON = """
    {
      "auth_mode": "browser",
      "tokens": {
        "account_id": "acct_12345"
      }
    }
    """

    let fileURL = tempDir.appending(path: "auth.json")
    try authJSON.write(to: fileURL, atomically: true, encoding: .utf8)

    let store = AuthStore(fileURL: fileURL)
    XCTAssertThrowsError(try store.load()) { error in
      XCTAssertTrue(error is AuthStoreError)
    }
  }

  // MARK: - Invalid / Non-existent File

  func testLoadNonExistentFile() {
    let store = AuthStore(fileURL: tempDir.appending(path: "nonexistent.json"))
    XCTAssertThrowsError(try store.load())
  }

  func testLoadInvalidJSON() throws {
    let fileURL = tempDir.appending(path: "auth.json")
    try "not json at all".write(to: fileURL, atomically: true, encoding: .utf8)

    let store = AuthStore(fileURL: fileURL)
    XCTAssertThrowsError(try store.load())
  }

  // MARK: - Envelope & Fingerprint

  func testEnvelopeFingerprint() throws {
    let jwt = "eyJhbGciOiJSUzI1NiJ9.eyJodHRwczovL2FwaS5vcGVuYWkuY29tL3Byb2ZpbGUiOnsiZW1haWwiOiJ0ZXN0QGV4YW1wbGUuY29tIn19.fakesignature"

    let authJSON = """
    {
      "auth_mode": "browser",
      "tokens": {
        "access_token": "\(jwt)",
        "account_id": "acct_12345"
      }
    }
    """

    let fileURL = tempDir.appending(path: "auth.json")
    try authJSON.write(to: fileURL, atomically: true, encoding: .utf8)

    let store = AuthStore(fileURL: fileURL)
    let envelope = try store.loadEnvelope()

    // Fingerprint should be non-empty hex string
    XCTAssertFalse(envelope.fingerprint.isEmpty)
    XCTAssertEqual(envelope.fingerprint.count, 64)  // SHA256 = 32 bytes = 64 hex chars

    // Same data should produce the same fingerprint
    let envelope2 = try store.loadEnvelope()
    XCTAssertEqual(envelope.fingerprint, envelope2.fingerprint)
  }

  func testDifferentDataDifferentFingerprint() throws {
    let jwt1 = "eyJhbGciOiJSUzI1NiJ9.eyJodHRwczovL2FwaS5vcGVuYWkuY29tL3Byb2ZpbGUiOnsiZW1haWwiOiJ0ZXN0QGV4YW1wbGUuY29tIn19.fakesignature"
    let jwt2 = "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ1c2VyMTIzIn0.sig"

    let authJSON1 = """
    {"auth_mode":"browser","tokens":{"access_token":"\(jwt1)","account_id":"acct_1"}}
    """
    let authJSON2 = """
    {"auth_mode":"browser","tokens":{"access_token":"\(jwt2)","account_id":"acct_2"}}
    """

    let file1 = tempDir.appending(path: "auth1.json")
    let file2 = tempDir.appending(path: "auth2.json")
    try authJSON1.write(to: file1, atomically: true, encoding: .utf8)
    try authJSON2.write(to: file2, atomically: true, encoding: .utf8)

    let store1 = AuthStore(fileURL: file1)
    let store2 = AuthStore(fileURL: file2)

    let envelope1 = try store1.loadEnvelope()
    let envelope2 = try store2.loadEnvelope()

    XCTAssertNotEqual(envelope1.fingerprint, envelope2.fingerprint)
  }

  // MARK: - Write Raw Data

  func testWriteRawData() throws {
    let fileURL = tempDir.appending(path: "auth.json")
    let store = AuthStore(fileURL: fileURL)

    let jwt = "eyJhbGciOiJSUzI1NiJ9.eyJodHRwczovL2FwaS5vcGVuYWkuY29tL3Byb2ZpbGUiOnsiZW1haWwiOiJ0ZXN0QGV4YW1wbGUuY29tIn19.fakesignature"
    let authJSON = """
    {"auth_mode":"browser","tokens":{"access_token":"\(jwt)","account_id":"acct_12345"}}
    """
    let data = authJSON.data(using: .utf8)!

    try store.writeRawData(data)

    // Read it back
    let readBack = try Data(contentsOf: fileURL)
    XCTAssertEqual(readBack, data)

    // Also verify we can load it
    let snapshot = try store.load()
    XCTAssertEqual(snapshot.accountID, "acct_12345")
  }

  // MARK: - Watched Directory

  func testWatchedDirectoryURL() {
    let fileURL = tempDir.appending(path: "auth.json")
    let store = AuthStore(fileURL: fileURL)
    XCTAssertEqual(store.watchedDirectoryURL.standardizedFileURL, tempDir.standardizedFileURL)
  }

  // MARK: - Envelope from Data

  func testEnvelopeFromData() throws {
    let jwt = "eyJhbGciOiJSUzI1NiJ9.eyJodHRwczovL2FwaS5vcGVuYWkuY29tL3Byb2ZpbGUiOnsiZW1haWwiOiJ0ZXN0QGV4YW1wbGUuY29tIn19.fakesignature"
    let authJSON = """
    {"auth_mode":"browser","tokens":{"access_token":"\(jwt)","account_id":"acct_12345"}}
    """
    let data = authJSON.data(using: .utf8)!

    let fileURL = tempDir.appending(path: "auth.json")
    let store = AuthStore(fileURL: fileURL)
    let envelope = try store.envelope(from: data)

    XCTAssertEqual(envelope.snapshot.accessToken, jwt)
    XCTAssertEqual(envelope.snapshot.accountID, "acct_12345")
    XCTAssertEqual(envelope.snapshot.email, "test@example.com")
    XCTAssertEqual(envelope.rawData, data)
    XCTAssertFalse(envelope.fingerprint.isEmpty)
  }

  // MARK: - AuthStoreError descriptions

  func testAuthStoreErrorDescriptions() {
    let missingTokenError = AuthStoreError.missingToken
    XCTAssertNotNil(missingTokenError.errorDescription)
    XCTAssertTrue(missingTokenError.errorDescription!.contains("access token"))

    let invalidJWTError = AuthStoreError.invalidJWT
    XCTAssertNotNil(invalidJWTError.errorDescription)
    XCTAssertTrue(invalidJWTError.errorDescription!.contains("token"))
  }
}
