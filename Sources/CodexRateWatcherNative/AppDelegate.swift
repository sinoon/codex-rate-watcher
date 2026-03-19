import AppKit

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

  init(windowMode: Bool = false) {
    self.windowMode = windowMode
    super.init()
  }

  // MARK: - Lifecycle

  func applicationDidFinishLaunching(_ notification: Notification) {
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
        button.title = "Codex 额度"
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
      if popover.isShown {
        popover.performClose(sender)
      } else {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
      }
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
      button.title = "Codex 额度"
      return
    }

    if let weeklyWindow = snapshot.rateLimit.secondaryWindow,
       weeklyWindow.remainingPercent <= 0 {
      button.title = "不可用 · \(state.availableProfileCount) 个可切"
      return
    }

    if !snapshot.rateLimit.allowed || snapshot.rateLimit.limitReached
        || snapshot.rateLimit.primaryWindow.remainingPercent <= 0 {
      button.title = "不可用 · \(state.availableProfileCount) 个可切"
      return
    }

    let primary = snapshot.rateLimit.primaryWindow
    button.title = "还剩 \(Int(primary.remainingPercent.rounded()))% · \(state.availableProfileCount) 个可切"
  }
}
