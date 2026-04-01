import Foundation

public enum TokenCostFormatting {
  public static func usd(_ value: Double, minimumFractionDigits: Int = 2, maximumFractionDigits: Int = 2) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.currencySymbol = "$"
    formatter.minimumFractionDigits = minimumFractionDigits
    formatter.maximumFractionDigits = maximumFractionDigits
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
  }

  public static func tokenCount(_ count: Int) -> String {
    let absolute = Double(abs(count))
    let sign = count < 0 ? "-" : ""

    switch absolute {
    case 1_000_000_000...:
      return sign + String(format: "%.1fB", absolute / 1_000_000_000)
    case 1_000_000...:
      return sign + String(format: "%.1fM", absolute / 1_000_000)
    case 1_000...:
      return sign + String(format: "%.1fK", absolute / 1_000)
    default:
      return "\(count)"
    }
  }
}
