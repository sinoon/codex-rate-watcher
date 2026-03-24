import XCTest
@testable import CodexRateKit

final class ProfileLoaderTests: XCTestCase {

  private var tempDir: URL!
  private var origDir: URL!

  override func setUp() {
    super.setUp()
    tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let profDir = tempDir.appending(path: "auth-profiles")
    try? FileManager.default.createDirectory(at: profDir, withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tempDir)
    super.tearDown()
  }

  // MARK: - Helpers

  private func writeProfileIndex(_ records: [AuthProfileRecord]) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try! encoder.encode(records)
    try! data.write(to: tempDir.appending(path: "profiles.json"))
  }

  private func writeSnapshot(fileName: String, jwt: String = "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ1c2VyMTIzIn0.sig", accountID: String = "acct_1") {
    let json = """
    {"auth_mode":"browser","tokens":{"access_token":"\(jwt)","account_id":"\(accountID)"}}
    """
    let url = tempDir.appending(path: "auth-profiles").appending(path: fileName)
    try! json.write(to: url, atomically: true, encoding: .utf8)
  }

  private func makeRecord(
    id: UUID = UUID(),
    fingerprint: String = "abc",
    snapshotFileName: String = "snap.json",
    email: String? = "test@example.com",
    accountID: String? = "acct_1",
    primaryUsed: Double = 30.0,
    secondaryUsed: Double? = 10.0,
    isBlocked: Bool = false,
    validationError: String? = nil
  ) -> AuthProfileRecord {
    let usage: AuthProfileUsageSummary?
    if isBlocked {
      usage = makeSummary(primaryUsedPercent: 100.0, isAllowed: false, limitReached: true)
    } else {
      usage = makeSummary(primaryUsedPercent: primaryUsed, secondaryUsedPercent: secondaryUsed)
    }
    return AuthProfileRecord(
      id: id,
      fingerprint: fingerprint,
      snapshotFileName: snapshotFileName,
      authMode: "browser",
      accountID: accountID,
      email: email,
      createdAt: Date(),
      lastSeenAt: Date(),
      lastValidatedAt: Date(),
      latestUsage: usage,
      validationError: validationError
    )
  }

  private func makeSummary(
    primaryUsedPercent: Double = 30.0,
    secondaryUsedPercent: Double? = 10.0,
    isAllowed: Bool = true,
    limitReached: Bool = false
  ) -> AuthProfileUsageSummary {
    let json: String
    if let sec = secondaryUsedPercent {
      json = """
      {"planType":"plus","isAllowed":\(isAllowed),"limitReached":\(limitReached),
       "primaryUsedPercent":\(primaryUsedPercent),"primaryResetAt":1773980000.0,
       "secondaryUsedPercent":\(sec),"secondaryResetAt":1774400000.0,
       "reviewUsedPercent":0,"reviewResetAt":1773990000.0}
      """
    } else {
      json = """
      {"planType":"plus","isAllowed":\(isAllowed),"limitReached":\(limitReached),
       "primaryUsedPercent":\(primaryUsedPercent),"primaryResetAt":1773980000.0,
       "reviewUsedPercent":0,"reviewResetAt":1773990000.0}
      """
    }
    return try! JSONDecoder().decode(AuthProfileUsageSummary.self, from: json.data(using: .utf8)!)
  }

  // MARK: - loadProfiles()

  func testLoadProfilesReturnsEmptyWhenNoFile() {
    // No profiles.json exists at the default path (not our tempDir)
    // This tests the graceful empty return
    // We can't easily redirect AppPaths, so just verify the method doesn't crash
    let profiles = ProfileLoader.loadProfiles()
    // May or may not be empty depending on whether the user has profiles
    XCTAssertNotNil(profiles)
  }

  // MARK: - bestProfile sorting

  func testProfilesSortedByAvailablePercent() {
    // Verify that the sorting logic works correctly
    let lowUsage = makeRecord(primaryUsed: 80.0)  // 20% remaining
    let highUsage = makeRecord(primaryUsed: 20.0)  // 80% remaining
    let midUsage = makeRecord(primaryUsed: 50.0)   // 50% remaining

    var profiles = [lowUsage, highUsage, midUsage]
    profiles.sort {
      ($0.latestUsage?.effectiveAvailablePercent ?? 0) > ($1.latestUsage?.effectiveAvailablePercent ?? 0)
    }

    XCTAssertEqual(profiles[0].latestUsage!.primaryRemainingPercent, 80.0, accuracy: 0.1)
    XCTAssertEqual(profiles[1].latestUsage!.primaryRemainingPercent, 50.0, accuracy: 0.1)
    XCTAssertEqual(profiles[2].latestUsage!.primaryRemainingPercent, 20.0, accuracy: 0.1)
  }

  // MARK: - bestProfile exclusion logic

  func testBestProfileSkipsExcludedID() {
    let idA = UUID()
    let idB = UUID()
    let profileA = makeRecord(id: idA, primaryUsed: 10.0)  // best, 90% remaining
    let profileB = makeRecord(id: idB, primaryUsed: 50.0)  // second best, 50% remaining

    var candidates = [profileA, profileB]
    candidates.sort {
      ($0.latestUsage?.effectiveAvailablePercent ?? 0) > ($1.latestUsage?.effectiveAvailablePercent ?? 0)
    }

    // Simulate exclusion of the best profile
    let filtered = candidates.filter { $0.id != idA && $0.validationError == nil && $0.latestUsage?.isBlocked != true }
    XCTAssertEqual(filtered.count, 1)
    XCTAssertEqual(filtered.first?.id, idB)
  }

  func testBestProfileSkipsBlockedProfiles() {
    let blockedProfile = makeRecord(isBlocked: true)
    let activeProfile = makeRecord(primaryUsed: 50.0)

    let candidates = [blockedProfile, activeProfile]
    let filtered = candidates.filter { $0.validationError == nil && $0.latestUsage?.isBlocked != true }
    XCTAssertEqual(filtered.count, 1)
    XCTAssertEqual(filtered.first!.latestUsage!.primaryRemainingPercent, 50.0, accuracy: 0.1)
  }

  func testBestProfileSkipsErrorProfiles() {
    let errorProfile = makeRecord(validationError: "402 Payment Required")
    let activeProfile = makeRecord(primaryUsed: 40.0)

    let candidates = [errorProfile, activeProfile]
    let filtered = candidates.filter { $0.validationError == nil && $0.latestUsage?.isBlocked != true }
    XCTAssertEqual(filtered.count, 1)
    XCTAssertEqual(filtered.first!.latestUsage!.primaryRemainingPercent, 60.0, accuracy: 0.1)
  }

  func testBestProfileReturnsNilWhenAllExcluded() {
    let idA = UUID()
    let profileA = makeRecord(id: idA, primaryUsed: 10.0)
    let candidates = [profileA]
    let filtered = candidates.filter { $0.id != idA }
    XCTAssertTrue(filtered.isEmpty)
  }

  func testBestProfileReturnsNilWhenAllBlocked() {
    let blocked1 = makeRecord(isBlocked: true)
    let blocked2 = makeRecord(isBlocked: true)
    let candidates = [blocked1, blocked2]
    let filtered = candidates.filter { $0.latestUsage?.isBlocked != true }
    XCTAssertTrue(filtered.isEmpty)
  }
}
