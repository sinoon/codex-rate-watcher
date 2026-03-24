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

  static func profileHeader(available: Int, total: Int = 0) -> String {
    if available > 0 { return "Other Profiles · \(available) available" }
    if total > 0 { return "Other Profiles · none available" }
    return "No other profiles"
  }

  static func profileBlocked(resetAt: TimeInterval?, label: String) -> String {
    if let r = resetAt {
      return "\(label) · \(resetDate(r)) 重置"
    }
    return label
  }

  // MARK: - Auto-Switch

  static let autoSwitchEnabled = "自动切换已开启"
  static let autoSwitchDisabled = "自动切换已关闭"

  static func autoSwitchNotifyTitle(to name: String) -> String {
    "已自动切换到 \(name)"
  }
  static func autoSwitchNotifyBody(from: String, to: String, reason: String) -> String {
    "\(from) → \(to) · \(reason)"
  }
  static let autoSwitchUndoAction = "撤销切换"
  static let restartCodexAction = "重启 Codex"
  static let restartCodexHint = "请重启 Codex 以使用新账号"
  static let autoSwitchMenuLabel = "自动切换账号"
  static let autoSwitchCooldown = "冷却中，稍后再试"


  // MARK: - Device Code Login

  static let addAccount = "添加账号"
  static let deviceCodeTitle = "登录 Codex 账号"
  static func deviceCodeMessage(code: String) -> String {
    "请在浏览器中输入以下验证码完成登录：\n\n\(code)\n\n点击下方按钮自动复制验证码并打开浏览器。"
  }
  static let deviceCodeCopyAndOpen = "复制验证码并打开浏览器"
  static let deviceCodeCancel = "取消"
  static let deviceCodeSuccess = "新账号登录成功"
  static func deviceCodeSuccessBody(email: String?) -> String {
    if let e = email { return "\(e) 已登录并自动注册到账号列表" }
    return "新账号已登录并注册到账号列表"
  }
  static let deviceCodeFailed = "登录失败"
  static let deviceCodeRequestingCode = "正在获取验证码…"


  // MARK: - Relay Plan

  static let relaySectionTitle = "Relay Plan"

  static func relayCoverage(duration: String, legCount: Int) -> String {
    "\(legCount) 账号接力 · 覆盖 \(duration)"
  }

  static func relayLegLabel(name: String, duration: String, remaining: Int) -> String {
    "\(name) · \(remaining)% · \(duration)"
  }

  static func relaySurvive(resetTime: String) -> String {
    "✅ 可撑到 \(resetTime) 重置"
  }

  static func relayGap(exhaustTime: String, resetTime: String, gap: String) -> String {
    "⚠️ \(exhaustTime) 全部耗尽 · \(resetTime) 重置 · 缺口 \(gap)"
  }

  static let relayNoAccounts = "无可用账号参与接力"

  static let relayAllExhausted = "所有账号均已耗尽"

  static func relayAutoNotifyTitle(to name: String) -> String {
    "接力切换到 \(name)"
  }

  static func relayAutoNotifyBody(from: String, to: String, coverage: String) -> String {
    "\(from) 即将耗尽 → 切到 \(to) · 剩余接力 \(coverage)"
  }

  static let relayAutoLabel = "智能接力"

  static func relayMenuBarSurvive(legCount: Int) -> String {
    "✓ \(legCount)号接力"
  }

  static func relayMenuBarGap(gap: String) -> String {
    "缺口 \(gap)"
  }

  // MARK: - Cost Dashboard

  static let costSectionTitle = "COST INSIGHT"

  static func costPerHour(_ usd: Double) -> String {
    "$\(String(format: "%.2f", usd))/hr"
  }

  static func costToday(_ usd: Double) -> String {
    "$\(String(format: "%.1f", usd)) today"
  }

  static func costUtilization(_ pct: Double) -> String {
    "\(Int((pct * 100).rounded()))% util"
  }

  static func costSubscription(plan: String, monthly: Double) -> String {
    "\(plan) · $\(Int(monthly))/mo"
  }

  static func costMonthUsed(_ usd: Double) -> String {
    "本月已用 $\(String(format: "%.1f", usd))"
  }

  static func costProjectedMonthly(_ usd: Double) -> String {
    "月度预计 $\(String(format: "%.0f", usd))"
  }

  static func costActiveHours(_ hours: Double) -> String {
    "活跃 \(String(format: "%.1f", hours))h"
  }

  static func costBudgetAlert(daily: Double, actual: Double) -> String {
    "日花费 $\(String(format: "%.1f", actual)) 已超预算 $\(String(format: "%.1f", daily))"
  }

  static let costNoBurnRate = "采样中"

  static func costMenuBar(pct: Int, costHr: Double) -> String {
    "\(pct)% · $\(String(format: "%.1f", costHr))/h"
  }

}
