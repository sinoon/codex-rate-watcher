import AppKit

enum AppPresentationPolicy {
  static func activationPolicyForDashboard(windowMode: Bool) -> NSApplication.ActivationPolicy {
    windowMode ? .regular : .accessory
  }
}
