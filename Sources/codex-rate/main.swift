import CodexRateKit
import Foundation

// MARK: - ANSI Escape Helpers

private enum ANSI {
  static let reset   = "\u{1B}[0m"
  static let bold    = "\u{1B}[1m"
  static let dim     = "\u{1B}[2m"
  static let red     = "\u{1B}[31m"
  static let green   = "\u{1B}[32m"
  static let yellow  = "\u{1B}[33m"
  static let blue    = "\u{1B}[34m"
  static let magenta = "\u{1B}[35m"
  static let cyan    = "\u{1B}[36m"
  static let white   = "\u{1B}[37m"
  static let bgRed   = "\u{1B}[41m"
  static let bgGreen = "\u{1B}[42m"
  static let bgYellow = "\u{1B}[43m"

  static func color(forPercent remaining: Double) -> String {
    if remaining > 50 { return green }
    if remaining > 15 { return yellow }
    return red
  }

  static let isColorEnabled: Bool = {
    if ProcessInfo.processInfo.environment["NO_COLOR"] != nil { return false }
    return isatty(STDOUT_FILENO) != 0
  }()

  static func c(_ code: String, _ text: String) -> String {
    isColorEnabled ? "\(code)\(text)\(reset)" : text
  }
}

// MARK: - Progress Bar

private enum ProgressBar {
  static func render(remainingPercent: Double, width: Int = 20) -> String {
    let clamped = max(0, min(100, remainingPercent))
    let filled = Int((clamped / 100.0) * Double(width))
    let empty = width - filled
    let bar = String(repeating: "\u{2588}", count: filled) + String(repeating: "\u{2591}", count: empty)
    let color = ANSI.color(forPercent: clamped)
    return ANSI.c(color, bar)
  }
}

// MARK: - Sparkline

private enum Sparkline {
  static let blocks: [Character] = ["\u{2581}", "\u{2582}", "\u{2583}", "\u{2584}", "\u{2585}", "\u{2586}", "\u{2587}", "\u{2588}"]

  static func render(values: [Double]) -> String {
    guard !values.isEmpty else { return "" }
    let lo = values.min()!
    let hi = values.max()!
    let range = hi - lo
    return String(values.map { v in
      if range < 0.001 { return blocks[3] }
      let idx = Int(((v - lo) / range) * Double(blocks.count - 1))
      return blocks[min(idx, blocks.count - 1)]
    })
  }
}

// MARK: - Time Formatting

private func formatDuration(seconds: Int) -> String {
  if seconds <= 0 { return "now" }
  let h = seconds / 3600
  let m = (seconds % 3600) / 60
  if h > 24 {
    let d = h / 24
    let rh = h % 24
    return "\(d)d \(rh)h"
  }
  if h > 0 { return "\(h)h \(m)m" }
  if m > 0 { return "\(m)m" }
  return "\(seconds)s"
}

private func formatResetTimestamp(resetAt: TimeInterval) -> String {
  let date = Date(timeIntervalSince1970: resetAt)
  let now = Date()
  guard date > now else { return "now" }

  let diff = Int(date.timeIntervalSince(now))
  let calendar = Calendar.current
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")

  if calendar.isDateInToday(date) {
    formatter.dateFormat = "HH:mm"
    return "today \(formatter.string(from: date)) (\(formatDuration(seconds: diff)))"
  } else if calendar.isDateInTomorrow(date) {
    formatter.dateFormat = "HH:mm"
    return "tomorrow \(formatter.string(from: date)) (\(formatDuration(seconds: diff)))"
  } else {
    formatter.dateFormat = "EEE HH:mm"
    return "\(formatter.string(from: date)) (\(formatDuration(seconds: diff)))"
  }
}

// MARK: - Box Drawing

private enum Box {
  static let W = 48

  static func topBorder() -> String    { "\u{2554}" + String(repeating: "\u{2550}", count: W) + "\u{2557}" }
  static func midBorder() -> String    { "\u{2560}" + String(repeating: "\u{2550}", count: W) + "\u{2563}" }
  static func bottomBorder() -> String { "\u{255A}" + String(repeating: "\u{2550}", count: W) + "\u{255D}" }

  static func row(_ content: String) -> String {
    let visible = stripANSI(content)
    let pad = max(0, W - visible.count)
    return "\u{2551} \(content)\(String(repeating: " ", count: pad - 1))\u{2551}"
  }

  static func centeredRow(_ content: String) -> String {
    let visible = stripANSI(content)
    let total = max(0, W - visible.count)
    let left = total / 2
    let right = total - left
    return "\u{2551}\(String(repeating: " ", count: left))\(content)\(String(repeating: " ", count: right))\u{2551}"
  }
}

private func stripANSI(_ s: String) -> String {
  s.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
}

// MARK: - JSON Output Helpers

private func windowToDict(_ w: LimitWindow) -> [String: Any] {
  [
    "used_percent": w.usedPercent,
    "remaining_percent": w.remainingPercent,
    "limit_window_seconds": w.limitWindowSeconds,
    "reset_after_seconds": w.resetAfterSeconds,
    "reset_at": w.resetAt
  ]
}

