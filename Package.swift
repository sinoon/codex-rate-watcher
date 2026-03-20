// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CodexRateWatcherNative",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "CodexRateKit", targets: ["CodexRateKit"]),
    .executable(name: "CodexRateWatcherNative", targets: ["CodexRateWatcherNative"]),
    .executable(name: "codex-rate", targets: ["codex-rate"]),
  ],
  targets: [
    // Shared library — no AppKit, no UserNotifications
    .target(
      name: "CodexRateKit",
      path: "Sources/CodexRateKit"
    ),
    // GUI app — AppKit-based menu bar app
    .executableTarget(
      name: "CodexRateWatcherNative",
      dependencies: ["CodexRateKit"],
      linkerSettings: [.linkedFramework("AppKit")]
    ),
    // CLI tool — terminal-based quota checker
    .executableTarget(
      name: "codex-rate",
      dependencies: ["CodexRateKit"],
      path: "Sources/codex-rate"
    ),
    // Tests for the shared library
    .testTarget(
      name: "CodexRateKitTests",
      dependencies: ["CodexRateKit"]
    ),
  ]
)
