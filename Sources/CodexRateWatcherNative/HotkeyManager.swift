import AppKit
import Foundation

/// Manages a global keyboard shortcut for toggling the popover.
/// Uses NSEvent global + local monitors (no Carbon dependency).
/// Default shortcut: ⌘⇧K
@MainActor
final class HotkeyManager {

  // MARK: - Config

  struct Config: Codable, Equatable, Sendable {
    var enabled: Bool = true
    var keyCode: UInt16 = 0x28  // kVK_ANSI_K
    var modifiers: UInt = 0     // stored as raw NSEvent.ModifierFlags
    // Default: .command + .shift
    static let defaultModifiers: NSEvent.ModifierFlags = [.command, .shift]

    var effectiveModifiers: NSEvent.ModifierFlags {
      modifiers == 0 ? Self.defaultModifiers : NSEvent.ModifierFlags(rawValue: modifiers)
    }

    var displayString: String {
      var parts: [String] = []
      let flags = effectiveModifiers
      if flags.contains(.control) { parts.append("⌃") }
      if flags.contains(.option)  { parts.append("⌥") }
      if flags.contains(.shift)   { parts.append("⇧") }
      if flags.contains(.command) { parts.append("⌘") }
      parts.append(Self.keyName(for: keyCode))
      return parts.joined()
    }

    private static func keyName(for code: UInt16) -> String {
      let names: [UInt16: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
        0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
        0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
        0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
        0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
        0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
        0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
        0x25: "L", 0x26: "J", 0x28: "K", 0x29: ";", 0x2A: "\\",
        0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".",
        0x24: "↩", 0x30: "⇥", 0x31: "␣", 0x33: "⌫", 0x35: "⎋",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
        0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
      ]
      return names[code] ?? "Key(\(code))"
    }
  }

  // MARK: - Properties

  private(set) var config: Config
  var onToggle: (() -> Void)?

  private var globalMonitor: Any?
  private var localMonitor: Any?

  private static let configURL: URL = {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
      .appendingPathComponent("CodexRateWatcherNative", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("hotkey-config.json")
  }()

  // MARK: - Init

  init() {
    config = Self.loadConfig()
    if config.enabled {
      startMonitoring()
    }
  }

  // MARK: - Public API

  func updateConfig(_ newConfig: Config) {
    guard newConfig != config else { return }
    stopMonitoring()
    config = newConfig
    saveConfig()
    if config.enabled {
      startMonitoring()
    }
  }

  // MARK: - Event Monitoring

  private func startMonitoring() {
    stopMonitoring()

    let targetKeyCode = config.keyCode
    let targetMods = config.effectiveModifiers.intersection([.command, .shift, .option, .control])

    // Global monitor — fires when app is NOT focused
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      let eventMods = event.modifierFlags.intersection([.command, .shift, .option, .control])
      if event.keyCode == targetKeyCode && eventMods == targetMods {
        Task { @MainActor [weak self] in
          self?.onToggle?()
        }
      }
    }

    // Local monitor — fires when app IS focused
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      let eventMods = event.modifierFlags.intersection([.command, .shift, .option, .control])
      if event.keyCode == targetKeyCode && eventMods == targetMods {
        Task { @MainActor [weak self] in
          self?.onToggle?()
        }
        return nil  // consume the event
      }
      return event
    }
  }

  private func stopMonitoring() {
    if let m = globalMonitor {
      NSEvent.removeMonitor(m)
      globalMonitor = nil
    }
    if let m = localMonitor {
      NSEvent.removeMonitor(m)
      localMonitor = nil
    }
  }

  // MARK: - Persistence

  private func saveConfig() {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(config) else { return }
    try? data.write(to: Self.configURL, options: .atomic)
  }

  private static func loadConfig() -> Config {
    guard let data = try? Data(contentsOf: configURL),
          let config = try? JSONDecoder().decode(Config.self, from: data) else {
      return Config()
    }
    return config
  }
}