private func limitToDict(_ l: UsageLimit) -> [String: Any] {
  var d: [String: Any] = [
    "allowed": l.allowed,
    "limit_reached": l.limitReached,
    "primary_window": windowToDict(l.primaryWindow)
  ]
  if let sw = l.secondaryWindow {
    d["secondary_window"] = windowToDict(sw)
  }
  return d
}

private func snapshotToDict(_ s: UsageSnapshot, auth: AuthSnapshot) -> [String: Any] {
  var d: [String: Any] = [
    "plan_type": s.planType,
    "rate_limit": limitToDict(s.rateLimit),
    "code_review_rate_limit": limitToDict(s.codeReviewRateLimit),
    "credits": [
      "has_credits": s.credits.hasCredits,
      "unlimited": s.credits.unlimited
    ] as [String: Any],
    "fetched_at": ISO8601DateFormatter().string(from: Date())
  ]
  if let email = auth.email { d["email"] = email }
  if let accountID = auth.accountID { d["account_id"] = accountID }
  if let authMode = auth.authMode { d["auth_mode"] = authMode }
  return d
}

// MARK: - Error Handling

private func exitWithError(_ message: String) -> Never {
  fputs(ANSI.c(ANSI.red, "\u{2717} Error: \(message)") + "\n", stderr)
  exit(1)
}

// MARK: - Argument Parsing

private struct CLIOptions {
  enum Command {
    case status
    case profiles
    case watch
    case history
    case relay
    case cost
    case proxy
    case mode
    case help
  }
  var command: Command = .status
  var jsonOutput: Bool = false
  var relayStrategy: String = "reset-aware"
  var watchInterval: Int = 30
  var historyHours: Int = 24
  var proxyPort: UInt16 = 19876
  var proxyUpstream: String = "https://api.openai.com"
  var noAutoRelay: Bool = false
  var proxyVerbose: Bool = false
  var modeTarget: String = ""
}

private func parseArguments() -> CLIOptions {
  var opts = CLIOptions()
  let args = Array(CommandLine.arguments.dropFirst())

  guard !args.isEmpty else { return opts }

  var idx = 0

  // First non-flag argument is the subcommand
  let first = args[0]
  switch first {
  case "status":
    opts.command = .status; idx = 1
  case "profiles":
    opts.command = .profiles; idx = 1
  case "watch":
    opts.command = .watch; idx = 1
  case "history":
    opts.command = .history; idx = 1
  case "cost":
    opts.command = .cost; idx = 1
  case "proxy":
    opts.command = .proxy; idx = 1
  case "mode":
    opts.command = .mode; idx = 1
  case "relay":
    opts.command = .relay; idx = 1
  case "help", "-h", "--help":
    opts.command = .help; return opts
  case "--json":
    opts.command = .status; opts.jsonOutput = true; idx = 1
  case "--version", "-v":
    print("codex-rate 2.1.0")
    exit(0)
  default:
    fputs(ANSI.c(ANSI.red, "Unknown command: \(first)") + "\n", stderr)
    fputs("Run 'codex-rate help' for usage information.\n", stderr)
    exit(1)
  }

  // Parse mode subcommand (proxy/direct)
  if opts.command == .mode && idx < args.count && !args[idx].hasPrefix("-") {
    opts.modeTarget = args[idx]
    idx += 1
  }

  // Parse remaining flags
  while idx < args.count {
    let arg = args[idx]
    switch arg {
    case "--json":
      opts.jsonOutput = true
    case "--interval":
      idx += 1
      guard idx < args.count, let val = Int(args[idx]), val >= 10 else {
        exitWithError("--interval requires a value >= 10")
      }
      opts.watchInterval = val
    case "--hours":
      idx += 1
      guard idx < args.count, let val = Int(args[idx]), val > 0 else {
        exitWithError("--hours requires a positive integer")
      }
      opts.historyHours = val
    case "--strategy":
      idx += 1
      guard idx < args.count else {
        exitWithError("--strategy requires a value: reset-aware, greedy, or max-runway")
      }
      opts.relayStrategy = args[idx]
    case "--port":
      idx += 1
      guard idx < args.count, let val = UInt16(args[idx]) else {
        exitWithError("--port requires a valid port number (1-65535)")
      }
      opts.proxyPort = val
    case "--upstream":
      idx += 1
      guard idx < args.count else {
        exitWithError("--upstream requires a URL")
      }
      opts.proxyUpstream = args[idx]
    case "--no-relay":
      opts.noAutoRelay = true
    case "--verbose":
      opts.proxyVerbose = true
    case "-h", "--help":
      opts.command = .help; return opts
    default:
      fputs(ANSI.c(ANSI.yellow, "Warning: unknown flag '\(arg)'") + "\n", stderr)
    }
    idx += 1
  }

  return opts
}

// MARK: - Subcommand: Status

