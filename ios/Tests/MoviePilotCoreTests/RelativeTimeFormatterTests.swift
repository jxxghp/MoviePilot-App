import Foundation
import MoviePilotCore
import Testing

struct RelativeTimeFormatterTests {
  @Test func formatsSecondsMinutesHoursDaysMonthsAndYearsAgo() throws {
    let tz = try #require(TimeZone(identifier: "Asia/Shanghai"))
    let now = try #require(RelativeTimeFormatter.parse("2026-11-22 12:00:00", timeZone: tz))

    #expect(RelativeTimeFormatter.format("2026-11-22 12:00:00", now: now, timeZone: tz) == "刚刚")
    #expect(RelativeTimeFormatter.format("2026-11-22 12:01:00", now: now, timeZone: tz) == "刚刚")
    #expect(RelativeTimeFormatter.format("2026-11-22 11:59:25", now: now, timeZone: tz) == "35秒前")
    #expect(RelativeTimeFormatter.format("2026-11-22 11:48:00", now: now, timeZone: tz) == "12分钟前")
    #expect(RelativeTimeFormatter.format("2026-11-22 09:00:00", now: now, timeZone: tz) == "3小时前")
    #expect(RelativeTimeFormatter.format("2026-11-17 12:00:00", now: now, timeZone: tz) == "5天前")
    #expect(RelativeTimeFormatter.format("2026-10-24 12:00:00", now: now, timeZone: tz) == "29天前")
    #expect(RelativeTimeFormatter.format("2026-10-23 12:00:00", now: now, timeZone: tz) == "1个月前")
    #expect(RelativeTimeFormatter.format("2026-09-20 12:00:00", now: now, timeZone: tz) == "2个月前")
    #expect(RelativeTimeFormatter.format("2025-12-01 12:00:00", now: now, timeZone: tz) == "11个月前")
    #expect(RelativeTimeFormatter.format("2025-11-22 12:00:00", now: now, timeZone: tz) == "1年前")
    #expect(RelativeTimeFormatter.format("2024-05-01 12:00:00", now: now, timeZone: tz) == "2年前")
  }

  @Test func parsesISO8601AndFallsBackGracefullyOnUnparseableText() throws {
    let tz = try #require(TimeZone(identifier: "Asia/Shanghai"))
    let now = try #require(RelativeTimeFormatter.parse("2026-11-22 12:00:00", timeZone: tz))

    #expect(
      RelativeTimeFormatter.format("2026-11-22T11:55:00+08:00", now: now, timeZone: tz) == "5分钟前")
    #expect(
      RelativeTimeFormatter.format("2026-11-22 11:54:59.123456", now: now, timeZone: tz) == "5分钟前")
    #expect(RelativeTimeFormatter.format("未知时间", now: now, timeZone: tz) == "未知时间")
    #expect(RelativeTimeFormatter.format("   ", now: now, timeZone: tz) == nil)
  }
}
