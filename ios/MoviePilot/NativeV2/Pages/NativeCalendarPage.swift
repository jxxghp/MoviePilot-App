import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生追剧日历页：参照周历日签条与透色玻璃卡片，直连 `GET /api/v1/subscribe/calendar`。
@MainActor
struct NativeCalendarPage: View {
  let session: NativeSession

  @State private var anchorWeekStart: Date
  @State private var selectedDate: Date
  @State private var entries: [NativeCalendarEntry] = []
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var attempt = 0

  /// 默认定位到包含今天的自然周（周日至周六）。
  init(session: NativeSession) {
    self.session = session
    let calendar = Calendar(identifier: .gregorian)
    let today = calendar.startOfDay(for: Date())
    let weekday = calendar.component(.weekday, from: today)
    let start = calendar.date(byAdding: .day, value: -(weekday - 1), to: today) ?? today
    _anchorWeekStart = State(initialValue: start)
    _selectedDate = State(initialValue: today)
  }

  /// 顶部周日期切换栏 + 当日播出卡片（或优雅空态）+ 本周排期总览。
  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          weekStrip
          if isLoading && entries.isEmpty {
            ProgressView("正在载入追剧日历…")
              .tint(.white)
              .frame(maxWidth: .infinity, minHeight: 180)
          } else if loadFailed && entries.isEmpty {
            failureCard
          } else {
            selectedDaySection
            if !entries.isEmpty {
              weekOverviewSection
            }
          }
        }
        .frame(maxWidth: 820)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .refreshable { await load() }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-calendar-scroll")
    }
    .navigationTitle(navigationMonthTitle)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("今天") {
          let today = calendar.startOfDay(for: Date())
          let weekday = calendar.component(.weekday, from: today)
          anchorWeekStart =
            calendar.date(byAdding: .day, value: -(weekday - 1), to: today) ?? today
          selectedDate = today
        }
        .accessibilityIdentifier("native-calendar-today")
      }
    }
    .task(id: "\(Self.isoDate(anchorWeekStart))|\(attempt)") { await load() }
  }

  private let calendar = Calendar(identifier: .gregorian)

  /// 当前展示的 7 天日期序列。
  private var weekDays: [Date] {
    (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: anchorWeekStart) }
  }

  /// 单行七天日签条：左右两侧直接内置上一周/下一周切换按钮，今天以暖红标注，选中项透色圆角高亮，有剧集日期带底部圆点。
  private var weekStrip: some View {
    let todayKey = Self.isoDate(Date())
    let selectedKey = Self.isoDate(selectedDate)
    let activeDates = Set(entries.map(\.date))
    return HStack(spacing: 4) {
      weekShiftButton(
        symbol: "chevron.left",
        label: "上一周",
        id: "native-calendar-prev-week"
      ) {
        withAnimation(.easeInOut(duration: 0.2)) { shiftWeek(by: -7) }
      }

      HStack(spacing: 3) {
        ForEach(weekDays, id: \.self) { day in
          let key = Self.isoDate(day)
          let isToday = key == todayKey
          let isSelected = key == selectedKey
          let hasItems = activeDates.contains(key)
          Button {
            selectedDate = day
          } label: {
            VStack(spacing: 4) {
              Text("\(calendar.component(.day, from: day))")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(isToday ? Color(red: 1.0, green: 0.42, blue: 0.44) : .white)
              Text(Self.weekdayShort(calendar.component(.weekday, from: day)))
                .font(.caption2)
                .foregroundStyle(
                  isToday ? Color(red: 1.0, green: 0.42, blue: 0.44) : .white.opacity(0.68))
              Circle()
                .fill(hasItems ? Color(red: 0.78, green: 0.62, blue: 1.0) : .clear)
                .frame(width: 4.5, height: 4.5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
              if isSelected {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                  .fill(.white.opacity(0.13))
                  .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                      .strokeBorder(.white.opacity(0.28), lineWidth: 0.8)
                  }
              }
            }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-calendar-day-\(key)")
        }
      }

      weekShiftButton(
        symbol: "chevron.right",
        label: "下一周",
        id: "native-calendar-next-week"
      ) {
        withAnimation(.easeInOut(duration: 0.2)) { shiftWeek(by: 7) }
      }
    }
    .contentShape(Rectangle())
    .gesture(
      DragGesture(minimumDistance: 28)
        .onEnded { value in
          guard abs(value.translation.width) > abs(value.translation.height) else { return }
          if value.translation.width < -28 {
            withAnimation(.easeInOut(duration: 0.2)) { shiftWeek(by: 7) }
          } else if value.translation.width > 28 {
            withAnimation(.easeInOut(duration: 0.2)) { shiftWeek(by: -7) }
          }
        }
    )
  }

  /// 紧贴日期条两侧的周切换按钮。
  private func weekShiftButton(
    symbol: String, label: String, id: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.caption.weight(.bold))
        .foregroundStyle(.white.opacity(0.86))
        .frame(width: 28, height: 48)
        .background {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.white.opacity(0.08))
            .overlay {
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
            }
        }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .accessibilityIdentifier(id)
  }

  /// 选中日期的播出内容或参考图同款空态玻璃卡。
  @ViewBuilder
  private var selectedDaySection: some View {
    let selectedKey = Self.isoDate(selectedDate)
    let matching = entries.filter { $0.date == selectedKey }
    if matching.isEmpty {
      CinematicPanel {
        VStack(spacing: 10) {
          Image(systemName: "tv")
            .font(.title)
            .foregroundStyle(.white.opacity(0.55))
          Text("这天没有播出的剧").font(.headline)
          Text("切换其他日期查看，或在媒体详情中添加订阅追剧。")
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.62))
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 132)
      }
      .accessibilityIdentifier("native-calendar-day-empty")
    } else {
      LazyVStack(alignment: .leading, spacing: 12) {
        Text("\(selectedKey) 播出").font(.headline).accessibilityAddTraits(.isHeader)
        ForEach(matching) { entry in
          calendarEntryCard(entry)
        }
      }
    }
  }

  /// 本周全部排期汇总，采用延迟垂直栈避免首屏同时发起数十张海报请求。
  private var weekOverviewSection: some View {
    LazyVStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("本周排期").font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
        Spacer()
        Text("\(entries.count) 项").font(.caption).foregroundStyle(.white.opacity(0.62))
      }
      ForEach(entries) { entry in
        calendarEntryCard(entry)
      }
    }
  }

  /// 单条播出日历卡片：竖版海报 + 剧名/季号 + 播出日期与集列表 + 订阅进度。
  private func calendarEntryCard(_ entry: NativeCalendarEntry) -> some View {
    let poster = NativeMediaDetailPage.resolveArtwork(
      entry.subscribe?.poster, source: "themoviedb")
    return CinematicPanel(padding: 12) {
      HStack(alignment: .top, spacing: 12) {
        NativeMediaArtwork(session: session, reference: poster, role: .poster, maximumWidth: 420)
          .frame(width: 58, height: 87)
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
          }
        VStack(alignment: .leading, spacing: 5) {
          HStack {
            Text(entry.displayTitle)
              .font(.headline)
              .foregroundStyle(.white)
              .lineLimit(1)
            Spacer(minLength: 4)
            Text(entry.date)
              .font(.caption2.monospacedDigit())
              .foregroundStyle(.white.opacity(0.68))
          }
          if !entry.episodesSummary.isEmpty {
            Text(entry.episodesSummary)
              .font(.subheadline)
              .foregroundStyle(.white.opacity(0.84))
              .lineLimit(2)
          }
          if let progressText = entry.progressSummary {
            Text(progressText)
              .font(.caption)
              .foregroundStyle(.white.opacity(0.62))
          }
        }
      }
    }
    .accessibilityIdentifier("native-calendar-entry-\(entry.id)")
  }

  /// 载入失败卡片。
  private var failureCard: some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 10) {
        Label("暂时无法载入追剧日历", systemImage: "exclamationmark.triangle").font(.headline)
        Button("重试") { attempt += 1 }
          .frame(minHeight: 44)
          .accessibilityIdentifier("native-calendar-retry")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// 切换上一周或下一周，并保持选中日期在目标周内。
  private func shiftWeek(by days: Int) {
    if let nextStart = calendar.date(byAdding: .day, value: days, to: anchorWeekStart) {
      anchorWeekStart = nextStart
      selectedDate = nextStart
    }
  }

  /// 导航栏紧凑年月标题：随当前选中周自动变化，避免额外占用日期条上方整行空间。
  private var navigationMonthTitle: String {
    let selectedYear = calendar.component(.year, from: selectedDate)
    let currentYear = calendar.component(.year, from: Date())
    let month = calendar.component(.month, from: selectedDate)
    if selectedYear != currentYear {
      return "追剧日历 · \(selectedYear)年\(month)月"
    }
    return "追剧日历 · \(month)月"
  }

  /// 请求可见周区间内的订阅播出排期（`end` 为开区间故 +7 天）。
  private func load() async {
    isLoading = true
    loadFailed = false
    defer { isLoading = false }
    let end = calendar.date(byAdding: .day, value: 7, to: anchorWeekStart) ?? anchorWeekStart
    do {
      let endpoint = try APIEndpoint(
        path: ["subscribe", "calendar"],
        query: [
          URLQueryItem(name: "start", value: Self.isoDate(anchorWeekStart)),
          URLQueryItem(name: "end", value: Self.isoDate(end)),
          URLQueryItem(name: "page", value: "1"),
          URLQueryItem(name: "count", value: "100"),
        ])
      let page = try await session.request(
        endpoint, as: NativeCalendarPagePayload.self, requiring: .init(category: .subscribe)
      ).value
      try Task.checkCancellation()
      entries = page.items ?? []
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
    }
  }

  /// 输出 `YYYY-MM-DD` 格式日期字符串。
  private static func isoDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  /// 中文单字星期标签，适配单行 7 日 + 左右周切换按钮布局。
  private static func weekdayShort(_ weekday: Int) -> String {
    switch weekday {
    case 1: "日"
    case 2: "一"
    case 3: "二"
    case 4: "三"
    case 5: "四"
    case 6: "五"
    default: "六"
    }
  }
}