private func runStatus(json: Bool) async {
  let authStore = AuthStore()
  let auth: AuthSnapshot
  do {
    auth = try authStore.load()
  } catch {
    exitWithError("Failed to read auth: \(error.localizedDescription)")
  }

  let client = UsageAPIClient()
  let snapshot: UsageSnapshot
  do {
    snapshot = try await client.fetchUsage(auth: auth)
  } catch {
    exitWithError("Failed to fetch usage: \(error.localizedDescription)")
  }

  if json {
    let dict = snapshotToDict(snapshot, auth: auth)
    if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
       let str = String(data: data, encoding: .utf8) {
      print(str)
    }
    return
  }

  // Pretty table output
  let plan = snapshot.planType.capitalized
  let primary = snapshot.rateLimit.primaryWindow
  let review = snapshot.codeReviewRateLimit.primaryWindow

  let isBlocked = !snapshot.rateLimit.allowed || snapshot.rateLimit.limitReached
    || primary.remainingPercent <= 0

  let statusLabel: String
  if isBlocked {
    statusLabel = ANSI.c(ANSI.red, "\u{274C} Blocked")
  } else if primary.remainingPercent <= 15 {
    statusLabel = ANSI.c(ANSI.yellow, "\u{26A0}\u{FE0F}  Low")
  } else {
    statusLabel = ANSI.c(ANSI.green, "\u{2705} Active")
  }

  print(Box.topBorder())
  print(Box.centeredRow(ANSI.c(ANSI.bold + ANSI.cyan, "Codex Rate Watcher \u{00B7} Status")))
  print(Box.midBorder())
  print(Box.row("Plan: \(ANSI.c(ANSI.bold, plan))"))
  if let email = auth.email {
    print(Box.row("Account: \(ANSI.c(ANSI.dim, email))"))
  }
  print(Box.row("Status: \(statusLabel)"))
  print(Box.midBorder())

  // Primary window
  let pBar = ProgressBar.render(remainingPercent: primary.remainingPercent)
  let pLabel = "\(Int(primary.remainingPercent.rounded()))% left"
  print(Box.row("5h Window   \(pBar) \(ANSI.c(ANSI.color(forPercent: primary.remainingPercent), pLabel))"))

  // Secondary (weekly) window
  if let weekly = snapshot.rateLimit.secondaryWindow {
    let wBar = ProgressBar.render(remainingPercent: weekly.remainingPercent)
    let wLabel = "\(Int(weekly.remainingPercent.rounded()))% left"
    print(Box.row("Weekly      \(wBar) \(ANSI.c(ANSI.color(forPercent: weekly.remainingPercent), wLabel))"))
  } else {
    print(Box.row("Weekly      \(ANSI.c(ANSI.dim, "N/A"))"))
  }

  // Code review
  let rBar = ProgressBar.render(remainingPercent: review.remainingPercent)
  let rLabel = "\(Int(review.remainingPercent.rounded()))% left"
  print(Box.row("Review      \(rBar) \(ANSI.c(ANSI.color(forPercent: review.remainingPercent), rLabel))"))

  print(Box.midBorder())

  // Reset times
  print(Box.row("5h resets: \(formatResetTimestamp(resetAt: primary.resetAt))"))
  if let weekly = snapshot.rateLimit.secondaryWindow {
    print(Box.row("Weekly resets: \(formatResetTimestamp(resetAt: weekly.resetAt))"))
  }
  print(Box.row("Review resets: \(formatResetTimestamp(resetAt: review.resetAt))"))

  print(Box.bottomBorder())
}

// MARK: - Subcommand: Profiles

private func runProfiles(json: Bool) {
  let url = AppPaths.profileIndexFile
  guard FileManager.default.fileExists(atPath: url.path) else {
    if json {
      print("[]")
    } else {
      print(ANSI.c(ANSI.yellow, "No profiles found."))
      print(ANSI.c(ANSI.dim, "Profiles are created automatically by the menu bar app."))
    }
    return
  }

  let records: [AuthProfileRecord]
  do {
    let data = try Data(contentsOf: url)
    records = try JSONDecoder().decode([AuthProfileRecord].self, from: data)
  } catch {
    exitWithError("Failed to read profiles: \(error.localizedDescription)")
  }

  if json {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    if let data = try? encoder.encode(records),
       let str = String(data: data, encoding: .utf8) {
      print(str)
    }
    return
  }

  guard !records.isEmpty else {
    print(ANSI.c(ANSI.yellow, "No profiles saved yet."))
    return
  }

  // Table header
  let header = String(format: "%-6s %-24s %-6s %-8s %-8s %-14s",
    "ID", "Email", "Plan", "5h", "Weekly", "Status")
  print(ANSI.c(ANSI.bold, header))
  print(String(repeating: "\u{2500}", count: 70))

  for record in records {
    let id = String(record.fingerprint.prefix(4))
    let email = record.email ?? "\u{2014}"
    let truncEmail = email.count > 22 ? String(email.prefix(20)) + ".." : email

    let plan: String
    let primary: String
    let weekly: String
    let status: String

    if let usage = record.latestUsage {
      plan = usage.planDisplayName
      primary = "\(Int(usage.primaryRemainingPercent.rounded()))%"
      if let sr = usage.secondaryRemainingPercent {
        weekly = "\(Int(sr.rounded()))%"
      } else {
        weekly = "\u{2014}"
      }
      if usage.isBlocked {
        status = ANSI.c(ANSI.red, "\u{274C} Blocked")
      } else if usage.isRunningLow {
        status = ANSI.c(ANSI.yellow, "\u{26A0}\u{FE0F}  Low")
      } else {
        status = ANSI.c(ANSI.green, "\u{2705} Active")
      }
    } else if record.validationError != nil {
      plan = "\u{2014}"
      primary = "\u{2014}"
      weekly = "\u{2014}"
      status = ANSI.c(ANSI.red, "\u{2717} Error")
    } else {
      plan = "\u{2014}"
      primary = "\u{2014}"
      weekly = "\u{2014}"
      status = ANSI.c(ANSI.dim, "Pending")
    }

    let row = String(format: "%-6s %-24s %-6s %-8s %-8s %s",
      id, truncEmail, plan, primary, weekly, status)
    print(row)
  }

  print()
  print(ANSI.c(ANSI.dim, "\(records.count) profile(s) total"))
}

