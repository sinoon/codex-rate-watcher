import Foundation

// MARK: - Centralized Copy (文案统一管理)
//
// All user-facing strings live here. This keeps every other file free of
// hard-coded Chinese text and makes localization trivial later.
//
// Rules:
//   1. One concept, one wording — never say the same thing two ways.
//   2. Omit what context already tells the user (e.g. "周额度" inside a Weekly row).
//   3. Hero area = full sentence; secondary area = keywords only.
//   4. Use "·" as a lightweight separator, never "，".

enum Copy {

  // MARK: - Duration formatting

  /// Compact duration: "2h10m", "45m", "3天2h"
  static func duration(_ interval: TimeInterval) -> String {
    let totalMinutes = max(0, Int(interval / 60))
    let days = totalMinutes / (60 * 24)
    let hours = (totalMinutes % (60 * 24)) / 60
    let minutes = totalMinutes % 60

    if days > 0 {
      return hours > 0 ? "\(days)天\(hours)h" : "\(days)天"
    }
    if hours > 0 {
      return minutes > 0 ? "\(hours)h\(minutes)m" : "\(hours)h"
    }
    return "\(max(1, minutes))m"
  }

  /// Compact date: "16:09" (today) / "明天 14:30" / "3/22"
  static func resetDate(_ resetAt: TimeInterval) -> String {
    let date = Date(timeIntervalSince1970: resetAt)
    let cal = Calendar.current
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "zh_Hans_CN")

    if cal.isDateInToday(date) {
      fmt.dateFormat = "HH:mm"
      return fmt.string(from: date)
    }
    if cal.isDateInTomorrow(date) {
      fmt.dateFormat = "HH:mm"
      return "明天 \(fmt.string(from: date))"
    }
    fmt.dateFormat = "M/d"
    return fmt.string(from: date)
  }

  // MARK: - Primary Hero Area

  /// "≈1h52m 可用 · 16:09 重置"
  static func heroBurn(timeLeft: TimeInterval?, resetAt: TimeInterval) -> String {
    let reset = resetDate(resetAt)
    if let t = timeLeft {
      return "≈\(duration(t)) 可用 · \(reset) 重置"
    }
    return "\(reset) 重置"
  }

  /// "已耗尽 · 16:09 重置"
  static func heroExhausted(resetAt: TimeInterval) -> String {
    "已耗尽 · \(resetDate(resetAt)) 重置"
  }

  /// "周额度耗尽 · 3/22 重置"
  static func heroWeeklyExhausted(resetAt: TimeInterval) -> String {
    "周额度耗尽 · \(resetDate(resetAt)) 重置"
  }

  // MARK: - Other Quotas Detail (compact)

  /// "≈2h10m 可用 · 3/22 重置"
  static func quotaBurn(timeLeft: TimeInterval?, resetAt: TimeInterval) -> String {
    let reset = resetDate(resetAt)
    if let t = timeLeft {
      return "≈\(duration(t)) · \(reset) 重置"
    }
    return "\(reset) 重置"
  }

  /// For review estimate which has no reset time
  static func reviewBurn(timeLeft: TimeInterval?) -> String {
    if let t = timeLeft {
      return "≈\(duration(t)) 可用"
    }
    return ""
  }

  // MARK: - Estimate Status (very short)

  static let sampling     = "采样中"
  static let estimating   = "估算中"
  static let stable       = "平稳"
  static let sufficient   = "充足"
  static func ratePerHour(_ pctPerHour: Double) -> String {
    "≈\(pctPerHour.formatted(.number.precision(.fractionLength(1))))%/h"
  }
  

  // MARK: - Badge / Status

  static let exhausted    = "已耗尽"
  static let runningLow   = "即将耗尽"
  static let unavailable  = "不可用"
  static let available    = "可用"
  static let syncing      = "同步中"
  static let validating   = "校验中"
  static let resetting    = "重置中"

  // MARK: - Menu Bar

  /// "44% · 2 备选"
  static func menuBarNormal(pct: Int, altCount: Int) -> String {
    altCount > 0 ? "\(pct)% · \(altCount) 备选" : "\(pct)%"
  }

  static func menuBarUnavailable(altCount: Int) -> String {
    altCount > 0 ? "不可用 · \(altCount) 备选" : "不可用"
  }

  static let menuBarDefault = "Codex"

  // MARK: - Footer

  static let footerAutoRefresh   = "每分钟自动刷新"
  static let footerHasCredits    = "有 credits 兜底"
  static let footerThrottled     = "当前账号被限流，建议切换"

  static func footerExhausted(label: String, resetAt: TimeInterval) -> String {
    "\(label)耗尽 · \(resetDate(resetAt)) 重置"
  }

  // MARK: - Recommendation

  static let recComputing       = "正在计算"
  static let recComputingDetail = "首轮校验完成后给出建议"
  static let recNoAvailable     = "无更优账号"
  static let recStayLow         = "当前最优，准备下一跳"
  static let recStay            = "继续用当前账号"
  static let recNoSwitch        = "暂不需要切换"

  static func recSwitch(to name: String) -> String {
    "建议切到 \(name)"
  }

  static func stayDetail(current: String, backup: (name: String, summary: String)?, isLow: Bool) -> String {
    if isLow, let b = backup {
      return "余量低 · 用完切 \(b.name) (\(b.summary))"
    }
    if let b = backup {
      return "当前最优 · 备选 \(b.name) (\(b.summary))"
    }
    return "当前最优 · \(current)"
  }

  static func switchDetail(
    recommended: String, recommendedSummary: String,
    current: String?, currentSummary: String?,
    backup: (name: String, summary: String)?
  ) -> String {
    var parts: [String] = ["\(recommended) 余量最多 (\(recommendedSummary))"]
    if let c = current, let cs = currentSummary {
      parts.append("当前 \(c) \(cs)")
    }
    if let b = backup {
      parts.append("备选 \(b.name) (\(b.summary))")
    }
    return parts.joined(separator: " · ")
  }

  // MARK: - Alerts

  static func alertExhausted(window: String) -> String {
    "\(window)已耗尽"
  }

  static let alertExhaustedBody = "额度用完，等待重置或切换账号"

  static func alertLow(window: String, pct: Int) -> String {
    "\(window)剩余 \(pct)%"
  }

  static func alertUrgencyBody(pct: Int, window: String) -> String {
    if pct <= 5 { return "即将耗尽，建议立即切换账号" }
    if pct <= 15 { return "较低，注意控制用量" }
    if pct <= 50 { return "\(window)已消耗过半，关注余量" }
    return "\(window)剩余 \(pct)%"
  }

  // MARK: - Profile list

  static func profileHeader(available: Int) -> String {
    available > 0 ? "Other Profiles · \(available) available" : "No other profiles"
  }

  static func profileBlocked(resetAt: TimeInterval?, label: String) -> String {
    if let r = resetAt {
      return "\(label) · \(resetDate(r)) 重置"
    }
    return label
  }
}
