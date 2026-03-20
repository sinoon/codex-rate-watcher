import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Manages a global keyboard shortcut for toggling the popover.
///
/// Uses standard NSEvent global + local monitors (no special permissions).
/// Default shortcut: ⌃⌥U (Control + Option + R).
///
/// After registration, performs a **static conflict check** by scanning
/// running applications against a database of known shortcut mappings.
/// If a likely conflict is found, notifies via `onConflict` with the
/// suspected app name, so the user can decide what to do.
@MainActor
final class HotkeyManager {

  // MARK: - Config

  struct Config: Codable, Equatable, Sendable {
    var enabled: Bool = true
    var keyCode: UInt16 = 0x20  // kVK_ANSI_U
    var modifiers: UInt = 0     // stored as raw NSEvent.ModifierFlags
    // Default: .control + .option
    static let defaultModifiers: NSEvent.ModifierFlags = [.control, .option]

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

  // MARK: - Conflict Detection

  struct ConflictInfo: Sendable {
    let shortcut: String
    let suspectedApps: [String]
    let message: String
  }

  /// Known global shortcuts registered by popular apps.
  /// Key: "bundleID", Value: list of (keyCode, modifierFlags) combos the app is known to use.
  /// This is a best-effort heuristic — apps can be reconfigured by users.
  private struct KnownShortcut {
    let bundleID: String
    let appName: String
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
  }

  private static let knownShortcuts: [KnownShortcut] = [
    // Raycast defaults
    KnownShortcut(bundleID: "com.raycast.macos", appName: "Raycast", keyCode: 0x31, modifiers: [.option]),  // ⌥Space
    KnownShortcut(bundleID: "com.raycast.macos", appName: "Raycast", keyCode: 0x28, modifiers: [.command, .shift]),  // ⌘⇧K (snippets)
    // Alfred defaults
    KnownShortcut(bundleID: "com.runningwithcrayons.Alfred", appName: "Alfred", keyCode: 0x31, modifiers: [.option]),  // ⌥Space
    KnownShortcut(bundleID: "com.alfredapp.Alfred", appName: "Alfred", keyCode: 0x31, modifiers: [.option]),
    // Spotlight
    KnownShortcut(bundleID: "com.apple.Spotlight", appName: "Spotlight", keyCode: 0x31, modifiers: [.command]),  // ⌘Space
    // BetterTouchTool — varies, but common
    KnownShortcut(bundleID: "com.hegenberg.BetterTouchTool", appName: "BetterTouchTool", keyCode: 0x28, modifiers: [.command, .shift]),
    // VS Code — ⌘⇧K is delete line
    KnownShortcut(bundleID: "com.microsoft.VSCode", appName: "VS Code", keyCode: 0x28, modifiers: [.command, .shift]),
    // iTerm2 — ⌘⇧K is clear buffer (local, not global)
    // Magnet window manager
    KnownShortcut(bundleID: "com.crowdcafe.windowmagnet", appName: "Magnet", keyCode: 0x0F, modifiers: [.control, .option]),  // ⌃⌥R (right half)
    // Rectangle window manager
    KnownShortcut(bundleID: "com.knollsoft.Rectangle", appName: "Rectangle", keyCode: 0x0F, modifiers: [.control, .option]),  // ⌃⌥R
    // Moom
    KnownShortcut(bundleID: "com.manytricks.Moom", appName: "Moom", keyCode: 0x0F, modifiers: [.control, .option]),
    // Spectacle
    KnownShortcut(bundleID: "com.divisiblebyzero.Spectacle", appName: "Spectacle", keyCode: 0x0F, modifiers: [.option, .command]),  // ⌘⌥R
  ]