// MARK: - Subcommand: Watch

private func runWatch(interval: Int, json: Bool) async {
  // Trap SIGINT for graceful exit
  signal(SIGINT, SIG_IGN)
  let sigSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
  let running = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
  running.initialize(to: true)
  sigSource.setEventHandler {
    running.pointee = false
    print("\n" + ANSI.c(ANSI.dim, "Stopping watch..."))
  }
  sigSource.resume()
  defer {
    sigSource.cancel()
    running.deallocate()
  }

  let authStore = AuthStore()
  let client = UsageAPIClient()

  while running.pointee {
    // Clear screen
    if !json { print("\u{1B}[2J\u{1B}[H", terminator: "") }

    let auth: AuthSnapshot
    do {
      auth = try authStore.load()
    } catch {
      fputs(ANSI.c(ANSI.red, "Auth error: \(error.localizedDescription)") + "\n", stderr)
      try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
      continue
    }

    do {
      let snapshot = try await client.fetchUsage(auth: auth)

      if json {
        let dict = snapshotToDict(snapshot, auth: auth)
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
           let str = String(data: data, encoding: .utf8) {
          print(str)
        }
      } else {
        let plan = snapshot.planType.capitalized
        let primary = snapshot.rateLimit.primaryWindow
        let review = snapshot.codeReviewRateLimit.primaryWindow

        let now = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)

        print(Box.topBorder())
        print(Box.centeredRow(ANSI.c(ANSI.bold + ANSI.cyan, "Codex Rate Watcher \u{00B7} Watch Mode")))
        print(Box.centeredRow(ANSI.c(ANSI.dim, "Updated: \(now) \u{00B7} Every \(interval)s \u{00B7} Ctrl+C to stop")))
        print(Box.midBorder())
        print(Box.row("Plan: \(ANSI.c(ANSI.bold, plan))"))
        print(Box.midBorder())

        let pBar = ProgressBar.render(remainingPercent: primary.remainingPercent)
        print(Box.row("5h Window   \(pBar) \(Int(primary.remainingPercent.rounded()))% left"))

        if let weekly = snapshot.rateLimit.secondaryWindow {
          let wBar = ProgressBar.render(remainingPercent: weekly.remainingPercent)
          print(Box.row("Weekly      \(wBar) \(Int(weekly.remainingPercent.rounded()))% left"))
        }

        let rBar = ProgressBar.render(remainingPercent: review.remainingPercent)
        print(Box.row("Review      \(rBar) \(Int(review.remainingPercent.rounded()))% left"))

        print(Box.midBorder())
        print(Box.row("5h resets: \(formatResetTimestamp(resetAt: primary.resetAt))"))
        if let weekly = snapshot.rateLimit.secondaryWindow {
          print(Box.row("Weekly resets: \(formatResetTimestamp(resetAt: weekly.resetAt))"))
        }
        print(Box.bottomBorder())
      }
    } catch {
      fputs(ANSI.c(ANSI.red, "Fetch error: \(error.localizedDescription)") + "\n", stderr)
    }

    // Sleep with periodic checks for cancellation
    let sleepEnd = Date().addingTimeInterval(Double(interval))
    while running.pointee && Date() < sleepEnd {
      try? await Task.sleep(nanoseconds: 500_000_000)
    }
  }
}

// MARK: - Subcommand: History

