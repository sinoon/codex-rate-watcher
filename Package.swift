// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "CodexRateWatcherNative",
  platforms: [
    .macOS(.v14)
  ],
  targets: [
    .executableTarget(
      name: "CodexRateWatcherNative",
      linkerSettings: [
        .linkedFramework("AppKit")
      ]
    )
  ]
)
