import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Manages a global keyboard shortcut for toggling the popover.
///
/// Uses the standard NSEvent global + local monitors approach.
/// After registration, performs a **conflict probe** — posts a synthetic
/// keyDown and checks whether the monitor receives it within a timeout.
/// If not, it means another app intercepted the shortcut first.
///
/// When a conflict is detected, enumerates running apps to guess which
/// known shortcut-grabbing apps (Raycast, Alfred, Karabiner, etc.) might
/// be responsible, and notifies via `onConflict`.
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

  // MARK: - Conflict Detection

  struct ConflictInfo: Sendable {
    let shortcut: String
    let suspectedApps: [String]
    let message: String
  }

  /// Well-known apps that register global shortcuts and may conflict
  private static let knownHotkeyApps: [String: String] = [
    "com.raycast.macos": "Raycast",
    "com.runningwithcrayons.Alfred": "Alfred",
    "com.alfredapp.Alfred": "Alfred",
    "io.pock.pock": "Pock",
    "com.hegenberg.BetterTouchTool": "BetterTouchTool",
    "org.pqrs.Karabiner-Elements": "Karabiner-Elements",
    "com.googlecode.iterm2": "iTerm2",
    "com.sublimetext.4": "Sublime Text",
    "com.microsoft.VSCode": "VS Code",
    "com.jetbrains.intellij": "IntelliJ IDEA",
    "com.apple.Safari": "Safari",
    "org.hammerspoon.Hammerspoon": "Hammerspoon",
    "com.surteesstudios.Bartender": "Bartender",
    "com.lwouis.alt-tab-macos": "AltTab",
    "at.obdev.LaunchBar": "LaunchBar",
    "com.spotify.client": "Spotify",
    "org.sbarex.SourceCodeSyntaxHighlight": "SyntaxHighlight",
    "com.toggl.danern": "Toggl Track",
    "com.todoist.mac.Todoist": "Todoist",
    "com.hnc.Discord": "Discord",
    "com.tinyspeck.slackmacgap": "Slack",
    "us.zoom.xos": "Zoom",
    "com.linear": "Linear",
    "com.figma.Desktop": "Figma",
    "com.pop.pop.app": "Pop",
    "com.crowdcafe.windowmagnet": "Magnet",
    "com.manytricks.Moom": "Moom",
    "com.divisiblebyzero.Spectacle": "Spectacle",
    "com.mathew-kurian.Sip": "Sip",
    "com.if.Paste": "Paste",
    "com.clipy-app.Clipy": "Clipy",
    "net.shinyfrog.bear": "Bear",
    "com.flexibits.fantastical2.mac": "Fantastical",
  ]

  // MARK: - Properties

  private(set) var config: Config
  var onToggle: (() -> Void)?
  /// Called when conflict is detected after registration
  var onConflict: ((ConflictInfo) -> Void)?

  /// Current conflict status (nil = no conflict or not yet probed)
  private(set) var currentConflict: ConflictInfo?

  private var globalMonitor: Any?
  private var localMonitor: Any?

  /// Flag used during conflict probe
  private var probeReceived: Bool = false
  private var isProbing: Bool = false

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
      // Delay probe slightly to let the app settle after launch
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
        self?.probeForConflict()
      }
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
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        self?.probeForConflict()
      }
    }
  }

  /// Manually re-run conflict detection
  func recheckConflict() {
    currentConflict = nil
    probeForConflict()
  }

  /// Human-readable status line
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
          guard let self else { return }
          if self.isProbing {
            self.probeReceived = true
          } else {
            self.onToggle?()
          }
        }
      }
    }

    // Local monitor — fires when app IS focused
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      let eventMods = event.modifierFlags.intersection([.command, .shift, .option, .control])
      if event.keyCode == targetKeyCode && eventMods == targetMods {
        Task { @MainActor [weak self] in
          guard let self else { return }
          if self.isProbing {
            self.probeReceived = true
          } else {
            self.onToggle?()
          }
        }
        return nil  // consume the event
      }
      return event
    }

    NSLog("[HotkeyManager] Registered NSEvent monitors for \(config.displayString)")
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

  // MARK: - Conflict Probe

  /// Posts a synthetic keyDown event with our shortcut and checks
  /// if the global monitor receives it. If it doesn't within a timeout,
  /// another app is likely intercepting the combo.
  private func probeForConflict() {
    guard config.enabled else { return }

    isProbing = true
    probeReceived = false

    // Build CGEventFlags from our config
    var cgFlags: CGEventFlags = []
    let m = config.effectiveModifiers
    if m.contains(.command) { cgFlags.insert(.maskCommand) }
    if m.contains(.shift)   { cgFlags.insert(.maskShift) }
    if m.contains(.option)  { cgFlags.insert(.maskAlternate) }
    if m.contains(.control) { cgFlags.insert(.maskControl) }

    // Post a synthetic key event
    if let event = CGEvent(keyboardEventSource: nil, virtualKey: config.keyCode, keyDown: true) {
      event.flags = cgFlags
      event.post(tap: .cgAnnotatedSessionEventTap)

      // Also post keyUp to clean up
      if let upEvent = CGEvent(keyboardEventSource: nil, virtualKey: config.keyCode, keyDown: false) {
        upEvent.flags = cgFlags
        upEvent.post(tap: .cgAnnotatedSessionEventTap)
      }
    }

    // Check after a short delay if we received it
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
      guard let self, self.isProbing else { return }
      self.isProbing = false

      if self.probeReceived {
        NSLog("[HotkeyManager] ✅ Probe OK — \(self.config.displayString) is working")
        self.currentConflict = nil
      } else {
        // Conflict detected — find who might be grabbing it
        let suspects = self.detectSuspectedApps()
        let suspectNames = suspects.isEmpty ? ["未知应用"] : suspects

        let message: String
        if suspects.isEmpty {
          message = "可能被其他应用抢占"
        } else {
          message = "可能被 \(suspects.joined(separator: "、")) 抢占"
        }

        let info = ConflictInfo(
          shortcut: self.config.displayString,
          suspectedApps: suspectNames,
          message: message
        )
        self.currentConflict = info
        self.onConflict?(info)

        NSLog("[HotkeyManager] ⚠️ Conflict detected for \(self.config.displayString) — \(message)")
      }
    }
  }

  /// Scan running apps for known hotkey-heavy applications
  private func detectSuspectedApps() -> [String] {
    let runningApps = NSWorkspace.shared.runningApplications
    var suspects: [String] = []

    for app in runningApps {
      guard let bundleID = app.bundleIdentifier else { continue }
      if let name = Self.knownHotkeyApps[bundleID] {
        suspects.append(name)
      }
    }

    return suspects
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