private func runHistory(hours: Int, json: Bool) {
  let url = AppPaths.samplesFile
  guard FileManager.default.fileExists(atPath: url.path) else {
    if json {
      print("{\"samples\":[]}")
    } else {
      print(ANSI.c(ANSI.yellow, "No usage samples found."))
      print(ANSI.c(ANSI.dim, "Samples are recorded automatically by the menu bar app."))
    }
    return
  }

  let samples: [UsageSample]
  do {
    let data = try Data(contentsOf: url)
    samples = try JSONDecoder().decode([UsageSample].self, from: data)
  } catch {
    exitWithError("Failed to read samples: \(error.localizedDescription)")
  }

  let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
  let recent = samples
    .filter { $0.capturedAt >= cutoff }
    .sorted { $0.capturedAt < $1.capturedAt }

  guard !recent.isEmpty else {
    if json {
      print("{\"samples\":[]}")
    } else {
      print(ANSI.c(ANSI.yellow, "No samples in the last \(hours) hour(s)."))
    }
    return
  }

  if json {
    // Build JSON output
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    var output: [String: Any] = [
      "hours": hours,
      "sample_count": recent.count
    ]
    let primaryValues = recent.map { $0.primaryUsedPercent }
    let weeklyValues = recent.compactMap { $0.secondaryUsedPercent }
    let reviewValues = recent.map { $0.reviewUsedPercent }

    output["primary"] = [
      "values": primaryValues,
      "sparkline": Sparkline.render(values: primaryValues),
      "current": primaryValues.last ?? 0,
      "peak": primaryValues.max() ?? 0,
      "average": primaryValues.isEmpty ? 0 : primaryValues.reduce(0, +) / Double(primaryValues.count)
    ] as [String: Any]

    output["weekly"] = [
      "values": weeklyValues,
      "sparkline": weeklyValues.isEmpty ? "" : Sparkline.render(values: weeklyValues),
      "current": weeklyValues.last ?? 0,
      "peak": weeklyValues.max() ?? 0,
      "average": weeklyValues.isEmpty ? 0 : weeklyValues.reduce(0, +) / Double(weeklyValues.count)
    ] as [String: Any]

    output["review"] = [
      "values": reviewValues,
      "sparkline": Sparkline.render(values: reviewValues),
      "current": reviewValues.last ?? 0,
      "peak": reviewValues.max() ?? 0,
      "average": reviewValues.isEmpty ? 0 : reviewValues.reduce(0, +) / Double(reviewValues.count)
    ] as [String: Any]

    if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]),
       let str = String(data: data, encoding: .utf8) {
      print(str)
    }
    return
  }

  // Pretty sparkline output
  let primaryValues = recent.map { $0.primaryUsedPercent }
  let weeklyValues = recent.compactMap { $0.secondaryUsedPercent }
  let reviewValues = recent.map { $0.reviewUsedPercent }

  let timeRange: String = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    let start = formatter.string(from: recent.first!.capturedAt)
    let end = formatter.string(from: recent.last!.capturedAt)
    return "\(start) \u{2192} \(end)"
  }()

  print()
  print(ANSI.c(ANSI.bold + ANSI.cyan, "  Codex Usage History") + ANSI.c(ANSI.dim, "  (last \(hours)h \u{00B7} \(recent.count) samples \u{00B7} \(timeRange))"))
  print()

  func printSparkRow(label: String, values: [Double]) {
    guard !values.isEmpty else {
      print("  \(ANSI.c(ANSI.bold, label))  \(ANSI.c(ANSI.dim, "no data"))")
      return
    }
    let spark = Sparkline.render(values: values)
    let current = Int(values.last!.rounded())
    let peak = Int(values.max()!.rounded())
    let avg = Int((values.reduce(0, +) / Double(values.count)).rounded())
    let color = ANSI.color(forPercent: max(0, 100 - (values.last ?? 0)))
    print("  \(ANSI.c(ANSI.bold, label))  \(ANSI.c(color, spark))  now:\(current)%  peak:\(peak)%  avg:\(avg)%")
  }

  printSparkRow(label: "Primary (5h):", values: primaryValues)
  printSparkRow(label: "Weekly:      ", values: weeklyValues)
  printSparkRow(label: "Review:      ", values: reviewValues)
  print()
}


// MARK: - Subcommand: Relay

