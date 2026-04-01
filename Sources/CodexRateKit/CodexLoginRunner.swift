import Foundation

public struct CodexLoginRunner: Sendable {
  public struct CommandResult: Sendable {
    public let exitCode: Int32
    public let output: String
    public let timedOut: Bool
    public let launchError: String?

    public init(exitCode: Int32, output: String, timedOut: Bool, launchError: String? = nil) {
      self.exitCode = exitCode
      self.output = output
      self.timedOut = timedOut
      self.launchError = launchError
    }
  }

  public struct Result: Sendable {
    public enum Outcome: Equatable, Sendable {
      case success
      case timedOut
      case failed(status: Int32)
      case missingBinary
      case launchFailed(String)
    }

    public let outcome: Outcome
    public let output: String

    public init(outcome: Outcome, output: String) {
      self.outcome = outcome
      self.output = output
    }
  }

  public typealias BinaryResolver = @Sendable ([String: String]) -> String?
  public typealias CommandRunner = @Sendable (String, [String: String], [String]) async -> CommandResult

  private let baseEnvironment: [String: String]
  private let binaryResolver: BinaryResolver
  private let commandRunner: CommandRunner

  public init(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    binaryResolver: @escaping BinaryResolver = Self.resolveCodexBinary,
    commandRunner: @escaping CommandRunner = Self.runCommand
  ) {
    self.baseEnvironment = environment
    self.binaryResolver = binaryResolver
    self.commandRunner = commandRunner
  }

  public func run(homePath: String?, timeout: TimeInterval) async -> Result {
    var environment = baseEnvironment
    if let homePath, !homePath.isEmpty {
      environment["CODEX_HOME"] = homePath
    }
    environment["CODEX_LOGIN_TIMEOUT_SECONDS"] = String(Int(timeout.rounded()))

    guard let binary = binaryResolver(environment) else {
      return Result(outcome: .missingBinary, output: "")
    }

    let commandResult = await commandRunner(binary, environment, ["login"])
    if let launchError = commandResult.launchError {
      return Result(outcome: .launchFailed(launchError), output: commandResult.output)
    }
    if commandResult.timedOut {
      return Result(outcome: .timedOut, output: commandResult.output)
    }
    if commandResult.exitCode == 0 {
      return Result(outcome: .success, output: commandResult.output)
    }
    return Result(outcome: .failed(status: commandResult.exitCode), output: commandResult.output)
  }

  public static func resolveCodexBinary(environment: [String: String]) -> String? {
    let fileManager = FileManager.default

    if let override = environment["CODEX_CLI_PATH"],
       !override.isEmpty,
       fileManager.isExecutableFile(atPath: override) {
      return override
    }

    let pathEntries = (environment["PATH"] ?? "")
      .split(separator: ":")
      .map(String.init)

    for entry in pathEntries where !entry.isEmpty {
      let candidate = URL(fileURLWithPath: entry, isDirectory: true)
        .appending(path: "codex")
        .path
      if fileManager.isExecutableFile(atPath: candidate) {
        return candidate
      }
    }

    for fallback in ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/usr/bin/codex"] {
      if fileManager.isExecutableFile(atPath: fallback) {
        return fallback
      }
    }

    return nil
  }

  public static func runCommand(
    binary: String,
    environment: [String: String],
    arguments: [String]
  ) async -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = arguments
    process.environment = environment

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    do {
      try process.run()
    } catch {
      return CommandResult(
        exitCode: -1,
        output: error.localizedDescription,
        timedOut: false,
        launchError: error.localizedDescription
      )
    }

    let timeoutSeconds = TimeInterval(environment["CODEX_LOGIN_TIMEOUT_SECONDS"] ?? "") ?? 120
    let timedOut = await wait(for: process, timeout: timeoutSeconds)
    if timedOut {
      process.terminate()
    }

    let output = await combinedOutput(stdout: stdout, stderr: stderr)
    if timedOut {
      return CommandResult(exitCode: process.terminationStatus, output: output, timedOut: true)
    }

    return CommandResult(exitCode: process.terminationStatus, output: output, timedOut: false)
  }

  private static func wait(for process: Process, timeout: TimeInterval) async -> Bool {
    await withTaskGroup(of: Bool.self) { group -> Bool in
      group.addTask {
        process.waitUntilExit()
        return false
      }
      group.addTask {
        try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
        return true
      }
      let result = await group.next() ?? false
      group.cancelAll()
      return result
    }
  }

  private static func combinedOutput(stdout: Pipe, stderr: Pipe) async -> String {
    async let out = readToEnd(stdout.fileHandleForReading)
    async let err = readToEnd(stderr.fileHandleForReading)
    let output = ([await out, await err])
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return output
  }

  private static func readToEnd(_ handle: FileHandle) async -> String {
    if #available(macOS 10.15.4, *) {
      if let data = try? handle.readToEnd() {
        return String(data: data, encoding: .utf8) ?? ""
      }
    }
    let data = handle.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
  }
}
