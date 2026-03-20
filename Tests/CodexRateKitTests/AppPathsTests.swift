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

  func testAllPathsAreAbsolute() {
    // All paths should be absolute (start with /)
    XCTAssertTrue(AppPaths.rootDirectory.path.hasPrefix("/"))
    XCTAssertTrue(AppPaths.samplesFile.path.hasPrefix("/"))
    XCTAssertTrue(AppPaths.profilesDirectory.path.hasPrefix("/"))
    XCTAssertTrue(AppPaths.profileIndexFile.path.hasPrefix("/"))
    XCTAssertTrue(AppPaths.backupsDirectory.path.hasPrefix("/"))
  }
}
