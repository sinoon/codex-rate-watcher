import XCTest
@testable import CodexRateKit

final class AppPathsTests: XCTestCase {

  func testRootDirectoryIsInAppSupport() {
    let path = AppPaths.rootDirectory.path
    XCTAssertTrue(path.contains("Application Support"), "Root directory should be in Application Support, got: \(path)")
    XCTAssertTrue(path.hasSuffix("CodexRateWatcherNative"), "Root directory should end with CodexRateWatcherNative, got: \(path)")
  }

  func testSamplesFileIsUnderRoot() {
    let samplesPath = AppPaths.samplesFile.path
    let rootPath = AppPaths.rootDirectory.path
    XCTAssertTrue(samplesPath.hasPrefix(rootPath), "Samples file should be under root directory")
    XCTAssertEqual(AppPaths.samplesFile.lastPathComponent, "samples.json")
  }

  func testProfilesDirectoryName() {
    XCTAssertEqual(AppPaths.profilesDirectory.lastPathComponent, "auth-profiles")
  }

  func testProfilesDirectoryIsUnderRoot() {
    let profilesPath = AppPaths.profilesDirectory.path
    let rootPath = AppPaths.rootDirectory.path
    XCTAssertTrue(profilesPath.hasPrefix(rootPath), "Profiles directory should be under root directory")
  }

  func testProfileIndexFileName() {
    XCTAssertEqual(AppPaths.profileIndexFile.lastPathComponent, "profiles.json")
  }

  func testProfileIndexFileIsUnderRoot() {
    let indexPath = AppPaths.profileIndexFile.path
    let rootPath = AppPaths.rootDirectory.path
    XCTAssertTrue(indexPath.hasPrefix(rootPath), "Profile index file should be under root directory")
  }

  func testBackupsDirectoryName() {
    XCTAssertEqual(AppPaths.backupsDirectory.lastPathComponent, "auth-backups")
  }

  func testBackupsDirectoryIsUnderRoot() {
    let backupsPath = AppPaths.backupsDirectory.path
    let rootPath = AppPaths.rootDirectory.path
    XCTAssertTrue(backupsPath.hasPrefix(rootPath), "Backups directory should be under root directory")
  }

  func testManagedCodexHomesDirectoryName() {
    XCTAssertEqual(AppPaths.managedCodexHomesDirectory.lastPathComponent, "managed-codex-homes")
  }

  func testManagedCodexHomesDirectoryIsUnderRoot() {
    let managedHomesPath = AppPaths.managedCodexHomesDirectory.path
    let rootPath = AppPaths.rootDirectory.path
    XCTAssertTrue(managedHomesPath.hasPrefix(rootPath), "Managed homes directory should be under root directory")
  }

  func testManagedCodexAccountsFileName() {
    XCTAssertEqual(AppPaths.managedCodexAccountsFile.lastPathComponent, "managed-codex-accounts.json")
  }

  func testManagedCodexAccountsFileIsUnderRoot() {
    let managedAccountsPath = AppPaths.managedCodexAccountsFile.path
    let rootPath = AppPaths.rootDirectory.path
    XCTAssertTrue(managedAccountsPath.hasPrefix(rootPath), "Managed accounts file should be under root directory")
  }

  func testTokenCostCacheFileName() {
    XCTAssertEqual(AppPaths.tokenCostCacheFile.lastPathComponent, "token-cost-cache.json")
  }

  func testTokenCostCacheFileIsUnderRoot() {
    let cachePath = AppPaths.tokenCostCacheFile.path
    let rootPath = AppPaths.rootDirectory.path
    XCTAssertTrue(cachePath.hasPrefix(rootPath), "Token cost cache file should be under root directory")
  }

  func testTokenCostDeviceFileName() {
    XCTAssertEqual(AppPaths.tokenCostDeviceFile.lastPathComponent, "token-cost-device.json")
  }

  func testTokenCostDeviceFileIsUnderRoot() {
    let devicePath = AppPaths.tokenCostDeviceFile.path
    let rootPath = AppPaths.rootDirectory.path
    XCTAssertTrue(devicePath.hasPrefix(rootPath), "Token cost device file should be under root directory")
  }

  func testTokenCostLedgerFileName() {
    XCTAssertEqual(AppPaths.tokenCostLocalLedgerFile.lastPathComponent, "token-cost-ledger.json")
  }

  func testTokenCostLedgerFileIsUnderRoot() {
    let ledgerPath = AppPaths.tokenCostLocalLedgerFile.path
    let rootPath = AppPaths.rootDirectory.path
    XCTAssertTrue(ledgerPath.hasPrefix(rootPath), "Token cost ledger file should be under root directory")
  }

  func testICloudDriveRootTargetsCloudDocsDirectory() {
    let path = AppPaths.iCloudDriveRootDirectory.path
    XCTAssertTrue(path.contains("Mobile Documents/com~apple~CloudDocs"), "iCloud root should point to CloudDocs, got: \(path)")
    XCTAssertTrue(path.hasSuffix("Codex Rate Watcher"), "iCloud root should end with Codex Rate Watcher, got: \(path)")
  }

  func testICloudLedgerDirectoryLivesUnderICloudRoot() {
    XCTAssertTrue(
      AppPaths.iCloudLedgerDirectory.path.hasPrefix(AppPaths.iCloudDriveRootDirectory.path),
      "iCloud ledger directory should be under the iCloud root directory"
    )
    XCTAssertEqual(AppPaths.iCloudLedgerDirectory.lastPathComponent, "token-ledgers")
  }

  func testAllPathsAreAbsolute() {
    // All paths should be absolute (start with /)
    XCTAssertTrue(AppPaths.rootDirectory.path.hasPrefix("/"))
    XCTAssertTrue(AppPaths.samplesFile.path.hasPrefix("/"))
    XCTAssertTrue(AppPaths.profilesDirectory.path.hasPrefix("/"))
    XCTAssertTrue(AppPaths.profileIndexFile.path.hasPrefix("/"))
    XCTAssertTrue(AppPaths.backupsDirectory.path.hasPrefix("/"))
    XCTAssertTrue(AppPaths.managedCodexHomesDirectory.path.hasPrefix("/"))
    XCTAssertTrue(AppPaths.managedCodexAccountsFile.path.hasPrefix("/"))
    XCTAssertTrue(AppPaths.tokenCostCacheFile.path.hasPrefix("/"))
    XCTAssertTrue(AppPaths.tokenCostDeviceFile.path.hasPrefix("/"))
    XCTAssertTrue(AppPaths.tokenCostLocalLedgerFile.path.hasPrefix("/"))
    XCTAssertTrue(AppPaths.iCloudDriveRootDirectory.path.hasPrefix("/"))
    XCTAssertTrue(AppPaths.iCloudLedgerDirectory.path.hasPrefix("/"))
  }
}
