import XCTest

final class HotkeyRemovalTests: XCTestCase {

  func testAppDelegateSourceDoesNotReferenceHotkeyFeature() throws {
    let testsDirectory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
    let repositoryRoot = testsDirectory
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let appDelegateURL = repositoryRoot
      .appendingPathComponent("Sources/CodexRateWatcherNative/AppDelegate.swift")

    let source = try String(contentsOf: appDelegateURL, encoding: .utf8)

    XCTAssertFalse(source.contains("hotkeyManager"))
    XCTAssertFalse(source.contains("toggleHotkey"))
    XCTAssertFalse(source.contains("快捷键"))
  }
}