private func runRelay(strategyName: String, json: Bool) async {
  let url = AppPaths.profileIndexFile
  guard FileManager.default.fileExists(atPath: url.path) else {
    if json {
      print("{\"legs\":[], \"error\": \"no profiles\"}")
    } else {
      print(ANSI.c(ANSI.yellow, "No profiles found."))
      print(ANSI.c(ANSI.dim, "Profiles are created by the menu bar app."))
    }
    return
  }

  let records: [AuthProfileRecord]
  do {
    let data = try Data(contentsOf: url)
    records = try JSONDecoder().decode([AuthProfileRecord].self, from: data)
  } catch {
    exitWithError("Failed to read profiles: \(error.localizedDescription)")
  }

  let strategy: RelayStrategy
  switch strategyName {
  case "greedy": strategy = .greedy
  case "max-runway": strategy = .maxRunway
  default: strategy = .resetAware
  }

  // Determine active profile
  let authStore = AuthStore()
  var activeProfileID: UUID? = nil
  if let auth = try? authStore.load() {
    activeProfileID = records.first(where: { $0.email == auth.email })?.id
  }

  let inputs = RelayPlanner.inputs(from: records, activeProfileID: activeProfileID)
  let plan = RelayPlanner.plan(profiles: inputs, currentBurnRate: nil, strategy: strategy)

  if json {
    var dict: [String: Any] = [
      "strategy": strategy.rawValue,
      "leg_count": plan.legCount,
      "total_coverage_seconds": plan.totalCoverageSeconds,
      "coverage_summary": plan.coverageSummary,
      "can_survive_until_reset": plan.canSurviveUntilReset,
    ]
    if let exhaustAt = plan.allExhaustedAt {
      dict["all_exhausted_at"] = ISO8601DateFormatter().string(from: exhaustAt)
    }
    if let reset = plan.earliestPrimaryReset {
      dict["earliest_primary_reset"] = ISO8601DateFormatter().string(from: reset)
    }
    if let gap = plan.gapToResetSeconds {
      dict["gap_to_reset_seconds"] = gap
    }
    var legsArr: [[String: Any]] = []
    for leg in plan.legs {
      legsArr.append([
        "profile_id": leg.profileID.uuidString,
        "display_name": leg.displayName,
        "start_at": ISO8601DateFormatter().string(from: leg.startAt),
        "estimated_exhaust_at": ISO8601DateFormatter().string(from: leg.estimatedExhaustAt),
        "duration_seconds": leg.durationSeconds,
        "starting_remain_percent": leg.startingRemainPercent,
        "burn_rate_per_hour": leg.burnRatePerHour,
      ])
    }
    dict["legs"] = legsArr
    if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
       let str = String(data: data, encoding: .utf8) {
      print(str)
    }
    return
  }

  // Pretty output
  guard !plan.legs.isEmpty else {
    print(ANSI.c(ANSI.yellow, "\u{26A0}\u{FE0F}  No usable accounts for relay."))
    return
  }

  let legColors = [ANSI.blue, ANSI.green, ANSI.yellow, ANSI.red, ANSI.magenta]

  print()
  print(ANSI.c(ANSI.bold + ANSI.cyan, "  Relay Plan") + ANSI.c(ANSI.dim, "  (strategy: \(strategy.rawValue) \u{00B7} \(plan.legCount) accounts \u{00B7} \(plan.coverageSummary))"))
  print()

  // Timeline bar
  let barWidth = 40
  let total = plan.totalCoverageSeconds
  var barStr = ""
  for (idx, leg) in plan.legs.enumerated() {
    let fraction = leg.durationSeconds / total
    let segWidth = max(1, Int(Double(barWidth) * fraction))
    let color = legColors[idx % legColors.count]
    barStr += ANSI.c(color, String(repeating: "\u{2588}", count: segWidth))
  }
  print("  \(barStr)")
  print()

  // Legend
  for (idx, leg) in plan.legs.enumerated() {
    let color = legColors[idx % legColors.count]
    let dot = ANSI.c(color, "\u{25CF}")
    let tag = idx == 0 ? ANSI.c(ANSI.dim, " (current)") : ""
    let duration = formatDuration(seconds: Int(leg.durationSeconds))
    print("  \(dot) \(ANSI.c(ANSI.bold, leg.displayName))\(tag)  \(Int(leg.startingRemainPercent.rounded()))% \u{2192} 0%  \u{00B7} \(duration)")
  }
  print()

  // Summary
  if plan.canSurviveUntilReset {
    let resetLabel = plan.earliestPrimaryReset.map { formatResetTimestamp(resetAt: $0.timeIntervalSince1970) } ?? "?"
    print(ANSI.c(ANSI.green, "  \u{2705} Relay covers until reset (\(resetLabel))"))
  } else if let exhaustAt = plan.allExhaustedAt {
    let exhaustLabel = formatResetTimestamp(resetAt: exhaustAt.timeIntervalSince1970)
    let resetLabel = plan.earliestPrimaryReset.map { formatResetTimestamp(resetAt: $0.timeIntervalSince1970) } ?? "?"
    if let gapSecs = plan.gapToResetSeconds {
      let gapLabel = formatDuration(seconds: Int(abs(gapSecs)))
      print(ANSI.c(ANSI.yellow, "  \u{26A0}\u{FE0F}  All exhausted: \(exhaustLabel)"))
      print(ANSI.c(ANSI.yellow, "     Next reset: \(resetLabel)  \u{00B7}  Gap: \(gapLabel)"))
    } else {
      print(ANSI.c(ANSI.yellow, "  \u{26A0}\u{FE0F}  All exhausted: \(exhaustLabel)"))
    }
  }
  print()
}



// MARK: - Subcommand: Proxy

