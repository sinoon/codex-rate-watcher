import AppKit

let app = NSApplication.shared

// --window mode: standalone window for debugging (screenshotable)
let useWindowMode = CommandLine.arguments.contains("--window")

let delegate = AppDelegate(windowMode: useWindowMode)
app.delegate = delegate
app.run()
