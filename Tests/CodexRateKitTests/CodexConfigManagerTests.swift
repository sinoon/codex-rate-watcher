import XCTest
@testable import CodexRateKit

final class CodexConfigManagerTests: XCTestCase {

  // MARK: - Helpers

  private var tmpDir: URL!

  override func setUp() {
    super.setUp()
    tmpDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("CodexConfigManagerTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tmpDir)
    super.tearDown()
  }

  private func configPath(_ name: String = "config.toml") -> String {
    tmpDir.appendingPathComponent(name).path
  }

  private func write(_ content: String, to name: String = "config.toml") {
    FileManager.default.createFile(
      atPath: configPath(name),
      contents: content.data(using: .utf8)
    )
  }

  private func read(_ name: String = "config.toml") -> String {
    (try? String(contentsOfFile: configPath(name), encoding: .utf8)) ?? ""
  }

  // Minimal Codex-style config for testing
  private let sampleConfig = """
    model = "gpt-5.4"
    model_reasoning_effort = "xhigh"
    # model_provider = "webinfra_model"

    [model_providers.webinfra_model]
    name = "GPT-5.4"
    base_url = "https://ai-coder.bytedance.net/responses/codex-bridge-gpt-5.4"
    wire_api = "responses"

    [projects."/Users/test/project"]
    trust_level = "trusted"

    [notice]
    hide_full_access_warning = true
    """

  // MARK: - Tests: currentMode

  func testCurrentModeDefaultsDirect() {
    write(sampleConfig)
    let mgr = CodexConfigManager(configPath: configPath())
    XCTAssertEqual(mgr.currentMode(), .direct)
  }

  func testCurrentModeDetectsProxy() {
    let config = """
      model = "gpt-5.4"
      model_provider = "rate_watcher"

      [model_providers.rate_watcher]
      name = "Rate Watcher Proxy"
      base_url = "http://localhost:19876"
      wire_api = "responses"
      """
    write(config)
    let mgr = CodexConfigManager(configPath: configPath())
    XCTAssertEqual(mgr.currentMode(), .proxy)
  }

  func testCurrentModeDirectWhenCommented() {
    let config = """
      model = "gpt-5.4"
      # model_provider = "rate_watcher"
      """
    write(config)
    let mgr = CodexConfigManager(configPath: configPath())
    XCTAssertEqual(mgr.currentMode(), .direct)
  }

  func testCurrentModeDirectWhenNoFile() {
    let mgr = CodexConfigManager(configPath: "/nonexistent/path/config.toml")
    XCTAssertEqual(mgr.currentMode(), .direct)
  }

  // MARK: - Tests: detectMode (static)

  func testDetectModeStatic() {
    XCTAssertEqual(
      CodexConfigManager.detectMode(in: "model_provider = \"rate_watcher\""),
      .proxy
    )
    XCTAssertEqual(
      CodexConfigManager.detectMode(in: "# model_provider = \"rate_watcher\""),
      .direct
    )
    XCTAssertEqual(
      CodexConfigManager.detectMode(in: "model_provider = \"openai\""),
      .direct
    )
  }

  // MARK: - Tests: switchToProxy

  func testSwitchToProxyAddsProviderLine() throws {
    write(sampleConfig)
    let mgr = CodexConfigManager(configPath: configPath())

    try mgr.switchTo(proxy: 19876)

    let result = read()
    XCTAssertTrue(result.contains("model_provider = \"rate_watcher\""))
    XCTAssertTrue(result.contains("[model_providers.rate_watcher]"))
    XCTAssertTrue(result.contains("http://localhost:19876"))
    XCTAssertEqual(mgr.currentMode(), .proxy)
  }

  func testSwitchToProxyCommentsOutExisting() throws {
    let config = """
      model = "gpt-5.4"
      model_provider = "webinfra_model"

      [model_providers.webinfra_model]
      name = "GPT-5.4"
      """
    write(config)
    let mgr = CodexConfigManager(configPath: configPath())

    try mgr.switchTo(proxy: 19876)

    let result = read()
    // webinfra_model provider line should be commented
    let lines = result.components(separatedBy: "\n")
    let webinfraLine = lines.first { $0.contains("webinfra_model") && $0.contains("model_provider") }
    XCTAssertNotNil(webinfraLine)
    XCTAssertTrue(webinfraLine!.trimmingCharacters(in: .whitespaces).hasPrefix("#"))
    // rate_watcher should be active
    XCTAssertTrue(result.contains("model_provider = \"rate_watcher\""))
  }

  func testSwitchToProxyCustomPort() throws {
    write(sampleConfig)
    let mgr = CodexConfigManager(configPath: configPath())

    try mgr.switchTo(proxy: 8080)

    let result = read()
    XCTAssertTrue(result.contains("http://localhost:8080"))
  }

  func testSwitchToProxyUncommentsExisting() throws {
    let config = """
      model = "gpt-5.4"
      # model_provider = "rate_watcher"

      [model_providers.rate_watcher]
      name = "Rate Watcher Proxy"
      base_url = "http://localhost:19876"
      wire_api = "responses"
      """
    write(config)
    let mgr = CodexConfigManager(configPath: configPath())

    try mgr.switchTo(proxy: 19876)

    let result = read()
    let lines = result.components(separatedBy: "\n")
    let providerLine = lines.first {
      $0.contains("model_provider") && $0.contains("rate_watcher") && !$0.contains("[")
    }
    XCTAssertNotNil(providerLine)
    XCTAssertFalse(providerLine!.trimmingCharacters(in: .whitespaces).hasPrefix("#"))
  }

  func testSwitchToProxyCreatesBackup() throws {
    write(sampleConfig)
    let mgr = CodexConfigManager(configPath: configPath())

    try mgr.switchTo(proxy: 19876)

    let files = try FileManager.default.contentsOfDirectory(atPath: tmpDir.path)
    let backups = files.filter { $0.contains(".rw-backup.") }
    XCTAssertEqual(backups.count, 1)
  }

  // MARK: - Tests: switchToDirect

  func testSwitchToDirectCommentsOutProvider() throws {
    let config = """
      model = "gpt-5.4"
      model_provider = "rate_watcher"

      [model_providers.rate_watcher]
      name = "Rate Watcher Proxy"
      base_url = "http://localhost:19876"
      wire_api = "responses"
      """
    write(config)
    let mgr = CodexConfigManager(configPath: configPath())

    try mgr.switchToDirect()

    let result = read()
    let lines = result.components(separatedBy: "\n")
    let providerLine = lines.first {
      $0.contains("model_provider") && $0.contains("rate_watcher") && !$0.contains("[")
    }
    XCTAssertNotNil(providerLine)
    XCTAssertTrue(providerLine!.trimmingCharacters(in: .whitespaces).hasPrefix("#"))
    XCTAssertEqual(mgr.currentMode(), .direct)
  }

  func testSwitchToDirectPreservesSection() throws {
    let config = """
      model = "gpt-5.4"
      model_provider = "rate_watcher"

      [model_providers.rate_watcher]
      name = "Rate Watcher Proxy"
      base_url = "http://localhost:19876"
      wire_api = "responses"
      """
    write(config)
    let mgr = CodexConfigManager(configPath: configPath())

    try mgr.switchToDirect()

    let result = read()
    // Section should still be there (just provider line commented)
    XCTAssertTrue(result.contains("[model_providers.rate_watcher]"))
    XCTAssertTrue(result.contains("http://localhost:19876"))
  }

  // MARK: - Tests: round-trip

  func testRoundTripDirectProxyDirect() throws {
    write(sampleConfig)
    let mgr = CodexConfigManager(configPath: configPath())

    XCTAssertEqual(mgr.currentMode(), .direct)
    try mgr.switchTo(proxy: 19876)
    XCTAssertEqual(mgr.currentMode(), .proxy)
    try mgr.switchToDirect()
    XCTAssertEqual(mgr.currentMode(), .direct)
    // Switch again
    try mgr.switchTo(proxy: 19876)
    XCTAssertEqual(mgr.currentMode(), .proxy)
  }

  // MARK: - Tests: errors

  func testSwitchToProxyThrowsWhenNoFile() {
    let mgr = CodexConfigManager(configPath: "/nonexistent/config.toml")
    XCTAssertThrowsError(try mgr.switchTo(proxy: 19876)) { error in
      XCTAssertTrue(error.localizedDescription.contains("not found"))
    }
  }

  func testSwitchToDirectThrowsWhenNoFile() {
    let mgr = CodexConfigManager(configPath: "/nonexistent/config.toml")
    XCTAssertThrowsError(try mgr.switchToDirect()) { error in
      XCTAssertTrue(error.localizedDescription.contains("not found"))
    }
  }

  // MARK: - Tests: Mode description

  func testModeDescription() {
    XCTAssertEqual(CodexConfigManager.Mode.proxy.description, "proxy")
    XCTAssertEqual(CodexConfigManager.Mode.direct.description, "direct")
    XCTAssertEqual(CodexConfigManager.Mode.proxy.rawValue, "proxy")
  }
}