private func runProxy(opts: CLIOptions) async {
  let config = ProxyServer.Config(
    port: opts.proxyPort,
    upstream: opts.proxyUpstream,
    autoRelay: !opts.noAutoRelay,
    verbose: opts.proxyVerbose
  )

  // Trap SIGINT for graceful shutdown
  signal(SIGINT, SIG_IGN)
  let sigSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
  sigSource.setEventHandler {
    print("\n" + ANSI.c(ANSI.dim, "Shutting down proxy..."))
    Foundation.exit(0)
  }
  sigSource.resume()

  let server = ProxyServer(config: config)
  do {
    try await server.run()
  } catch {
    exitWithError(error.localizedDescription)
  }
}

// MARK: - Help


private func runCost(json: Bool) async {
  // Determine tier from profiles
  let profilesURL = AppPaths.profileIndexFile
  var tier = SubscriptionTier.plus
  if let data = try? Data(contentsOf: profilesURL),
     let profiles = try? JSONDecoder().decode([AuthProfileRecord].self, from: data) {
    if let active = profiles.first(where: { $0.isValid }),
       let usage = active.latestUsage {
      tier = SubscriptionTier(planType: usage.planType)
    }
  }

  let weekly = CostTracker.weeklyStats(tier: tier)
  let live = CostTracker.todaySummary(currentTier: tier, currentBurnRate: nil, currentUsedPercent: 0)

  if json {
    var result: [[String: Any]] = []
    for d in weekly {
      result.append([
        "date": d.date,
        "tier": d.tier.rawValue,
        "estimated_cost_usd": round(d.estimatedCostUSD * 100) / 100,
        "avg_utilization": round(d.avgUtilization * 1000) / 10,
        "active_minutes": d.totalActiveMinutes,
        "peak_burn_rate": d.peakBurnRate ?? 0,
        "cycles": d.cycles.count
      ])
    }
    if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
       let str = String(data: jsonData, encoding: .utf8) {
      print(str)
    }
    return
  }

  // Pretty output
  let bold = "\u{001B}[1m"
  let dim = "\u{001B}[2m"
  let green = "\u{001B}[32m"
  let yellow = "\u{001B}[33m"
  let cyan = "\u{001B}[36m"
  let reset = "\u{001B}[0m"

  print("")
  print("\(bold)💰 Cost Dashboard\(reset)")
  print("\(dim)────────────────────────────────────────\(reset)")
  print("")

  // Subscription info
  print("  \(dim)Subscription:\(reset)  \(bold)\(tier.rawValue.capitalized)\(reset) · $\(Int(tier.monthlyUSD))/mo")
  print("")

  // Today summary
  if let cph = live.costPerHour, cph > 0 {
    print("  \(dim)Burn Rate:\(reset)     \(green)$\(String(format: "%.2f", cph))/hr\(reset)")
  }
  print("  \(dim)Today Cost:\(reset)    \(bold)$\(String(format: "%.2f", live.todayCostUSD))\(reset)")
  print("  \(dim)Active Hours:\(reset)  \(String(format: "%.1f", live.activeHoursToday))h")
  if let proj = live.projectedMonthlyCostUSD {
    let color = proj > tier.monthlyUSD ? yellow : green
    print("  \(dim)Monthly Est:\(reset)   \(color)$\(String(format: "%.0f", proj))\(reset)")
  }
  print("")

  // 7-day history
  if !weekly.isEmpty {
    print("  \(bold)7-Day History\(reset)")
    print("  \(dim)Date         Cost     Util   Active  Cycles\(reset)")
    for d in weekly {
      let utilColor = d.avgUtilization > 0.5 ? green : yellow
      let utilPct = Int((d.avgUtilization * 100).rounded())
      let activeH = String(format: "%.1f", Double(d.totalActiveMinutes) / 60.0)
      print("  \(d.date)  \(cyan)$\(String(format: "%5.2f", d.estimatedCostUSD))\(reset)   \(utilColor)\(String(format: "%3d", utilPct))%\(reset)   \(activeH)h   \(d.cycles.count)")
    }

    let totalCost = weekly.map(\.estimatedCostUSD).reduce(0, +)
    let avgUtil = weekly.map(\.avgUtilization).reduce(0, +) / Double(weekly.count)
    print("  \(dim)─────────────────────────────────────\(reset)")
    print("  \(dim)Total:\(reset)       \(bold)$\(String(format: "%.2f", totalCost))\(reset)   \(String(format: "%3d", Int((avgUtil * 100).rounded())))%")
  } else {
    print("  \(dim)No history data yet. Run the app to collect samples.\(reset)")
  }

  print("")
}

