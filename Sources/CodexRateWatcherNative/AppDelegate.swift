import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let popover = NSPopover()
  private var statusItem: NSStatusItem!
  private let monitor = UsageMonitor()
  private var observerID: UUID?
  private let windowMode: Bool
  private var debugWindow: NSWindow?

  init(windowMode: Bool = false) {
    self.windowMode = windowMode
    super.init()
  }

  // MARK: - Lifecycle

  func applicationDidFinishLaunching(_ notification: Notification) {
    // ── Build standard main menu (for keyboard shortcuts) ──
    buildMainMenu()

    let viewController = PopoverViewController(monitor: monitor)

    if windowMode {
      // ── Standalone window mode (for debugging / screenshots) ──
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
      // ── Normal menu bar mode ──
      NSApp.setActivationPolicy(.accessory)

      popover.behavior = .transient
      popover.animates = true
      popover.contentSize = NSSize(width: 860, height: 580)
      popover.contentViewController = viewController

      statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      if let button = statusItem.button {
        button.image = NSImage(
          systemSymbolName: "speedometer",
          accessibilityDescription: "Rate limits"
        )
        button.imagePosition = .imageLeading
        button.title = "Codex 额度"
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
      }
    }

    // ── Monitor ──
    observerID = monitor.addObserver { [weak self] state in
      DispatchQueue.main.async { self?.renderMenuBar(state: state) }
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
    // In window mode, quit when window is closed
    return windowMode
  }

  // MARK: - Status Item Click

  @objc private func handleStatusItemClick(_ sender: AnyObject?) {
    guard let button = statusItem?.button,
          let event = NSApp.currentEvent else { return }

    if event.type == .rightMouseUp {
      // Right-click → show context menu
      let menu = buildStatusMenu()
      statusItem.menu = menu
      statusItem.button?.performClick(nil)
      // Reset to nil so left-click works next time
      statusItem.menu = nil
    } else {
      // Left-click → toggle popover
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

    // Open popover
    let openItem = NSMenuItem(title: "打开面板", action: #selector(openPopover), keyEquivalent: "o")
    openItem.target = self
    menu.addItem(openItem)

    // Refresh
    let refreshItem = NSMenuItem(title: "立即刷新", action: #selector(refreshNow), keyEquivalent: "r")
    refreshItem.target = self
    menu.addItem(refreshItem)

    menu.addItem(NSMenuItem.separator())

    // About
    let aboutItem = NSMenuItem(title: "关于 Codex Rate Watcher", action: #selector(showAbout), keyEquivalent: "")
    aboutItem.target = self
    menu.addItem(aboutItem)

    menu.addItem(NSMenuItem.separator())

    // Quit
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

  @objc private func showAbout() {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(nil)
    // Go back to accessory after a delay (only in non-window mode)
    if !windowMode {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        NSApp.setActivationPolicy(.accessory)
      }
    }
  }

  @objc private func quitApp() {
    NSApp.terminate(nil)
  }

  // MARK: - Main Menu (for ⌘Q keyboard shortcut)

  private func buildMainMenu() {
    let mainMenu = NSMenu()

    // ── App menu ──
    let appMenu = NSMenu()
    let appMenuItem = NSMenuItem()
    appMenuItem.submenu = appMenu

    appMenu.addItem(withTitle: "关于 Codex Rate Watcher", action: #selector(showAbout), keyEquivalent: "")
    appMenu.addItem(NSMenuItem.separator())
    appMenu.addItem(withTitle: "退出 Codex Rate Watcher", action: #selector(quitApp), keyEquivalent: "q")

    mainMenu.addItem(appMenuItem)

    // ── Edit menu (for standard text operations) ──
    let editMenu = NSMenu(title: "编辑")
    let editMenuItem = NSMenuItem()
    editMenuItem.submenu = editMenu

    editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

    mainMenu.addItem(editMenuItem)

    // ── Window menu ──
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
