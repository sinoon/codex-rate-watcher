import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let popover = NSPopover()
  private var statusItem: NSStatusItem!
  private let monitor = UsageMonitor()
  private var observerID: UUID?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    let viewController = PopoverViewController(monitor: monitor)
    popover.behavior = .transient
    popover.animates = true
    popover.contentSize = NSSize(width: 860, height: 580)
    popover.contentViewController = viewController

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = statusItem.button {
      button.image = NSImage(systemSymbolName: "speedometer", accessibilityDescription: "Rate limits")
      button.imagePosition = .imageLeading
      button.title = "Codex 额度"
      button.font = .systemFont(ofSize: 13, weight: .semibold)
      button.target = self
      button.action = #selector(togglePopover(_:))
    }

    observerID = monitor.addObserver { [weak self] state in
      DispatchQueue.main.async {
        self?.renderMenuBar(state: state)
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

  @objc
  private func togglePopover(_ sender: AnyObject?) {
    guard let button = statusItem.button else { return }

    if popover.isShown {
      popover.performClose(sender)
    } else {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      popover.contentViewController?.view.window?.makeKey()
    }
  }

  private func renderMenuBar(state: UsageMonitor.State) {
    guard let button = statusItem.button else { return }
    guard let snapshot = state.snapshot else {
      button.title = "Codex 额度"
      return
    }

    if let weeklyWindow = snapshot.rateLimit.secondaryWindow, weeklyWindow.remainingPercent <= 0 {
      button.title = "不可用 · \(state.availableProfileCount) 个可切"
      return
    }

    if !snapshot.rateLimit.allowed || snapshot.rateLimit.limitReached || snapshot.rateLimit.primaryWindow.remainingPercent <= 0 {
      button.title = "不可用 · \(state.availableProfileCount) 个可切"
      return
    }

    let primary = snapshot.rateLimit.primaryWindow
    button.title = "还剩 \(Int(primary.remainingPercent.rounded()))% · \(state.availableProfileCount) 个可切"
  }
}