  /// Well-known apps that are heavy shortcut users (for general warning)
  private static let knownHotkeyApps: [String: String] = [
    "com.raycast.macos": "Raycast",
    "com.runningwithcrayons.Alfred": "Alfred",
    "com.alfredapp.Alfred": "Alfred",
    "com.hegenberg.BetterTouchTool": "BetterTouchTool",
    "org.pqrs.Karabiner-Elements": "Karabiner-Elements",
    "org.hammerspoon.Hammerspoon": "Hammerspoon",
    "com.crowdcafe.windowmagnet": "Magnet",
    "com.knollsoft.Rectangle": "Rectangle",
    "com.manytricks.Moom": "Moom",
    "com.divisiblebyzero.Spectacle": "Spectacle",
    "at.obdev.LaunchBar": "LaunchBar",
    "com.lwouis.alt-tab-macos": "AltTab",
    "com.surteesstudios.Bartender": "Bartender",
  ]

  // MARK: - Properties

  private(set) var config: Config
  var onToggle: (() -> Void)?
  /// Called when a potential conflict is detected
  var onConflict: ((ConflictInfo) -> Void)?

  /// Current conflict status (nil = no conflict detected)
  private(set) var currentConflict: ConflictInfo?

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
      checkForConflicts()
    }
  }

  // MARK: - Public API

  func updateConfig(_ newConfig: Config) {
    guard newConfig != config else { return }
    stopMonitoring()
    config = newConfig
    currentConflict = nil
    saveConfig()
    if config.enabled {
      startMonitoring()
      checkForConflicts()
    }
  }

  /// Manually re-run conflict detection
  func recheckConflicts() {
    currentConflict = nil
    checkForConflicts()
  }

  /// Human-readable status for the right-click menu
  var statusLine: String {
    if !config.enabled { return "快捷键已关闭" }
    if let conflict = currentConflict {
      return "\(config.displayString) ⚠️ \(conflict.message)"
    }
    return "\(config.displayString) ✓"
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

    NSLog("[HotkeyManager] Registered \(config.displayString)")
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

  // MARK: - Static Conflict Detection

  /// Check running apps against known shortcut database to detect
  /// likely conflicts. This is a heuristic — it checks default shortcuts
  /// of popular apps, not actual runtime registrations.
  private func checkForConflicts() {
    let runningBundleIDs = Set(
      NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
    )

    let myKeyCode = config.keyCode
    let myMods = config.effectiveModifiers.intersection([.command, .shift, .option, .control])

    // Check for exact match in known shortcuts database
    var exactConflicts: [String] = []
    for known in Self.knownShortcuts {
      guard runningBundleIDs.contains(known.bundleID) else { continue }
      let knownMods = known.modifiers.intersection([.command, .shift, .option, .control])
      if known.keyCode == myKeyCode && knownMods == myMods {
        if !exactConflicts.contains(known.appName) {
          exactConflicts.append(known.appName)
        }
      }
    }

    if !exactConflicts.isEmpty {
      let names = exactConflicts.joined(separator: "、")
      let info = ConflictInfo(
        shortcut: config.displayString,
        suspectedApps: exactConflicts,
        message: "\(names) 默认也使用 \(config.displayString)"
      )
      currentConflict = info
      onConflict?(info)
      NSLog("[HotkeyManager] ⚠️ Potential conflict: \(config.displayString) — \(info.message)")
      NSLog("[HotkeyManager] 💡 Tip: check \(names) settings, or change shortcut in right-click menu")
      return
    }

    // No exact match — check if any heavy-shortcut apps are running (informational only)
    var hotkeyAppsRunning: [String] = []
    for (bundleID, name) in Self.knownHotkeyApps {
      if runningBundleIDs.contains(bundleID) {
        hotkeyAppsRunning.append(name)
      }
    }

    if !hotkeyAppsRunning.isEmpty {
      NSLog("[HotkeyManager] ℹ️ \(config.displayString) registered. Note: \(hotkeyAppsRunning.joined(separator: ", ")) running (no known conflict)")
    } else {
      NSLog("[HotkeyManager] ✅ \(config.displayString) registered — no conflicts detected")
    }

    currentConflict = nil
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