private func printHelp() {
  let help = """
  \(ANSI.c(ANSI.bold + ANSI.cyan, "codex-rate")) \u{2014} Codex CLI Usage Monitor

  \(ANSI.c(ANSI.bold, "USAGE"))
    codex-rate [command] [options]

  \(ANSI.c(ANSI.bold, "COMMANDS"))
    status      Show current usage quotas (default)
    profiles    List saved authentication profiles
    watch       Continuous monitoring mode
    history     Show usage history with sparklines
    relay       Show relay plan across accounts
    cost        Show cost dashboard & 7-day spending
    proxy       Start local HTTP proxy for Codex API
    mode        Switch Codex between proxy and direct modes
    help        Show this help message

  \(ANSI.c(ANSI.bold, "OPTIONS"))
    --json               Output as JSON
    --interval <secs>    Watch polling interval (default: 30, min: 10)
    --hours <N>          History window in hours (default: 24)
    --strategy <name>    Relay strategy: reset-aware (default), greedy, max-runway
    --port <N>           Proxy listen port (default: 19876)
    --upstream <url>     Proxy upstream URL (default: https://api.openai.com)
    --no-relay           Disable automatic 429 failover
    --verbose            Verbose proxy logging
    -v, --version        Show version
    -h, --help           Show help

  \(ANSI.c(ANSI.bold, "EXAMPLES"))
    codex-rate                    Show current status
    codex-rate status --json      Status as JSON (for scripts/Raycast)
    codex-rate profiles           List all auth profiles
    codex-rate watch --interval 15  Monitor every 15 seconds
    codex-rate history --hours 6  Show last 6 hours
    codex-rate relay              Show relay plan
    codex-rate relay --strategy greedy  Use greedy strategy
    codex-rate cost              Show cost dashboard
    codex-rate cost --json       Cost data as JSON
    codex-rate proxy             Start proxy on port 19876
    codex-rate proxy --port 8080 Start proxy on custom port
    codex-rate proxy --verbose   Proxy with request logging
    codex-rate mode              Show current Codex mode
    codex-rate mode proxy        Switch to proxy mode
    codex-rate mode direct       Switch to direct/account mode
  \(ANSI.c(ANSI.dim, "Part of Codex Rate Watcher \u{00B7} https://github.com/patchwork-body/shakeflow"))
  """
  print(help)
}


// MARK: - Subcommand: Mode

private func runMode(target: String, port: UInt16, json: Bool) {
  let mgr = CodexConfigManager()
  let current = mgr.currentMode()

  // No target = show current mode
  if target.isEmpty {
    if json {
      let obj: [String: String] = [
        "mode": current.rawValue,
        "config": mgr.path,
      ]
      if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
         let str = String(data: data, encoding: .utf8) {
        print(str)
      }
    } else {
      let icon = current == .proxy ? "PROXY" : "DIRECT"
      let color = current == .proxy ? ANSI.magenta : ANSI.green
      print(ANSI.c(ANSI.bold, "Codex Mode: ") + ANSI.c(ANSI.bold + color, icon))
      print(ANSI.c(ANSI.dim, "  Config: \(mgr.path)"))
      if current == .proxy {
        print(ANSI.c(ANSI.dim, "  Proxy:  http://localhost:\(port)"))
      }
      print()
      print("Switch with:  codex-rate mode proxy | codex-rate mode direct")
    }
    return
  }

  // Switch mode
  switch target.lowercased() {
  case "proxy":
    if current == .proxy {
      print(ANSI.c(ANSI.yellow, "Already in proxy mode."))
      return
    }
    do {
      try mgr.switchTo(proxy: port)
      if json {
        print("{\"mode\":\"proxy\",\"port\":\(port)}")
      } else {
        print(ANSI.c(ANSI.green, "Switched to PROXY mode."))
        print("  Codex will route through: http://localhost:\(port)")
        print()
        print(ANSI.c(ANSI.dim, "Make sure the proxy is running:"))
        print(ANSI.c(ANSI.cyan, "  codex-rate proxy --port \(port)"))
      }
    } catch {
      fputs(ANSI.c(ANSI.red, "Failed: \(error.localizedDescription)") + "\n", stderr)
    }

  case "direct", "normal":
    if current == .direct {
      print(ANSI.c(ANSI.yellow, "Already in direct mode."))
      return
    }
    do {
      try mgr.switchToDirect()
      if json {
        print("{\"mode\":\"direct\"}")
      } else {
        print(ANSI.c(ANSI.green, "Switched to DIRECT mode."))
        print("  Codex will use account-based auth directly.")
      }
    } catch {
      fputs(ANSI.c(ANSI.red, "Failed: \(error.localizedDescription)") + "\n", stderr)
    }

  default:
    fputs(ANSI.c(ANSI.red, "Unknown mode: \(target)") + "\n", stderr)
    fputs("Usage: codex-rate mode [proxy|direct]\n", stderr)
  }
}

// MARK: - Main Entry Point

private let opts = parseArguments()

switch opts.command {
case .status:
  await runStatus(json: opts.jsonOutput)
case .profiles:
  runProfiles(json: opts.jsonOutput)
case .watch:
  await runWatch(interval: opts.watchInterval, json: opts.jsonOutput)
case .history:
  runHistory(hours: opts.historyHours, json: opts.jsonOutput)
case .cost:
  await runCost(json: opts.jsonOutput)
case .proxy:
  await runProxy(opts: opts)
case .mode:
  runMode(target: opts.modeTarget, port: opts.proxyPort, json: opts.jsonOutput)
case .relay:
  await runRelay(strategyName: opts.relayStrategy, json: opts.jsonOutput)
case .help:
  printHelp()
}
