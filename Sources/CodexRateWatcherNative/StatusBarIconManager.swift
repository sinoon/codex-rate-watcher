import AppKit

/// Manages dynamic menu-bar icon tinting based on quota health.
@MainActor
enum StatusBarIcon {

  // MARK: - Color tiers

  enum Tier: String {
    case healthy   // > 50 %
    case caution   // 15 – 50 %
    case warning   // 5 – 15 %
    case critical  // 0 – 5 %
    case exhausted // exactly 0 or blocked
    case unknown   // no data yet

    var color: NSColor {
      switch self {
      case .healthy:   return NSColor(srgbRed: 0.20, green: 0.83, blue: 0.47, alpha: 1)   // green
      case .caution:   return NSColor(srgbRed: 0.95, green: 0.77, blue: 0.06, alpha: 1)   // yellow
      case .warning:   return NSColor(srgbRed: 0.96, green: 0.52, blue: 0.07, alpha: 1)   // orange
      case .critical:  return NSColor(srgbRed: 0.95, green: 0.25, blue: 0.24, alpha: 1)   // red
      case .exhausted: return NSColor(srgbRed: 0.95, green: 0.25, blue: 0.24, alpha: 1)   // red
      case .unknown:   return NSColor(srgbRed: 0.56, green: 0.58, blue: 0.62, alpha: 1)   // gray
      }
    }
  }

  // MARK: - Tier resolution

  static func tier(for state: UsageMonitor.State) -> Tier {
    guard let snapshot = state.snapshot else { return .unknown }

    // Check weekly window first (it's the hard limit)
    if let weekly = snapshot.rateLimit.secondaryWindow,
       weekly.remainingPercent <= 0 {
      return .exhausted
    }

    // Check if rate-limited or blocked
    if !snapshot.rateLimit.allowed || snapshot.rateLimit.limitReached {
      return .exhausted
    }

    let remaining = snapshot.rateLimit.primaryWindow.remainingPercent

    if remaining <= 0  { return .exhausted }
    if remaining <= 5  { return .critical }
    if remaining <= 15 { return .warning }
    if remaining <= 50 { return .caution }
    return .healthy
  }

  // MARK: - Icon generation

  /// Returns a composite NSImage: SF Symbol "speedometer" + small colored dot.
  static func icon(for tier: Tier) -> NSImage {
    let size = NSSize(width: 20, height: 18)
    let img = NSImage(size: size, flipped: false) { rect in
      // Draw the base SF Symbol
      if let symbol = NSImage(systemSymbolName: "speedometer",
                              accessibilityDescription: "Rate limit status") {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let configured = symbol.withSymbolConfiguration(config) ?? symbol
        // Tint the symbol to match the tier
        let tinted = configured.tinted(with: tier.color)
        tinted.draw(in: NSRect(x: 0, y: 1, width: 18, height: 16))
      }

      // Draw the small status dot (top-right corner)
      let dotSize: CGFloat = 6
      let dotRect = NSRect(x: rect.width - dotSize, y: rect.height - dotSize, width: dotSize, height: dotSize)
      let dotPath = NSBezierPath(ovalIn: dotRect)
      tier.color.setFill()
      dotPath.fill()

      // Add a tiny dark border to the dot for contrast
      NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.3).setStroke()
      dotPath.lineWidth = 0.5
      dotPath.stroke()

      return true
    }
    img.isTemplate = false  // We handle our own coloring
    return img
  }
}

// MARK: - NSImage tinting helper

extension NSImage {
  func tinted(with color: NSColor) -> NSImage {
    let image = self.copy() as! NSImage
    image.lockFocus()
    color.set()
    let imageRect = NSRect(origin: .zero, size: image.size)
    imageRect.fill(using: .sourceAtop)
    image.unlockFocus()
    image.isTemplate = false
    return image
  }
}
