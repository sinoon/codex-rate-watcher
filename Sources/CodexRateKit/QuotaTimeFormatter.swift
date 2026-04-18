import Foundation

public enum ResetLabelStyle: Sendable {
  case compact
  case chineseMonthDay
}

public enum QuotaTimeFormatter {
  private static let locale = Locale(identifier: "zh_Hans_CN")

  public static func durationLabel(_ interval: TimeInterval) -> String {
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

  public static func resetLabel(
    for resetAt: TimeInterval,
    now: Date = Date(),
    timeZone: TimeZone = .autoupdatingCurrent,
    style: ResetLabelStyle = .compact
  ) -> String? {
    let date = Date(timeIntervalSince1970: resetAt)
    guard date > now else { return nil }

    let calendar = configuredCalendar(timeZone: timeZone)
    let formatter = configuredFormatter(timeZone: timeZone)

    if calendar.isDate(date, equalTo: now, toGranularity: .day) {
      formatter.dateFormat = "HH:mm"
      return formatter.string(from: date)
    }

    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
       calendar.isDate(date, equalTo: tomorrow, toGranularity: .day) {
      formatter.dateFormat = "HH:mm"
      return "明天 \(formatter.string(from: date))"
    }

    formatter.dateFormat = style == .compact ? "M/d HH:mm" : "M月d日 HH:mm"
    return formatter.string(from: date)
  }

  public static func resetCountdownLabel(
    for resetAt: TimeInterval,
    now: Date = Date(),
    timeZone: TimeZone = .autoupdatingCurrent,
    style: ResetLabelStyle = .compact
  ) -> String? {
    let date = Date(timeIntervalSince1970: resetAt)
    let remaining = date.timeIntervalSince(now)
    guard remaining > 0,
          let resetLabel = resetLabel(for: resetAt, now: now, timeZone: timeZone, style: style) else {
      return nil
    }

    return "\(resetLabel) 重置 · \(durationLabel(remaining))后"
  }

  public static func contextualResetCountdownLabel(
    context: String,
    for resetAt: TimeInterval,
    now: Date = Date(),
    timeZone: TimeZone = .autoupdatingCurrent,
    style: ResetLabelStyle = .compact
  ) -> String? {
    let date = Date(timeIntervalSince1970: resetAt)
    let remaining = date.timeIntervalSince(now)
    guard remaining > 0,
          let resetLabel = resetLabel(for: resetAt, now: now, timeZone: timeZone, style: style) else {
      return nil
    }

    return "\(context)：\(resetLabel) · \(durationLabel(remaining))后"
  }

  private static func configuredCalendar(timeZone: TimeZone) -> Calendar {
    var calendar = Calendar.autoupdatingCurrent
    calendar.timeZone = timeZone
    return calendar
  }

  private static func configuredFormatter(timeZone: TimeZone) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = timeZone
    return formatter
  }
}
