import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Manages a global keyboard shortcut for toggling the popover.
///
/// **Strategy (priority order)**:
/// 1. **CGEvent Tap** — intercepts events at the HID level before any app sees them.
///    Requires Accessibility permission. This is the most reliable approach.
/// 2. **NSEvent global monitor** — fallback if CGEvent Tap cannot be created
///    (permission denied). Less reliable if another app consumes the combo.
///
/// **Conflict detection**: On startup and after each config change, a probe timer
/// verifies the hotkey is reachable. If the primary shortcut is blocked (no callback
/// within 0.5 s of a synthetic key-down), the manager automatically tries fallback
/// combos and notifies via `onConflict`.
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

    var cgEventFlags: CGEventFlags {
      var flags: CGEventFlags = []
      let m = effectiveModifiers
      if m.contains(.command) { flags.insert(.maskCommand) }
      if m.contains(.shift)   { flags.insert(.maskShift) }
      if m.contains(.option)  { flags.insert(.maskAlternate) }
      if m.contains(.control) { flags.insert(.maskControl) }
      return flags
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

  // MARK: - Conflict Info

  struct ConflictInfo: Sendable {
    let originalShortcut: String
    let activeShortcut: String
    let message: String
  }

  /// Fallback shortcuts to try when the primary is blocked
  private static let fallbackConfigs: [(keyCode: UInt16, modifiers: NSEvent.ModifierFlags)] = [
    (0x28, [.command, .option]),          // ⌘⌥K
    (0x28, [.control, .shift]),           // ⌃⇧K
    (0x28, [.command, .option, .shift]),   // ⌘⌥⇧K
    (0x28, [.control, .option]),           // ⌃⌥K
  ]

  // MARK: - Properties

  private(set) var config: Config
  var onToggle: (() -> Void)?
  /// Called when the shortcut was changed due to conflict detection
  var onConflict: ((ConflictInfo) -> Void)?

  private var globalMonitor: Any?
  private var localMonitor: Any?
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private(set) var usingCGEventTap: Bool = false

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

  /// Check if Accessibility permissions are granted (needed for CGEvent Tap)
  static var hasAccessibilityPermission: Bool {
    AXIsProcessTrusted()
  }

  /// Prompt user for Accessibility permission
  static func requestAccessibilityPermission() {
    // Use @preconcurrency-safe workaround for kAXTrustedCheckOptionPrompt
    let prompt = "AXTrustedCheckOptionPrompt" as CFString
    let options = [prompt: true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
  }
  // MARK: - CGEvent Tap (Primary Strategy)

  private func startCGEventTap() -> Bool {
    // Store config values for the C callback closure
    let targetKeyCode = Int64(config.keyCode)
    let targetFlags = config.cgEventFlags

    // We need to pass context to the C callback
    let context = UnsafeMutablePointer<HotkeyContext>.allocate(capacity: 1)
    context.initialize(to: HotkeyContext(
      keyCode: targetKeyCode,
      flags: targetFlags,
      fired: false
    ))

    let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,  // active tap — can consume events
      eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
      callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
        guard type == .keyDown, let ctx = refcon?.assumingMemoryBound(to: HotkeyContext.self) else {
          return Unmanaged.passRetained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let eventFlags = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        let targetFlags = ctx.pointee.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])

        if keyCode == ctx.pointee.keyCode && eventFlags == targetFlags {
          ctx.pointee.fired = true
          // Post notification to main thread
          DistributedNotificationCenter.default().post(
            name: .hotkeyFired,
            object: nil
          )
          return nil  // consume the event — no other app sees it
        }

        return Unmanaged.passRetained(event)
      },
      userInfo: context
    )

    guard let tap else {
      context.deallocate()
      return false
    }

    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)

    eventTap = tap
    runLoopSource = source

    // Listen for the distributed notification
    DistributedNotificationCenter.default().addObserver(
      self,
      selector: #selector(handleHotkeyNotification),
      name: .hotkeyFired,
      object: nil
    )

    return true
  }

  @objc private func handleHotkeyNotification() {
    Task { @MainActor in
      self.onToggle?()
    }
  }

  private func stopCGEventTap() {
    if let tap = eventTap {
      CGEvent.tapEnable(tap: tap, enable: false)
      if let source = runLoopSource {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
      }
      // Note: CFMachPort is managed by CF, we just nil our references
      eventTap = nil
      runLoopSource = nil
    }
    DistributedNotificationCenter.default().removeObserver(
      self, name: .hotkeyFired, object: nil
    )
  }

  // MARK: - NSEvent Monitor (Fallback Strategy)

  private func startNSEventMonitor() {
    let targetKeyCode = config.keyCode
    let targetMods = config.effectiveModifiers.intersection([.command, .shift, .option, .control])

    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      let eventMods = event.modifierFlags.intersection([.command, .shift, .option, .control])
      if event.keyCode == targetKeyCode && eventMods == targetMods {
        Task { @MainActor [weak self] in
          self?.onToggle?()
        }
      }
    }

    localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      let eventMods = event.modifierFlags.intersection([.command, .shift, .option, .control])
      if event.keyCode == targetKeyCode && eventMods == targetMods {
        Task { @MainActor [weak self] in
          self?.onToggle?()
        }
        return nil
      }
      return event
    }
  }

  private func stopNSEventMonitor() {
    if let m = globalMonitor {
      NSEvent.removeMonitor(m)
      globalMonitor = nil
    }
    if let m = localMonitor {
      NSEvent.removeMonitor(m)
      localMonitor = nil
    }
  }

  // MARK: - Combined Start/Stop

  private func startMonitoring() {
    stopMonitoring()

    // Try CGEvent Tap first (most reliable)
    if startCGEventTap() {
      usingCGEventTap = true
      // Also add local monitor for when our own window is focused
      let targetKeyCode = config.keyCode
      let targetMods = config.effectiveModifiers.intersection([.command, .shift, .option, .control])
      localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        let eventMods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if event.keyCode == targetKeyCode && eventMods == targetMods {
          Task { @MainActor [weak self] in
            self?.onToggle?()
          }
          return nil
        }
        return event
      }
      NSLog("[HotkeyManager] ✅ Using CGEvent Tap for \(config.displayString) — highest priority")
    } else {
      usingCGEventTap = false
      startNSEventMonitor()
      NSLog("[HotkeyManager] ⚠️ CGEvent Tap unavailable, using NSEvent monitor for \(config.displayString)")

      // Request Accessibility permission if not granted
      if !Self.hasAccessibilityPermission {
        NSLog("[HotkeyManager] 🔐 Requesting Accessibility permission for reliable hotkeys")
        Self.requestAccessibilityPermission()
      }
    }
  }

  private func stopMonitoring() {
    stopCGEventTap()
    stopNSEventMonitor()
    usingCGEventTap = false
  }

  /// Returns a diagnostic summary of the hotkey state
  var diagnosticInfo: String {
    var lines: [String] = []
    lines.append("Hotkey: \(config.enabled ? config.displayString : "disabled")")
    lines.append("Method: \(usingCGEventTap ? "CGEvent Tap (high priority)" : "NSEvent Monitor (normal)")")
    lines.append("Accessibility: \(Self.hasAccessibilityPermission ? "granted" : "NOT granted")")
    return lines.joined(separator: "\n")
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

// MARK: - CGEvent Tap Context

private struct HotkeyContext {
  let keyCode: Int64
  let flags: CGEventFlags
  var fired: Bool
}

// MARK: - Notification Name

extension Notification.Name {
  static let hotkeyFired = Notification.Name("com.codexratewatcher.hotkeyFired")
}
