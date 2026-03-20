import Foundation
import UserNotifications
import CodexRateKit
/// Manages alert notifications when quota drops below configured thresholds.
/// Tracks which alerts have already fired per reset-window to avoid spam.
@MainActor
final class AlertManager {

  // MARK: - Configuration

  struct Config: Codable, Equatable {
    var enabled: Bool = true
    /// Thresholds (percent remaining) that trigger notifications, descending.
    var thresholds: [Int] = [50, 30, 15, 5]
    /// Also send a notification when quota is fully exhausted.
    var notifyOnExhausted: Bool = true
    /// Play sound with notification.
    var playSound: Bool = true
  }

  // MARK: - State

  /// Tracks which threshold was last fired for a given quota window,
  /// keyed by "primary-{resetAt}" / "weekly-{resetAt}".
  private var firedAlerts: [String: Int] = [:]

  private(set) var config: Config {
    didSet { saveConfig() }
  }

  private static let configURL: URL = {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
      .appendingPathComponent("CodexRateWatcherNative", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("alert-config.json")
  }()

  // MARK: - Init

  init() {
    config = Self.loadConfig()
    requestNotificationPermission()
  }

  // MARK: - Public API

  func updateConfig(_ newConfig: Config) {
    config = newConfig
  }

  /// Called every time UsageMonitor emits a new state.
  /// Evaluates whether any threshold has been newly crossed.
  func evaluate(state: UsageMonitor.State) {
    guard config.enabled, let snapshot = state.snapshot else { return }

    let primary = snapshot.rateLimit.primaryWindow
    let primaryKey = "primary-\(Int(primary.resetAt))"
    checkAndNotify(
      windowLabel: "5h 主配额",
      remaining: primary.remainingPercent,
      key: primaryKey
    )

    if let weekly = snapshot.rateLimit.secondaryWindow {
      let weeklyKey = "weekly-\(Int(weekly.resetAt))"
      checkAndNotify(
        windowLabel: "周配额",
        remaining: weekly.remainingPercent,
        key: weeklyKey
      )
    }
  }

  /// Reset fired alerts (e.g. when switching accounts).
  func resetFiredAlerts() {
    firedAlerts.removeAll()
  }

  // MARK: - Private

  private func checkAndNotify(windowLabel: String, remaining: Double, key: String) {
    let remainingInt = Int(remaining.rounded())

    // Exhausted
    if remaining <= 0 {
      if config.notifyOnExhausted && firedAlerts[key] != 0 {
        firedAlerts[key] = 0
        sendNotification(
          title: "\(windowLabel) 已耗尽",
          body: Copy.alertExhaustedBody,
          urgency: .critical
        )
      }
      return
    }

    // Find the highest threshold that remaining% has dropped below
    let sortedThresholds = config.thresholds.sorted(by: >)
    for threshold in sortedThresholds {
      if remainingInt <= threshold {
        let lastFired = firedAlerts[key]
        // Only fire if we haven't already fired for this threshold or a lower one
        if lastFired == nil || lastFired! > threshold {
          firedAlerts[key] = threshold
          let urgency: NotificationUrgency = threshold <= 5 ? .critical : (threshold <= 15 ? .warning : .info)
          sendNotification(
            title: "\(windowLabel) 剩余 \(remainingInt)%",
            body: urgencyBody(remaining: remainingInt, windowLabel: windowLabel),
            urgency: urgency
          )
        }
        break
      }
    }
  }

  private func urgencyBody(remaining: Int, windowLabel: String) -> String {
    if remaining <= 5 {
      return "即将耗尽，建议切换账号"
    }
    if remaining <= 15 {
      return "较低，注意控制用量"
    }
    if remaining <= 30 {
      return "\(windowLabel)已消耗过半，关注余量"
    }
    return "\(windowLabel)剩余 \(remaining)%"
  }

  private enum NotificationUrgency {
    case info, warning, critical
  }

  private func sendNotification(title: String, body: String, urgency: NotificationUrgency) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    if config.playSound {
      content.sound = urgency == .critical ? .defaultCritical : .default
    }
    // Category for potential future actions (e.g. "Switch Account")
    content.categoryIdentifier = "QUOTA_ALERT"

    let request = UNNotificationRequest(
      identifier: "quota-\(title)-\(Date().timeIntervalSince1970)",
      content: content,
      trigger: nil // deliver immediately
    )

    UNUserNotificationCenter.current().add(request) { error in
      if let error {
        print("[AlertManager] notification error: \(error.localizedDescription)")
      }
    }
  }

  private func requestNotificationPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      if let error {
        print("[AlertManager] permission error: \(error.localizedDescription)")
      }
    }
    registerNotificationCategories()
  }

  private func registerNotificationCategories() {
    let undoAction = UNNotificationAction(
      identifier: "UNDO_SWITCH",
      title: Copy.autoSwitchUndoAction,
      options: [.foreground]
    )
    let autoSwitchCategory = UNNotificationCategory(
      identifier: "AUTO_SWITCH",
      actions: [undoAction],
      intentIdentifiers: [],
      options: []
    )
    let quotaCategory = UNNotificationCategory(
      identifier: "QUOTA_ALERT",
      actions: [],
      intentIdentifiers: [],
      options: []
    )
    UNUserNotificationCenter.current().setNotificationCategories([autoSwitchCategory, quotaCategory])
  }

  /// Send auto-switch notification with Undo action button
  func sendAutoSwitchNotification(fromName: String, toName: String, reason: String) {
    let content = UNMutableNotificationContent()
    content.title = Copy.autoSwitchNotifyTitle(to: toName)
    content.body = Copy.autoSwitchNotifyBody(from: fromName, to: toName, reason: reason)
    content.sound = .default
    content.categoryIdentifier = "AUTO_SWITCH"

    let request = UNNotificationRequest(
      identifier: "auto-switch-\(Date().timeIntervalSince1970)",
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request) { error in
      if let error {
        print("[AlertManager] auto-switch notification error: \(error.localizedDescription)")
      }
    }
  }

  // MARK: - Persistence

  private func saveConfig() {
    guard let data = try? JSONEncoder().encode(config) else { return }
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
