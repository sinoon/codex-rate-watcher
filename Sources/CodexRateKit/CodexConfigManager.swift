import Foundation

// MARK: - CodexConfigManager

/// Manages Codex CLI config.toml to toggle between proxy and direct modes.
public struct CodexConfigManager {

  public enum Mode: String, CustomStringConvertible {
    case proxy  = "proxy"
    case direct = "direct"
    public var description: String { rawValue }
  }

  public enum ConfigError: Error, LocalizedError {
    case configNotFound(String)
    case readFailed(String)
    case writeFailed(String)

    public var errorDescription: String? {
      switch self {
      case .configNotFound(let p): return "Codex config not found: \(p)"
      case .readFailed(let m):     return "Failed to read config: \(m)"
      case .writeFailed(let m):    return "Failed to write config: \(m)"
      }
    }
  }

  private let configPath: String
  private static let providerKey = "rate_watcher"

  // MARK: Init

  public init(configPath: String? = nil) {
    if let p = configPath {
      self.configPath = p
    } else {
      let home = FileManager.default.homeDirectoryForCurrentUser.path
      self.configPath = "\(home)/.codex/config.toml"
    }
  }

  // MARK: Public – read

  /// The resolved config file path.
  public var path: String { configPath }

  /// Detect current mode by scanning for an active `model_provider = "rate_watcher"`.
  public func currentMode() -> Mode {
    guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
      return .direct
    }
    return Self.detectMode(in: content)
  }

  // MARK: Public – write

  /// Switch Codex to proxy mode (route through rate-watcher proxy).
  @discardableResult
  public func switchTo(proxy port: UInt16 = 19876) throws -> String {
    let content = try readConfig()
    try backup(content)
    var lines = content.components(separatedBy: "\n")

    // 1. Comment out every active model_provider line that isn't ours
    for i in 0..<lines.count {
      let t = lines[i].trimmingCharacters(in: .whitespaces)
      guard !t.hasPrefix("#"), t.hasPrefix("model_provider"), t.contains("=") else { continue }
      if !t.contains(Self.providerKey) {
        lines[i] = "# \(lines[i])"
      }
    }

    // 2. Ensure our provider line is present and uncommented
    if let idx = indexOfLine(containing: Self.providerKey, withPrefix: "model_provider", in: lines) {
      lines[idx] = "model_provider = \"\(Self.providerKey)\""
    } else {
      let insertAt = insertionPointForProvider(in: lines)
      lines.insert("model_provider = \"\(Self.providerKey)\"", at: insertAt)
    }

    // 3. Ensure [model_providers.rate_watcher] section exists
    let joined = lines.joined(separator: "\n")
    if !joined.contains("[model_providers.\(Self.providerKey)]") {
      let section = [
        "",
        "[model_providers.\(Self.providerKey)]",
        "name = \"Rate Watcher Proxy\"",
        "base_url = \"http://localhost:\(port)\"",
        "wire_api = \"responses\"",
      ]
      let at = insertionPointForSection(in: lines)
      lines.insert(contentsOf: section, at: at)
    } else {
      // Update port in existing section
      updatePort(port, in: &lines)
    }

    try writeConfig(lines.joined(separator: "\n"))
    return configPath
  }

  /// Switch back to direct / account mode.
  @discardableResult
  public func switchToDirect() throws -> String {
    let content = try readConfig()
    try backup(content)
    var lines = content.components(separatedBy: "\n")

    for i in 0..<lines.count {
      let t = lines[i].trimmingCharacters(in: .whitespaces)
      if !t.hasPrefix("#"), t.contains("model_provider"), t.contains(Self.providerKey) {
        lines[i] = "# \(lines[i])"
        break
      }
    }

    try writeConfig(lines.joined(separator: "\n"))
    return configPath
  }

  // MARK: Internal helpers (visible to tests)

  static func detectMode(in content: String) -> Mode {
    for line in content.components(separatedBy: "\n") {
      let t = line.trimmingCharacters(in: .whitespaces)
      if !t.hasPrefix("#"), t.hasPrefix("model_provider"), t.contains(providerKey) {
        return .proxy
      }
    }
    return .direct
  }

  // MARK: Private

  private func readConfig() throws -> String {
    guard FileManager.default.fileExists(atPath: configPath) else {
      throw ConfigError.configNotFound(configPath)
    }
    do { return try String(contentsOfFile: configPath, encoding: .utf8) }
    catch { throw ConfigError.readFailed(error.localizedDescription) }
  }

  private func writeConfig(_ content: String) throws {
    do { try content.write(toFile: configPath, atomically: true, encoding: .utf8) }
    catch { throw ConfigError.writeFailed(error.localizedDescription) }
  }

  private func backup(_ content: String) throws {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
    try content.write(
      toFile: configPath + ".rw-backup.\(fmt.string(from: Date()))",
      atomically: true, encoding: .utf8
    )
  }

  /// Find an existing line that contains `keyword` and starts with `prefix`.
  private func indexOfLine(containing keyword: String, withPrefix prefix: String, in lines: [String]) -> Int? {
    for i in 0..<lines.count {
      let t = lines[i].trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "# ", with: "")
        .replacingOccurrences(of: "#", with: "")
      if t.hasPrefix(prefix), t.contains(keyword) { return i }
    }
    return nil
  }

  /// Best line to insert `model_provider = ...` (right after the `model = ...` line).
  private func insertionPointForProvider(in lines: [String]) -> Int {
    for i in 0..<lines.count {
      let t = lines[i].trimmingCharacters(in: .whitespaces)
      if !t.hasPrefix("#"), t.hasPrefix("model "), t.contains("=") { return i + 1 }
    }
    return min(1, lines.count)
  }

  /// Best line to insert the `[model_providers.rate_watcher]` section.
  private func insertionPointForSection(in lines: [String]) -> Int {
    var lastProviderEnd = -1
    for i in 0..<lines.count {
      if lines[i].hasPrefix("[model_providers.") {
        var j = i + 1
        while j < lines.count, !lines[j].hasPrefix("[") { j += 1 }
        lastProviderEnd = j
      }
    }
    if lastProviderEnd > 0 { return lastProviderEnd }

    // Fallback: insert before first non-model top-level section
    for i in 0..<lines.count {
      let l = lines[i]
      if l.hasPrefix("[projects.") || l.hasPrefix("[notice") || l.hasPrefix("[memories")
        || l.hasPrefix("[mcp_servers") || l.hasPrefix("[sandbox") || l.hasPrefix("[features")
      {
        return i
      }
    }
    return lines.count
  }

  /// Update `base_url` inside the `[model_providers.rate_watcher]` section.
  private func updatePort(_ port: UInt16, in lines: inout [String]) {
    var inSection = false
    for i in 0..<lines.count {
      if lines[i].contains("[model_providers.\(Self.providerKey)]") {
        inSection = true; continue
      }
      if inSection, lines[i].hasPrefix("[") { break }
      if inSection, lines[i].contains("base_url") {
        lines[i] = "base_url = \"http://localhost:\(port)\""
        break
      }
    }
  }
}
