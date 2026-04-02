import AppKit

let app = NSApplication.shared

// --window mode: standalone window for debugging (screenshotable)
let useWindowMode = CommandLine.arguments.contains("--window")
let openDashboardOnLaunch = CommandLine.arguments.contains("--dashboard")

let delegate = AppDelegate(
  windowMode: useWindowMode,
  openDashboardOnLaunch: openDashboardOnLaunch
)
app.delegate = delegate
app.run()
