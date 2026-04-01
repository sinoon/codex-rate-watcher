import XCTest
@testable import CodexRateKit

final class CodexLoginRunnerTests: XCTestCase {

  func testRunReturnsMissingBinaryWhenResolverFails() async {
    let runner = CodexLoginRunner(
      binaryResolver: { _ in nil },
      commandRunner: { _, _, _ in
        XCTFail("Command runner should not be called when binary resolution fails")
        return .init(exitCode: 0, output: "", timedOut: false)
      }
    )

    let result = await runner.run(homePath: "/tmp/codex-home", timeout: 30)

    XCTAssertEqual(result.outcome, .missingBinary)
  }

  func testRunScopesCodexHomeIntoEnvironment() async {
    let runner = CodexLoginRunner(
      binaryResolver: { _ in "/opt/homebrew/bin/codex" },
      commandRunner: { binary, environment, arguments in
        XCTAssertEqual(binary, "/opt/homebrew/bin/codex")
        XCTAssertEqual(arguments, ["login"])
        XCTAssertEqual(environment["CODEX_HOME"], "/tmp/codex-home")
        return .init(exitCode: 0, output: "ok", timedOut: false)
      }
    )

    let result = await runner.run(homePath: "/tmp/codex-home", timeout: 30)

    XCTAssertEqual(result.outcome, .success)
    XCTAssertEqual(result.output, "ok")
  }

  func testRunReturnsTimedOutWhenCommandRunnerTimesOut() async {
    let runner = CodexLoginRunner(
      binaryResolver: { _ in "/usr/local/bin/codex" },
      commandRunner: { _, _, _ in
        .init(exitCode: 124, output: "timed out", timedOut: true)
      }
    )

    let result = await runner.run(homePath: nil, timeout: 5)

    XCTAssertEqual(result.outcome, .timedOut)
    XCTAssertEqual(result.output, "timed out")
  }

  func testRunReturnsFailureStatusForNonZeroExit() async {
    let runner = CodexLoginRunner(
      binaryResolver: { _ in "/usr/local/bin/codex" },
      commandRunner: { _, _, _ in
        .init(exitCode: 2, output: "failed", timedOut: false)
      }
    )

    let result = await runner.run(homePath: nil, timeout: 5)

    XCTAssertEqual(result.outcome, .failed(status: 2))
    XCTAssertEqual(result.output, "failed")
  }
}