/// `GET /api/v1/subscribe/calendar` 分页返回结构。
private struct NativeCalendarPagePayload: Decodable, Sendable {
  let items: [NativeCalendarEntry]?
  let total: Int?
}

/// 单日订阅播出条目。
private struct NativeCalendarEntry: Decodable, Sendable, Identifiable {
  /// 单集摘要。
  struct Episode: Decodable, Sendable {
    let episodeNumber: Int?
    let name: String?

    /// 对应 `episode_number` 字段。
    private enum CodingKeys: String, CodingKey {
      case episodeNumber = "episode_number"
      case name
    }
  }

  /// 关联订阅摘要。
  struct SubscribeSummary: Decodable, Sendable {
    let id: Int?
    let name: String?
    let season: Int?
    let poster: String?
    let totalEpisode: Int?
    let completedEpisode: Int?

    /// 对应日历内嵌订阅字段。
    private enum CodingKeys: String, CodingKey {
      case id
      case name
      case season
      case poster
      case totalEpisode = "total_episode"
      case completedEpisode = "completed_episode"
    }
  }

  let date: String
  let episodes: [Episode]?
  let runtime: Int?
  let subscribe: SubscribeSummary?

  /// 由日期与订阅 ID 构成唯一行键。
  var id: String { "\(date)|\(subscribe?.id ?? 0)|\(subscribe?.name ?? "")" }

  /// 剧名与季号。
  var displayTitle: String {
    let base = subscribe?.name ?? "订阅更新"
    if let season = subscribe?.season {
      return "\(base) S\(String(format: "%02d", season))"
    }
    return base
  }

  /// 汇总当日播出的集数与单集名。
  var episodesSummary: String {
    (episodes ?? []).prefix(3).compactMap { ep in
      if let num = ep.episodeNumber {
        if let name = ep.name, !name.isEmpty { return "E\(String(format: "%02d", num)) \(name)" }
        return "第 \(num) 集"
      }
      return ep.name
    }.joined(separator: " · ")
  }

  /// 订阅完成进度与单集时长说明。
  var progressSummary: String? {
    var parts: [String] = []
    if let total = subscribe?.totalEpisode, total > 0 {
      let done = subscribe?.completedEpisode ?? 0
      parts.append("已更新 \(done)/\(total) 集")
    }
    if let runtime, runtime > 0 {
      parts.append("\(runtime) 分钟")
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }
}
