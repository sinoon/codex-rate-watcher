import AppKit
import UserNotifications
import ServiceManagement
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
  private let codexConfigManager = CodexConfigManager()

  /// Launch at Login via SMAppService (macOS 13+)
  var launchAtLoginEnabled: Bool {
    SMAppService.mainApp.status == .enabled
  }
  private var proxyTask: Task<Void, Never>?
  private var proxyServer: ProxyServer?
  private var proxyStatusTimer: Timer?
  private var addAccountTask: Task<Void, Never>?

  init(windowMode: Bool = false) {
    self.windowMode = windowMode
    super.init()
  }

  // MARK: - Lifecycle

  func applicationDidFinishLaunching(_ notification: Notification) {
    if Bundle.main.bundleIdentifier != nil {
      UNUserNotificationCenter.current().delegate = self
    }
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
      popover.contentSize = NSSize(width: 400, height: 10)  // initial; PopoverVC adjusts via preferredContentSize
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

    monitor.start()

    // Auto-start proxy if current mode is proxy
    if codexConfigManager.currentMode() == .proxy {
      startProxyServer()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    if let observerID {
      monitor.removeObserver(observerID)
      self.observerID = nil
    }
    monitor.stop()
    stopProxyServer()
    addAccountTask?.cancel()
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
    guard let _ = statusItem?.button,
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

    // Codex mode toggle
    let currentMode = codexConfigManager.currentMode()
    let modeEmoji = currentMode == .proxy ? "🌐" : "⚡️"
    let modeText = currentMode == .proxy ? "Codex 模式：代理" : "Codex 模式：直连"
    let modeToggle = NSMenuItem(title: "\(modeEmoji) \(modeText)", action: #selector(toggleCodexMode), keyEquivalent: "")
    modeToggle.target = self
    menu.addItem(modeToggle)

    let addAccountItem = NSMenuItem(title: Copy.addAccount, action: #selector(startAddAccountFlow), keyEquivalent: "")
    addAccountItem.target = self
    menu.addItem(addAccountItem)

    // Launch at Login toggle
    let launchLabel = launchAtLoginEnabled
      ? Copy.launchAtLoginOn
      : Copy.launchAtLoginOff
    let launchItem = NSMenuItem(title: launchLabel, action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    launchItem.target = self
    menu.addItem(launchItem)

    menu.addItem(NSMenuItem.separator())

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

  @objc private func toggleLaunchAtLogin() {
    do {
      if launchAtLoginEnabled {
        try SMAppService.mainApp.unregister()
        NSLog("[LaunchAtLogin] disabled")
      } else {
        try SMAppService.mainApp.register()
        NSLog("[LaunchAtLogin] enabled")
      }
    } catch {
      NSLog("[LaunchAtLogin] toggle failed: \(error.localizedDescription)")
    }
  }

  @objc private func toggleCodexMode() {
    do {
      if codexConfigManager.currentMode() == .proxy {
        try codexConfigManager.switchToDirect()
        stopProxyServer()
      } else {
        try codexConfigManager.switchTo(proxy: 19876)
        startProxyServer()
      }
      if let vc = popover.contentViewController as? PopoverViewController {
        vc.refreshModeFromExternal()
      }
    } catch {
      NSLog("[ModeToggle] toggle failed: \(error.localizedDescription)")
    }
  }

  /// Called by PopoverViewController when user toggles mode in the UI.
  func handleModeSwitch(toProxy: Bool) {
    if toProxy {
      startProxyServer()
    } else {
      stopProxyServer()
    }
  }

  // MARK: - Proxy Lifecycle

  private func startProxyServer() {
    guard proxyTask == nil else { return }
    let config = ProxyServer.Config(port: 19876)
    let server = ProxyServer(config: config)
    proxyServer = server
    proxyTask = Task.detached {
      do {
        try await server.run()
      } catch {
        NSLog("[Proxy] server stopped: \(error.localizedDescription)")
      }
    }
    NSLog("[Proxy] started on :19876")
    // Start status polling
    startProxyStatusPolling()
  }

  private func stopProxyServer() {
    proxyStatusTimer?.invalidate()
    proxyStatusTimer = nil
    proxyTask?.cancel()
    proxyTask = nil
    proxyServer = nil
    NSLog("[Proxy] stopped")
    // Update popover
    if let vc = popover.contentViewController as? PopoverViewController {
      vc.updateProxyStatus(running: false, stats: nil)
    }
  }

  private func startProxyStatusPolling() {
    proxyStatusTimer?.invalidate()
    proxyStatusTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor in
        let running = await ProxyServer.healthCheck(port: 19876)
        let stats = self.proxyServer?.stats
        if let vc = self.popover.contentViewController as? PopoverViewController {
          vc.updateProxyStatus(running: running, stats: stats)
        }
        // Auto-restart if proxy died but mode is still proxy
        if !running && self.codexConfigManager.currentMode() == .proxy && self.proxyTask != nil {
          NSLog("[Proxy] detected crash, restarting...")
          self.proxyTask?.cancel()
          self.proxyTask = nil
          self.proxyServer = nil
          self.startProxyServer()
        }
      }
    }
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


  // MARK: - Managed Account Login

  @objc func startAddAccountFlow() {
    guard addAccountTask == nil else {
      return
    }

    sendUserNotification(
      identifier: "managed-account-login-started",
      title: Copy.addAccountStartedTitle,
      body: Copy.addAccountStartedBody
    )

    addAccountTask = Task { [weak self] in
      guard let self else { return }
      defer { self.addAccountTask = nil }

      do {
        let account = try await monitor.addManagedAccount(timeout: 300)
        NSLog("[ManagedAccountLogin] Added account: \(account.email)")
        sendUserNotification(
          identifier: "managed-account-login-success",
          title: Copy.addAccountSuccess,
          body: Copy.addAccountSuccessBody(email: account.email)
        )
      } catch is CancellationError {
        return
      } catch {
        NSLog("[ManagedAccountLogin] Error: \(error.localizedDescription)")
        sendUserNotification(
          identifier: "managed-account-login-failed",
          title: Copy.addAccountFailed,
          body: error.localizedDescription
        )

        if !windowMode {
          NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)

        let errorAlert = NSAlert()
        errorAlert.messageText = Copy.addAccountFailed
        errorAlert.informativeText = error.localizedDescription
        errorAlert.alertStyle = .warning
        errorAlert.addButton(withTitle: "好")
        errorAlert.runModal()

        if !windowMode {
          NSApp.setActivationPolicy(.accessory)
        }
      }
    }
  }

  private func sendUserNotification(identifier: String, title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default

    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    Task {
      try? await UNUserNotificationCenter.current().add(request)
    }
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

    let modePrefix = codexConfigManager.currentMode() == .proxy ? "🌐 " : ""

    guard let snapshot = state.snapshot else {
      button.title = modePrefix + Copy.menuBarDefault
      return
    }

    if let weeklyWindow = snapshot.rateLimit.secondaryWindow,
       weeklyWindow.remainingPercent <= 0 {
      button.title = modePrefix + Copy.menuBarUnavailable(altCount: state.availableProfileCount)
      return
    }

    if !snapshot.rateLimit.allowed || snapshot.rateLimit.limitReached
        || snapshot.rateLimit.primaryWindow.remainingPercent <= 0 {
      button.title = modePrefix + Copy.menuBarUnavailable(altCount: state.availableProfileCount)
      return
    }

    let primary = snapshot.rateLimit.primaryWindow
    let plan = state.relayPlan
    if plan.legs.count > 1 {
      let pct = Int(primary.remainingPercent.rounded())
      if plan.canSurviveUntilReset {
        button.title = modePrefix + "\(pct)% \(Copy.relayMenuBarSurvive(legCount: plan.legCount))"
      } else if let gapSecs = plan.gapToResetSeconds {
        button.title = modePrefix + "\(pct)% \(Copy.relayMenuBarGap(gap: Copy.duration(abs(gapSecs))))"
      } else {
        button.title = modePrefix + Copy.menuBarNormal(pct: pct, altCount: state.availableProfileCount)
      }
    } else {
      // Show cost rate on menu bar when burn rate is known
      if let liveCost = state.liveCost, let cph = liveCost.costPerHour, cph > 0 {
        let pct = Int(primary.remainingPercent.rounded())
        button.title = modePrefix + Copy.costMenuBar(pct: pct, costHr: cph)
      } else {
        button.title = modePrefix + Copy.menuBarNormal(pct: Int(primary.remainingPercent.rounded()), altCount: state.availableProfileCount)
      }
    }
  }
}


// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: @preconcurrency UNUserNotificationCenterDelegate {

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Show notification banner even when app is in foreground
    completionHandler([.banner, .sound])
  }
}
