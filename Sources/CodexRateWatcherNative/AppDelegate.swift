import AppKit
import UserNotifications
import CodexRateKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let popover = NSPopover()
  private var statusItem: NSStatusItem!
  private let monitor = UsageMonitor()
  private let alertManager = AlertManager()
  private var observerID: UUID?
  private let windowMode: Bool
  private var debugWindow: NSWindow?
  private var currentTier: StatusBarIcon.Tier = .unknown
  private var hotkeyManager: HotkeyManager?
  private var autoSwitchMenuItem: NSMenuItem?

  init(windowMode: Bool = false) {
    self.windowMode = windowMode
    super.init()
  }

  // MARK: - Lifecycle

  func applicationDidFinishLaunching(_ notification: Notification) {
    UNUserNotificationCenter.current().delegate = self
    buildMainMenu()

    let viewController = PopoverViewController(monitor: monitor)

    if windowMode {
      NSApp.setActivationPolicy(.regular)

      let windowSize = NSSize(width: 380, height: 580)
      let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: windowSize),
        styleMask: [.titled, .closable, .miniaturizable],
        backing: .buffered,
        defer: false
      )
      window.title = "Codex Rate Watcher (Debug)"
      window.contentViewController = viewController
      window.isReleasedWhenClosed = false
      window.backgroundColor = NSColor(srgbRed: 0.047, green: 0.051, blue: 0.063, alpha: 1)
      window.center()
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      debugWindow = window
    } else {
      NSApp.setActivationPolicy(.accessory)

      popover.behavior = .transient
      popover.animates = true
      popover.contentSize = NSSize(width: 860, height: 580)
      popover.contentViewController = viewController

      statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      if let button = statusItem.button {
        button.image = StatusBarIcon.icon(for: .unknown)
        button.imagePosition = .imageLeading
        button.title = Copy.menuBarDefault
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
      }
    }

    observerID = monitor.addObserver { [weak self] state in
      DispatchQueue.main.async {
        self?.renderMenuBar(state: state)
        self?.alertManager.evaluate(state: state)
      }
    }
    // Wire auto-switch notification
    monitor.onAutoSwitch = { [weak self] fromName, toName, reason in
      self?.alertManager.sendAutoSwitchNotification(fromName: fromName, toName: toName, reason: reason)
    }

    monitor.start()

    // Set up global hotkey (⇧⌃⌥K by default)
    if !windowMode {
      let hk = HotkeyManager()
      hk.onToggle = { [weak self] in
        self?.togglePopover()
      }
      hk.onConflict = { info in
        NSLog("[Hotkey] ⚠️ \(info.shortcut) \(info.message)")
      }
      hotkeyManager = hk
      NSLog("[AppDelegate] Hotkey registered: \(hk.config.displayString)")
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    if let observerID {
      monitor.removeObserver(observerID)
      self.observerID = nil
    }
    monitor.stop()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return windowMode
  }

  // MARK: - Popover Toggle

  private func togglePopover() {
    guard let button = statusItem?.button else { return }
    if popover.isShown {
      popover.performClose(nil)
    } else {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      popover.contentViewController?.view.window?.makeKey()
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  // MARK: - Status Item Click

  @objc private func handleStatusItemClick(_ sender: AnyObject?) {
    guard let button = statusItem?.button,
          let event = NSApp.currentEvent else { return }

    if event.type == .rightMouseUp {
      let menu = buildStatusMenu()
      statusItem.menu = menu
      statusItem.button?.performClick(nil)
      statusItem.menu = nil
    } else {
      togglePopover()
    }
  }

  // MARK: - Status Item Context Menu

  private func buildStatusMenu() -> NSMenu {
    let menu = NSMenu()

    let openItem = NSMenuItem(title: "打开面板", action: #selector(openPopover), keyEquivalent: "o")
    openItem.target = self
    menu.addItem(openItem)

    let refreshItem = NSMenuItem(title: "立即刷新", action: #selector(refreshNow), keyEquivalent: "r")
    refreshItem.target = self
    menu.addItem(refreshItem)

    menu.addItem(NSMenuItem.separator())

    let alertLabel = alertManager.config.enabled ? "🔔 通知预警：已开启" : "🔕 通知预警：已关闭"
    let alertToggle = NSMenuItem(title: alertLabel, action: #selector(toggleAlerts), keyEquivalent: "")
    alertToggle.target = self
    menu.addItem(alertToggle)

    let soundLabel = alertManager.config.playSound ? "🔊 提示音：已开启" : "🔇 提示音：已关闭"
    let soundToggle = NSMenuItem(title: soundLabel, action: #selector(toggleAlertSound), keyEquivalent: "")
    soundToggle.target = self
    menu.addItem(soundToggle)

    menu.addItem(NSMenuItem.separator())

    let hotkeyLabel = hotkeyManager?.config.enabled == true
      ? "⌨️ 快捷键：\(hotkeyManager?.statusLine ?? "⇧⌃⌥K")"
      : "⌨️ 快捷键：已关闭"
    let hotkeyToggle = NSMenuItem(title: hotkeyLabel, action: #selector(toggleHotkey), keyEquivalent: "")
    hotkeyToggle.target = self
    menu.addItem(hotkeyToggle)

    let aboutItem = NSMenuItem(title: "关于 Codex Rate Watcher", action: #selector(showAbout), keyEquivalent: "")
    aboutItem.target = self
    menu.addItem(aboutItem)

    menu.addItem(NSMenuItem.separator())

    let quitItem = NSMenuItem(title: "退出 Codex Rate Watcher", action: #selector(quitApp), keyEquivalent: "q")
    quitItem.target = self
    menu.addItem(quitItem)

    return menu
  }

  @objc private func openPopover() {
    guard let button = statusItem?.button else { return }
    if !popover.isShown {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      popover.contentViewController?.view.window?.makeKey()
    }
  }

  @objc private func refreshNow() {
    Task { await monitor.refresh(manual: true) }
  }

  @objc private func toggleAlerts() {
    var config = alertManager.config
    config.enabled.toggle()
    alertManager.updateConfig(config)
  }

  @objc private func toggleAlertSound() {
    var config = alertManager.config
    config.playSound.toggle()
    alertManager.updateConfig(config)
  }

  @objc private func toggleAutoSwitch() {
    monitor.setAutoSwitch(enabled: !monitor.autoSwitchConfig.enabled)
    // Update menu item title
    autoSwitchMenuItem?.title = "\(Copy.autoSwitchMenuLabel)：\(monitor.autoSwitchConfig.enabled ? "已开启" : "已关闭")"
  }

  @objc private func toggleHotkey() {
    guard let hk = hotkeyManager else { return }
    var config = hk.config
    config.enabled.toggle()
    hk.updateConfig(config)
  }

  @objc private func showAbout() {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(nil)
    if !windowMode {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        NSApp.setActivationPolicy(.accessory)
      }
    }
  }

  @objc private func quitApp() {
    NSApp.terminate(nil)
  }

  // MARK: - Main Menu

  private func buildMainMenu() {
    let mainMenu = NSMenu()

    let appMenu = NSMenu()
    let appMenuItem = NSMenuItem()
    appMenuItem.submenu = appMenu

    appMenu.addItem(withTitle: "关于 Codex Rate Watcher", action: #selector(showAbout), keyEquivalent: "")
    appMenu.addItem(NSMenuItem.separator())
    appMenu.addItem(withTitle: "退出 Codex Rate Watcher", action: #selector(quitApp), keyEquivalent: "q")

    mainMenu.addItem(appMenuItem)

    let editMenu = NSMenu(title: "编辑")
    let editMenuItem = NSMenuItem()
    editMenuItem.submenu = editMenu

    editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

    mainMenu.addItem(editMenuItem)

    let windowMenu = NSMenu(title: "窗口")
    let windowMenuItem = NSMenuItem()
    windowMenuItem.submenu = windowMenu

    windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
    windowMenu.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

    mainMenu.addItem(windowMenuItem)

    NSApp.mainMenu = mainMenu
  }

  // MARK: - Menu Bar Render

  private func renderMenuBar(state: UsageMonitor.State) {
    guard let button = statusItem?.button else { return }

    let tier = StatusBarIcon.tier(for: state)
    if tier != currentTier {
      currentTier = tier
      button.image = StatusBarIcon.icon(for: tier)
    }

    guard let snapshot = state.snapshot else {
      button.title = Copy.menuBarDefault
      return
    }

    if let weeklyWindow = snapshot.rateLimit.secondaryWindow,
       weeklyWindow.remainingPercent <= 0 {
      button.title = Copy.menuBarUnavailable(altCount: state.availableProfileCount)
      return
    }

    if !snapshot.rateLimit.allowed || snapshot.rateLimit.limitReached
        || snapshot.rateLimit.primaryWindow.remainingPercent <= 0 {
      button.title = Copy.menuBarUnavailable(altCount: state.availableProfileCount)
      return
    }

    let primary = snapshot.rateLimit.primaryWindow
    button.title = Copy.menuBarNormal(pct: Int(primary.remainingPercent.rounded()), altCount: state.availableProfileCount)
  }
}


// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: @preconcurrency UNUserNotificationCenterDelegate {
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if response.actionIdentifier == "UNDO_SWITCH" {
      Task { @MainActor in
        await self.monitor.undoLastAutoSwitch()
      }
    }
    completionHandler()
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Show notification banner even when app is in foreground
    completionHandler([.banner, .sound])
  }
}
