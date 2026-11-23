import Foundation

/// 将后端时间戳字符串解析并格式化为中文相对时间（如 `35秒前`、`12分钟前`、`3小时前`、`5天前`、`2个月前`、`1年前`）。
public enum RelativeTimeFormatter {
  /// 将时间戳字符串格式化为相对当前时间的中文倒计文本；无法解析时原样返回清洗后的文本。
  public static func format(
    _ raw: String?,
    now: Date = Date(),
    timeZone: TimeZone = .current
  ) -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
    else { return nil }
    guard let date = parse(trimmed, timeZone: timeZone) else { return trimmed }
    return format(date: date, now: now)
  }

  /// 按经过秒数分段输出 `刚刚`、`xx秒前`、`xx分钟前`、`xx小时前`、`xx天前`、`xx个月前`、`xx年前`。
  public static func format(date: Date, now: Date = Date()) -> String {
    let elapsed = Int(now.timeIntervalSince(date))
    if elapsed < 1 {
      return "刚刚"
    }
    if elapsed < 60 {
      return "\(elapsed)秒前"
    }
    if elapsed < 3_600 {
      return "\(elapsed / 60)分钟前"
    }
    if elapsed < 86_400 {
      return "\(elapsed / 3_600)小时前"
    }
    let daySeconds = 86_400
    let days = elapsed / daySeconds
    if days < 30 {
      return "\(days)天前"
    }
    if days < 365 {
      let months = min(max(days / 30, 1), 11)
      return "\(months)个月前"
    }
    let years = max(days / 365, 1)
    return "\(years)年前"
  }

  /// 解析常见后端时间字符串（含本地 `yyyy-MM-dd HH:mm:ss`、ISO 8601 带/不带时区与小数秒）。
  public static func parse(_ raw: String, timeZone: TimeZone = .current) -> Date? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let isoFractional = ISO8601DateFormatter()
    isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = isoFractional.date(from: trimmed) {
      return date
    }

    let isoStandard = ISO8601DateFormatter()
    isoStandard.formatOptions = [.withInternetDateTime]
    if let date = isoStandard.date(from: trimmed) {
      return date
    }

    let formats = [
      "yyyy-MM-dd HH:mm:ss",
      "yyyy-MM-dd'T'HH:mm:ss",
      "yyyy-MM-dd HH:mm:ss.SSSSSS",
      "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
      "yyyy-MM-dd HH:mm:ss.SSS",
      "yyyy-MM-dd'T'HH:mm:ss.SSS",
      "yyyy/MM/dd HH:mm:ss",
      "yyyy-MM-dd HH:mm",
      "yyyy-MM-dd",
    ]
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    for pattern in formats {
      formatter.dateFormat = pattern
      if let date = formatter.date(from: trimmed) {
        return date
      }
    }
    return nil
  }
}
