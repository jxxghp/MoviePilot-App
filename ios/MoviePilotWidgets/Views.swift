import AppIntents
import MoviePilotCore
import SwiftUI
import WidgetKit

#if canImport(UIKit)
  import UIKit
#endif

/// 六尺寸共用语义颜色与数据投影，材质和着色由 WidgetKit 提供。
struct MoviePilotWidgetView: View {
  let entry: MoviePilotEntry
  @Environment(\.widgetFamily) private var family

  /// 不自绘玻璃或固定明暗底色；系统决定桌面、锁屏和着色模式的容器外观。
  var body: some View {
    Group {
      switch family {
      case .accessoryInline: inline
      case .accessoryCircular: circular
      case .accessoryRectangular: rectangular
      default: home
      }
    }
    .containerBackground(.background, for: .widget)
    .widgetURL(entry.display.link)
    .redacted(reason: entry.placeholder ? .placeholder : [])
    .privacySensitive(!entry.sample)
  }

  /// 页头只展示别名与内容；地址和账号身份不出现在组件上。
  private var header: some View {
    HStack(spacing: 6) {
      Image(systemName: entry.content.symbol).foregroundStyle(.tint).widgetAccentable()
      Text(entry.display.name).font(.caption.weight(.semibold)).lineLimit(1)
      Spacer(minLength: 0)
      if family != .systemSmall {
        Text(entry.display.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
      }
    }
  }

  /// 高度不足时保留主指标和更新时间，避免大字体把必要信息推到容器外。
  private var home: some View {
    VStack(alignment: .leading, spacing: family == .systemMedium ? 4 : 8) {
      header
      if entry.display.metrics.isEmpty && entry.display.items.isEmpty {
        Spacer(minLength: 0)
        Text(
          entry.display.state == .empty
            ? L10n.text("暂无内容") : (entry.display.message ?? L10n.text("暂时无法读取"))
        )
        .font(.subheadline).foregroundStyle(.secondary).fixedSize(
          horizontal: false, vertical: true)
        Spacer(minLength: 0)
      } else {
        details
        Spacer(minLength: 0)
      }
      footer
    }
  }

  /// 小、中尺寸只展示统计；大尺寸按可用高度减少明细条数，不挤掉分类总数。
  @ViewBuilder private var details: some View {
    if family == .systemSmall {
      compactMetrics
    } else if family == .systemLarge && entry.content != .overview && !entry.display.items.isEmpty {
      ViewThatFits(in: .vertical) {
        largeDetails(limit: 6)
        largeDetails(limit: 4)
        largeDetails(limit: 2)
        statistics
      }
    } else if family == .systemMedium {
      ViewThatFits(in: .vertical) {
        statistics
        compactMetrics
      }
    } else {
      statistics
    }
  }

  /// 大卡片先显示全量统计，再显示服务提供的近期明细和自然进度。
  private func largeDetails(limit: Int) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      statistics
      Divider()
      VStack(alignment: .leading, spacing: 6) {
        ForEach(entry.display.items.prefix(limit), id: \.id) { item in
          if let url = entry.display.link {
            Link(destination: url) { itemView(item) }.buttonStyle(.plain)
          } else {
            itemView(item)
          }
        }
      }
    }.fixedSize(horizontal: false, vertical: true)
  }

  /// 分类与状态使用独立格子，数量沿用后台全范围计数，不从六条明细重算。
  private var statistics: some View {
    let columns = entry.content == .subscriptions ? 4 : (entry.content == .downloads ? 3 : 2)
    let metrics =
      entry.content == .overview && family == .systemMedium
      ? Array(entry.display.metrics.prefix(4)) : entry.display.metrics
    // 有限指标直接排版，避免惰性网格在 ViewThatFits 中高估高度并退回总数。
    return VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 6) {
      ForEach(Array(stride(from: 0, to: metrics.count, by: columns)), id: \.self) { row in
        HStack(alignment: .top, spacing: 8) {
          ForEach(0..<columns, id: \.self) { column in
            if metrics.indices.contains(row + column) {
              metricView(metrics[row + column])
            } else {
              Color.clear.frame(maxWidth: .infinity)
            }
          }
        }
      }
    }.fixedSize(horizontal: false, vertical: true)
  }

  /// 只识别明确的速度指标，不把旧服务的任务总数当作下载速度。
  private var hasTransferMetrics: Bool {
    entry.content == .downloads
      && entry.display.metrics.contains { $0.id == "downloadSpeed" }
      && entry.display.metrics.contains { $0.id == "uploadSpeed" }
  }

  /// 小尺寸保留双向速度或 CPU/内存；订阅和入库只显示总数。
  @ViewBuilder private var compactMetrics: some View {
    if hasTransferMetrics || entry.content == .overview {
      let metrics = entry.display.metrics.filter {
        entry.content == .overview
          ? ["cpu", "memory"].contains($0.id)
          : ["downloadSpeed", "uploadSpeed"].contains($0.id)
      }
      VStack(alignment: .leading, spacing: 8) {
        ForEach(metrics, id: \.id) { metric in
          if entry.content == .overview {
            metricView(metric)
          } else {
            HStack(spacing: 5) {
              Image(systemName: metric.icon.symbol).foregroundStyle(.tint).widgetAccentable()
              Text(metric.value).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(
                0.7)
            }.accessibilityLabel("\(metric.title) \(metric.value)")
          }
        }
      }
    } else {
      primaryMetric
    }
  }

  /// 总数标签按内容表达用途，不改变服务端计数或将未授权分类显示为零。
  private func metricTitle(_ metric: WidgetMetric) -> String {
    guard metric.id == "count" else { return metric.title }
    switch entry.content {
    case .imports: return L10n.text("总入库")
    case .subscriptions: return L10n.text("总订阅")
    case .downloads: return L10n.text("下载任务")
    default: return metric.title
    }
  }

  /// 主指标保留后台格式化单位，不自行计算下载速度、总数或权限。
  @ViewBuilder private var primaryMetric: some View {
    if let metric = entry.display.metrics.first {
      VStack(alignment: .leading, spacing: 2) {
        Text(metric.value)
          .font(
            .system(family == .systemSmall ? .largeTitle : .title2, design: .rounded).weight(
              .semibold)
          )
          .lineLimit(1).minimumScaleFactor(0.6).monospacedDigit()
        Text(metricTitle(metric)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
    } else {
      Text(entry.display.title).font(.headline).lineLimit(1)
    }
  }

  /// 辅助指标使用语义符号及二级标题，兼容系统深浅色和桌面着色。
  private func metricView(_ metric: WidgetMetric) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Label(metricTitle(metric), systemImage: metric.icon.symbol)
        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
      Text(metric.value)
        .font(family == .systemMedium ? .subheadline.weight(.semibold) : .headline)
        .lineLimit(1).minimumScaleFactor(0.65).monospacedDigit()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// 只有来源自带百分比才画进度条，名称已由隐私投影决定是否保留。
  private func itemView(_ item: WidgetItem) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Text(item.title).font(.caption).lineLimit(1)
        Spacer(minLength: 0)
        if let progress = item.progress {
          Text(progress, format: .percent.precision(.fractionLength(0)))
            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
      }
      if let subtitle = item.subtitle, !subtitle.isEmpty {
        Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
      }
      if let progress = item.progress {
        ProgressView(value: progress).accessibilityLabel(L10n.text("进度"))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// 常驻真实采样时间，断网和过旧均不能伪装成刚刚更新。
  private var footer: some View {
    HStack(spacing: 4) {
      if let date = entry.display.updatedAt {
        Image(systemName: entry.display.state == .stale ? "clock.badge.exclamationmark" : "clock")
        Text(date, style: .time)
      }
      if let note = entry.display.message, entry.display.updatedAt != nil {
        Text(note).lineLimit(1)
      }
    }
    .font(.caption2).foregroundStyle(.secondary)
  }

  /// 行内用一个 Text 保留完整双向速度，避免系统只提取 HStack 中的首段文字。
  @ViewBuilder private var inline: some View {
    if hasTransferMetrics,
      let download = entry.display.metrics.first(where: { $0.id == "downloadSpeed" }),
      let upload = entry.display.metrics.first(where: { $0.id == "uploadSpeed" })
    {
      Text("↓ \(lockRate(download)) ↑ \(lockRate(upload))")
        .accessibilityLabel(L10n.format("下载速度 %@，上传速度 %@", download.value, upload.value))
    } else {
      Label(
        entry.display.metrics.first?.value ?? L10n.text("打开 MoviePilot"),
        systemImage: entry.content.symbol)
    }
  }

  /// 锁屏只压缩速率单位的写法，不换算数值；桌面继续显示后台原始格式。
  private func lockRate(_ metric: WidgetMetric) -> String {
    metric.value.replacingOccurrences(of: " ", with: "")
      .replacingOccurrences(of: "GB/s", with: "G/s")
      .replacingOccurrences(of: "MB/s", with: "M/s")
      .replacingOccurrences(of: "KB/s", with: "K/s")
  }

  /// 自然进度用圆环，数量或速度用文字，避免将数量误画成百分比。
  private var circular: some View {
    ZStack {
      AccessoryWidgetBackground()
      if hasTransferMetrics {
        VStack(spacing: 2) {
          ForEach(
            entry.display.metrics.filter { $0.id == "downloadSpeed" || $0.id == "uploadSpeed" },
            id: \.id
          ) { metric in
            HStack(spacing: 2) {
              Image(systemName: metric.icon.symbol)
              Text(lockRate(metric)).lineLimit(1).minimumScaleFactor(0.85)
            }.font(.system(.caption2, design: .rounded).weight(.medium))
              .accessibilityLabel("\(metric.title) \(metric.value)")
          }
        }
      } else if let progress = entry.display.items.first?.progress {
        Gauge(value: progress) { Image(systemName: entry.content.symbol) }
          .gaugeStyle(.accessoryCircular)
      } else {
        VStack(spacing: 2) {
          Image(systemName: entry.content.symbol)
          Text(entry.display.metrics.first?.value ?? L10n.text("打开 App"))
            .font(.caption2).lineLimit(1).minimumScaleFactor(0.5)
        }
      }
    }
  }

  /// 矩形锁屏只保留两行必要数据，去掉实例名和时间，避免狭小容器文字溢出。
  private var rectangular: some View {
    VStack(alignment: .leading, spacing: 4) {
      if entry.display.metrics.isEmpty {
        Label(entry.display.title, systemImage: entry.content.symbol)
          .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        Text(entry.display.state == .empty ? L10n.text("暂无内容") : L10n.text("在 App 中检查小组件"))
          .font(.caption).lineLimit(2)
      } else if hasTransferMetrics {
        HStack(spacing: 10) {
          ForEach(
            entry.display.metrics.filter { $0.id == "downloadSpeed" || $0.id == "uploadSpeed" },
            id: \.id
          ) { metric in
            Label(lockRate(metric), systemImage: metric.icon.symbol)
              .lineLimit(1).minimumScaleFactor(0.85)
              .accessibilityLabel("\(metric.title) \(metric.value)")
          }
        }.font(.caption.weight(.semibold)).monospacedDigit()
        if let metric = entry.display.metrics.first(where: { $0.id == "freeSpace" }) {
          HStack(spacing: 4) {
            Label(L10n.format("剩余 %@", metric.value), systemImage: metric.icon.symbol)
              .lineLimit(1).minimumScaleFactor(0.85)
              .accessibilityLabel("\(metric.title) \(metric.value)")
            if entry.display.state == .stale {
              Image(systemName: "clock.badge.exclamationmark")
                .accessibilityLabel(L10n.text("数据待更新"))
            }
          }.font(.caption2).foregroundStyle(.secondary)
        }
      } else {
        Label(entry.display.title, systemImage: entry.content.symbol)
          .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        Text(
          entry.display.metrics.prefix(2).map { "\($0.title) \($0.value)" }.joined(separator: " · ")
        )
        .font(.caption).lineLimit(2)
      }
    }
  }
}

/// 正在播放桌面小组件视图，支持小、中、大三种响应式尺寸与零延迟播控按钮。
struct MoviePilotNowPlayingWidgetView: View {
  let entry: NowPlayingWidgetEntry
  @Environment(\.widgetFamily) private var family

  /// 采用系统原生材质背景，兼容浅色、深色与桌面图标色调渲染。
  var body: some View {
    Group {
      if !entry.snapshot.active || entry.snapshot.title.isEmpty {
        idleView
      } else {
        switch family {
        case .systemSmall:
          smallPlayingView
        case .systemLarge:
          largePlayingView
        default:
          mediumPlayingView
        }
      }
    }
    .containerBackground(.background, for: .widget)
    .widgetURL(deepLinkURL)
    .redacted(reason: entry.placeholder ? .placeholder : [])
    .privacySensitive(!entry.sample)
  }

  private var deepLinkURL: URL? {
    let pid = entry.snapshot.pluginId.trimmingCharacters(in: .whitespacesAndNewlines)
    if PluginWidgetValidator.isValidPluginId(pid) {
      return URL(string: "moviepilot://plugin/\(pid)?surface=data")
    }
    return URL(string: "moviepilot://music")
  }

  private var idleView: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: "waveform.circle.fill")
          .font(.subheadline)
          .foregroundStyle(.tint)
          .widgetAccentable()
        Text("正在播放")
          .font(.caption.weight(.semibold))
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      Spacer(minLength: 0)
      Text(L10n.text("当前暂无播放中的插件音频"))
        .font(.subheadline.weight(.medium))
        .lineLimit(2)
      Text(L10n.text("点击打开 MoviePilot"))
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Spacer(minLength: 0)
    }
  }

  private var smallPlayingView: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 8) {
        artworkThumb(size: 46, radius: 11)
        Spacer(minLength: 0)
        Button(
          intent: NowPlayingControlIntent(
            command: "togglePlayPause", pluginId: entry.snapshot.pluginId)
        ) {
          Image(systemName: entry.snapshot.isPlaying ? "pause.circle.fill" : "play.circle.fill")
            .font(.system(size: 28))
            .foregroundStyle(.tint)
            .widgetAccentable()
        }
        .buttonStyle(.plain)
      }
      Spacer(minLength: 0)
      Text(entry.snapshot.title)
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
      Text(
        entry.snapshot.artist.isEmpty
          ? (entry.snapshot.pluginName.isEmpty ? "MoviePilot" : entry.snapshot.pluginName)
          : entry.snapshot.artist
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
      .lineLimit(1)
      if let progress = playbackProgress {
        ProgressView(value: progress)
          .tint(.accentColor)
      }
    }
  }

  private var mediumPlayingView: some View {
    HStack(spacing: 12) {
      artworkThumb(size: 78, radius: 16)
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 6) {
          Text(entry.snapshot.title)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
          Spacer(minLength: 0)
          if !entry.snapshot.pluginName.isEmpty {
            Text(entry.snapshot.pluginName)
              .font(.system(size: 10, weight: .medium))
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        Text(subtitleLine)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        if let lyric = currentLyricLines.first {
          Text(lyric)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.tint)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
        controlRow(compact: true)
      }
    }
  }

  private var largePlayingView: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        artworkThumb(size: 86, radius: 18)
        VStack(alignment: .leading, spacing: 4) {
          if !entry.snapshot.pluginName.isEmpty {
            Label(entry.snapshot.pluginName, systemImage: "waveform")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.tint)
              .lineLimit(1)
          }
          Text(entry.snapshot.title)
            .font(.headline.weight(.bold))
            .lineLimit(2)
          Text(subtitleLine)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
      }

      if let progress = playbackProgress {
        VStack(spacing: 3) {
          ProgressView(value: progress)
            .tint(.accentColor)
          HStack {
            Text(formatDurationMs(entry.snapshot.positionMs))
            Spacer(minLength: 0)
            Text(formatDurationMs(entry.snapshot.durationMs))
          }
          .font(.system(size: 10, design: .rounded))
          .foregroundStyle(.secondary)
          .monospacedDigit()
        }
      }

      Divider()

      VStack(alignment: .leading, spacing: 5) {
        let lines = currentLyricLines
        if lines.isEmpty {
          Text(L10n.text("暂无同步歌词"))
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          ForEach(Array(lines.prefix(4).enumerated()), id: \.offset) { idx, line in
            Text(line)
              .font(idx == 0 ? .subheadline.weight(.semibold) : .caption)
              .foregroundStyle(idx == 0 ? .primary : .secondary)
              .lineLimit(1)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Spacer(minLength: 0)
      controlRow(compact: false)
    }
  }

  private func controlRow(compact: Bool) -> some View {
    HStack(spacing: compact ? 14 : 22) {
      if entry.snapshot.hasLike {
        Button(
          intent: NowPlayingControlIntent(
            command: "toggleLike", pluginId: entry.snapshot.pluginId)
        ) {
          Image(systemName: entry.snapshot.liked ? "heart.fill" : "heart")
            .font(.system(size: compact ? 15 : 17, weight: .semibold))
            .foregroundStyle(entry.snapshot.liked ? Color.red : Color.secondary)
        }
        .buttonStyle(.plain)
      }

      Button(
        intent: NowPlayingControlIntent(
          command: "previous", pluginId: entry.snapshot.pluginId)
      ) {
        Image(systemName: "backward.fill")
          .font(.system(size: compact ? 15 : 18, weight: .semibold))
          .foregroundStyle(entry.snapshot.canPrevious ? .primary : .tertiary)
      }
      .buttonStyle(.plain)
      .disabled(!entry.snapshot.canPrevious)

      Button(
        intent: NowPlayingControlIntent(
          command: "togglePlayPause", pluginId: entry.snapshot.pluginId)
      ) {
        Image(systemName: entry.snapshot.isPlaying ? "pause.circle.fill" : "play.circle.fill")
          .font(.system(size: compact ? 26 : 34))
          .foregroundStyle(.tint)
          .widgetAccentable()
      }
      .buttonStyle(.plain)

      Button(
        intent: NowPlayingControlIntent(
          command: "next", pluginId: entry.snapshot.pluginId)
      ) {
        Image(systemName: "forward.fill")
          .font(.system(size: compact ? 15 : 18, weight: .semibold))
          .foregroundStyle(entry.snapshot.canNext ? .primary : .tertiary)
      }
      .buttonStyle(.plain)
      .disabled(!entry.snapshot.canNext)

      if compact {
        Spacer(minLength: 0)
      }
    }
    .frame(maxWidth: .infinity, alignment: compact ? .leading : .center)
  }

  @ViewBuilder
  private func artworkThumb(size: CGFloat, radius: CGFloat) -> some View {
    #if canImport(UIKit)
      if let data = entry.artworkData, let uiImage = UIImage(data: data) {
        Image(uiImage: uiImage)
          .resizable()
          .scaledToFill()
          .frame(width: size, height: size)
          .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
      } else {
        placeholderArtwork(size: size, radius: radius)
      }
    #else
      placeholderArtwork(size: size, radius: radius)
    #endif
  }

  private func placeholderArtwork(size: CGFloat, radius: CGFloat) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: radius, style: .continuous)
        .fill(.quaternary)
      Image(systemName: "music.quarternote.3")
        .font(.system(size: size * 0.38, weight: .semibold))
        .foregroundStyle(.tint)
        .widgetAccentable()
    }
    .frame(width: size, height: size)
  }

  private var subtitleLine: String {
    let artist = entry.snapshot.artist.trimmingCharacters(in: .whitespacesAndNewlines)
    let album = entry.snapshot.album.trimmingCharacters(in: .whitespacesAndNewlines)
    if !artist.isEmpty && !album.isEmpty { return "\(artist) · \(album)" }
    if !artist.isEmpty { return artist }
    if !album.isEmpty { return album }
    return entry.snapshot.pluginName.isEmpty ? "MoviePilot" : entry.snapshot.pluginName
  }

  private var currentLyricLines: [String] {
    entry.snapshot.lyrics
      .components(separatedBy: .newlines)
      .map { line -> String in
        if let closeIdx = line.firstIndex(of: "]"), line.hasPrefix("[") {
          return String(line[line.index(after: closeIdx)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      .filter { !$0.isEmpty }
  }

  private var playbackProgress: Double? {
    guard entry.snapshot.durationMs > 0 else { return nil }
    let ratio = Double(entry.snapshot.positionMs) / Double(entry.snapshot.durationMs)
    return min(max(ratio, 0), 1)
  }

  private func formatDurationMs(_ ms: Int) -> String {
    let totalSec = max(0, ms / 1000)
    let minutes = totalSec / 60
    let seconds = totalSec % 60
    return String(format: "%02d:%02d", minutes, seconds)
  }
}

/// 插件桌面小组件视图：统一承载预设模板与 `PluginWidgetNode` 自定义布局树。
struct MoviePilotPluginWidgetView: View {
  let entry: PluginWidgetEntry
  @Environment(\.widgetFamily) private var family

  /// 使用系统语义背景与插件自定义强调色。
  var body: some View {
    VStack(alignment: .leading, spacing: family == .systemMedium ? 6 : 8) {
      headerView
      if let snapshot = entry.snapshot {
        if snapshot.state == .unavailable {
          Spacer(minLength: 0)
          Text(snapshot.message ?? L10n.text("暂时无法读取插件小组件"))
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Spacer(minLength: 0)
        } else {
          contentBody(for: snapshot)
          Spacer(minLength: 0)
        }
        footerView(for: snapshot)
      } else {
        Spacer(minLength: 0)
        Text(L10n.text("长按编辑小组件，选择要固定的已启用插件卡片"))
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
      }
    }
    .tint(resolvedAccentColor)
    .containerBackground(.background, for: .widget)
    .widgetURL(defaultPluginURL)
    .redacted(reason: entry.placeholder ? .placeholder : [])
    .privacySensitive(!entry.sample)
  }

  private var resolvedAccentColor: Color? {
    guard let hex = entry.snapshot?.accentHex else { return nil }
    return PluginWidgetTonePalette.colorFromHex(hex)
  }

  private var defaultPluginURL: URL? {
    let pid = (entry.snapshot?.pluginId ?? entry.pluginId)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard PluginWidgetValidator.isValidPluginId(pid) else { return nil }
    let key = (entry.snapshot?.widgetKey ?? entry.widgetKey)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if key.isEmpty {
      return URL(string: "moviepilot://plugin/\(pid)?surface=data")
    }
    return URL(string: "moviepilot://plugin/\(pid)?surface=data&widgetKey=\(key)")
  }

  private var headerView: some View {
    HStack(spacing: 6) {
      Image(systemName: "puzzlepiece.extension.fill")
        .foregroundStyle(.tint)
        .widgetAccentable()
      Text(entry.snapshot?.title ?? entry.profileName)
        .font(.caption.weight(.semibold))
        .lineLimit(1)
      Spacer(minLength: 0)
      if family != .systemSmall, let pluginName = entry.snapshot?.pluginName, !pluginName.isEmpty {
        Text(pluginName)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
  }

  @ViewBuilder
  private func contentBody(for snapshot: PluginWidgetSnapshot) -> some View {
    let sizeKey =
      family == .systemSmall ? "small" : (family == .systemLarge ? "large" : "medium")
    if snapshot.kind == .custom, let rootNode = snapshot.resolvedLayout(forSizeKey: sizeKey) {
      PluginWidgetCustomNodeView(
        node: rootNode,
        pluginId: snapshot.pluginId,
        widgetKey: snapshot.widgetKey,
        depth: 0
      )
    } else {
      switch snapshot.kind {
      case .list:
        presetListView(snapshot)
      case .poster:
        presetPosterView(snapshot)
      case .nowPlaying:
        presetNowPlayingView(snapshot)
      case .pluginLaunch:
        presetLaunchView(snapshot)
      default:
        presetMetricsView(snapshot)
      }
    }
  }

  @ViewBuilder
  private func presetMetricsView(_ snapshot: PluginWidgetSnapshot) -> some View {
    let cols =
      family == .systemSmall
      ? 1 : (snapshot.metrics.count >= 3 && family == .systemMedium ? 3 : 2)
    let visibleMetrics =
      family == .systemSmall
      ? Array(snapshot.metrics.prefix(2))
      : Array(snapshot.metrics.prefix(family == .systemLarge ? 6 : 4))
    if visibleMetrics.isEmpty && snapshot.items.isEmpty {
      Text(snapshot.message ?? snapshot.subtitle ?? L10n.text("暂无可展示的小组件数据"))
        .font(.caption)
        .foregroundStyle(.secondary)
    } else {
      VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 6) {
        if !visibleMetrics.isEmpty {
          ForEach(Array(stride(from: 0, to: visibleMetrics.count, by: cols)), id: \.self) { row in
            HStack(alignment: .top, spacing: 8) {
              ForEach(0..<cols, id: \.self) { col in
                if visibleMetrics.indices.contains(row + col) {
                  let m = visibleMetrics[row + col]
                  VStack(alignment: .leading, spacing: 2) {
                    Text(m.label)
                      .font(.caption2)
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
                    Text(m.value)
                      .font(family == .systemMedium ? .subheadline.weight(.semibold) : .headline)
                      .foregroundStyle(PluginWidgetTonePalette.foreground(m.tone))
                      .monospacedDigit()
                      .lineLimit(1)
                      .minimumScaleFactor(0.7)
                    if family == .systemLarge, let sub = m.subValue, !sub.isEmpty {
                      Text(sub)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                  Color.clear.frame(maxWidth: .infinity)
                }
              }
            }
          }
        }
        if family == .systemLarge && !snapshot.items.isEmpty {
          Divider()
          ForEach(snapshot.items.prefix(3), id: \.id) { item in
            presetListRow(item)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func presetListView(_ snapshot: PluginWidgetSnapshot) -> some View {
    let maxRows = family == .systemSmall ? 2 : (family == .systemLarge ? 5 : 2)
    if snapshot.items.isEmpty {
      presetMetricsView(snapshot)
    } else {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(snapshot.items.prefix(maxRows), id: \.id) { item in
          presetListRow(item)
        }
      }
    }
  }

  private func presetListRow(_ item: PluginWidgetListItem) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Text(item.title)
          .font(.caption.weight(.medium))
          .lineLimit(1)
        Spacer(minLength: 0)
        if let trailing = item.trailing, !trailing.isEmpty {
          Text(trailing)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
        } else if let progress = item.progress {
          Text(progress, format: .percent.precision(.fractionLength(0)))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
      }
      if family != .systemSmall, let subtitle = item.subtitle, !subtitle.isEmpty {
        Text(subtitle)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      if let progress = item.progress {
        ProgressView(value: progress)
      }
    }
  }

  private func presetPosterView(_ snapshot: PluginWidgetSnapshot) -> some View {
    HStack(spacing: 10) {
      #if canImport(UIKit)
        if let data = entry.artworkData, let uiImg = UIImage(data: data) {
          Image(uiImage: uiImg)
            .resizable()
            .scaledToFill()
            .frame(
              width: family == .systemSmall ? 48 : 68,
              height: family == .systemSmall ? 64 : 84
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
      #endif
      VStack(alignment: .leading, spacing: 4) {
        if let sub = snapshot.subtitle, !sub.isEmpty {
          Text(sub)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(family == .systemLarge ? 3 : 2)
        }
        if let firstMetric = snapshot.metrics.first {
          Text("\(firstMetric.label)：\(firstMetric.value)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tint)
            .monospacedDigit()
            .lineLimit(1)
        }
        if family == .systemLarge {
          ForEach(snapshot.items.prefix(3), id: \.id) { item in
            presetListRow(item)
          }
        }
      }
    }
  }

  private func presetNowPlayingView(_ snapshot: PluginWidgetSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      if let sub = snapshot.subtitle, !sub.isEmpty {
        Text(sub)
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
      }
      if let firstItem = snapshot.items.first {
        presetListRow(firstItem)
      } else {
        presetMetricsView(snapshot)
      }
    }
  }

  private func presetLaunchView(_ snapshot: PluginWidgetSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      if let sub = snapshot.subtitle, !sub.isEmpty {
        Text(sub)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(family == .systemSmall ? 2 : 3)
      }
      Label(L10n.text("点击打开插件"), systemImage: "arrow.up.forward.circle.fill")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tint)
    }
  }

  private func footerView(for snapshot: PluginWidgetSnapshot) -> some View {
    HStack(spacing: 4) {
      if let ts = snapshot.updatedAt {
        Image(systemName: "clock")
        Text(Date(timeIntervalSince1970: ts), style: .time)
      }
      if entry.connectionFailed {
        Text(L10n.text("暂时无法连接"))
          .lineLimit(1)
      } else if let subtitle = snapshot.subtitle, !subtitle.isEmpty,
        snapshot.kind == .metrics || snapshot.kind == .list
      {
        Text("· \(subtitle)")
          .lineLimit(1)
      }
    }
    .font(.caption2)
    .foregroundStyle(.secondary)
  }
}

/// 递归渲染 `PluginWidgetNode` 声明式自定义布局树的 SwiftUI 视图（最大深度 5 层）。
struct PluginWidgetCustomNodeView: View {
  let node: PluginWidgetNode
  let pluginId: String
  let widgetKey: String
  let depth: Int

  /// 按节点类型分发容器与原子组件。
  var body: some View {
    if depth <= PluginWidgetNode.maxDepth {
      renderedNode
    }
  }

  @ViewBuilder
  private var renderedNode: some View {
    switch node.type {
    case "column":
      let spacing = CGFloat(node.gap ?? 6)
      let children = node.children ?? []
      VStack(alignment: horizontalAlignment(node.align), spacing: spacing) {
        ForEach(Array(children.enumerated()), id: \.offset) { _, child in
          PluginWidgetCustomNodeView(
            node: child, pluginId: pluginId, widgetKey: widgetKey, depth: depth + 1)
        }
      }
      .modifier(ContainerSurfaceModifier(node: node))

    case "row":
      let spacing = CGFloat(node.gap ?? 8)
      let children = node.children ?? []
      let isSpaceBetween = node.align == "spaceBetween" || node.justify == "spaceBetween"
      HStack(alignment: verticalAlignment(node.align), spacing: spacing) {
        ForEach(Array(children.enumerated()), id: \.offset) { idx, child in
          if isSpaceBetween && idx > 0 {
            Spacer(minLength: 4)
          }
          PluginWidgetCustomNodeView(
            node: child, pluginId: pluginId, widgetKey: widgetKey, depth: depth + 1)
        }
      }
      .modifier(ContainerSurfaceModifier(node: node))

    case "stack", "box":
      let children = node.children ?? []
      ZStack(alignment: Alignment(horizontal: horizontalAlignment(node.align), vertical: .center)) {
        ForEach(Array(children.enumerated()), id: \.offset) { _, child in
          PluginWidgetCustomNodeView(
            node: child, pluginId: pluginId, widgetKey: widgetKey, depth: depth + 1)
        }
      }
      .modifier(ContainerSurfaceModifier(node: node))

    case "text":
      let content = node.text ?? node.label ?? node.valueText ?? ""
      Text(content)
        .font(resolvedFont(size: node.size, weight: node.weight))
        .foregroundStyle(PluginWidgetTonePalette.foreground(node.tone))
        .lineLimit(node.maxLines ?? 2)
        .monospacedDigitIfNeeded(node.monospace == true)

    case "metric":
      VStack(alignment: .leading, spacing: 2) {
        if let label = node.label, !label.isEmpty {
          Text(label)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Text(node.valueText ?? node.text ?? "—")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(PluginWidgetTonePalette.foreground(node.tone))
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        if let sub = node.subValue, !sub.isEmpty {
          Text(sub)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

    case "progress":
      let val = min(max(node.progressValue ?? 0, 0), 1)
      VStack(alignment: .leading, spacing: 3) {
        if node.label != nil || node.valueText != nil {
          HStack {
            if let label = node.label {
              Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let valueText = node.valueText {
              Text(valueText).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                .lineLimit(1)
            }
          }
        }
        ProgressView(value: val)
          .tint(PluginWidgetTonePalette.accent(node.tone))
      }

    case "badge":
      Text(node.text ?? node.label ?? "")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(PluginWidgetTonePalette.badgeForeground(node.tone))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
          Capsule(style: .continuous)
            .fill(PluginWidgetTonePalette.badgeBackground(node.tone))
        )
        .lineLimit(1)

    case "icon":
      Image(systemName: mappedSymbol(node.name))
        .font(resolvedFont(size: node.size, weight: node.weight))
        .foregroundStyle(PluginWidgetTonePalette.foreground(node.tone))

    case "image":
      let w = CGFloat(node.width ?? 44)
      let h = CGFloat(node.height ?? 44)
      let r = CGFloat(node.cornerRadius ?? 10)
      #if canImport(UIKit)
        if let data = PluginWidgetFileStore.readCachedPluginImageData(rawPathOrName: node.url),
          let uiImg = UIImage(data: data)
        {
          Image(uiImage: uiImg)
            .resizable()
            .scaledToFill()
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
        } else {
          RoundedRectangle(cornerRadius: r, style: .continuous)
            .fill(.quaternary)
            .frame(width: w, height: h)
            .overlay(Image(systemName: "photo").font(.caption).foregroundStyle(.secondary))
        }
      #else
        RoundedRectangle(cornerRadius: r, style: .continuous)
          .fill(.quaternary)
          .frame(width: w, height: h)
      #endif

    case "button":
      buttonView

    case "divider":
      Divider()

    case "spacer":
      Spacer(minLength: CGFloat(node.minLength ?? 0))

    default:
      EmptyView()
    }
  }

  @ViewBuilder
  private var buttonView: some View {
    let title = node.label ?? node.text ?? L10n.text("执行")
    let isFilled = node.filled ?? true
    let action = node.action
    if action?.type == "pluginAction", let actId = action?.actionId, !actId.isEmpty {
      Button(
        intent: PluginWidgetActionIntent(
          pluginId: pluginId, widgetKey: widgetKey, actionId: actId)
      ) {
        buttonLabel(title: title, isFilled: isFilled)
      }
      .buttonStyle(.plain)
    } else if let url = resolvedButtonURL(action) {
      Link(destination: url) {
        buttonLabel(title: title, isFilled: isFilled)
      }
      .buttonStyle(.plain)
    } else {
      buttonLabel(title: title, isFilled: isFilled)
    }
  }

  private func buttonLabel(title: String, isFilled: Bool) -> some View {
    Text(title)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(
        isFilled ? Color.white : PluginWidgetTonePalette.badgeForeground(node.tone)
      )
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(
            isFilled
              ? PluginWidgetTonePalette.accent(node.tone)
              : PluginWidgetTonePalette.badgeBackground(node.tone)
          )
      )
      .lineLimit(1)
  }

  private func resolvedButtonURL(_ action: PluginWidgetAction?) -> URL? {
    if action?.type == "openRoute", let route = action?.route, !route.isEmpty {
      var comps = URLComponents()
      comps.scheme = "moviepilot"
      comps.host = "open"
      comps.queryItems = [URLQueryItem(name: "path", value: route)]
      return comps.url
    }
    guard PluginWidgetValidator.isValidPluginId(pluginId) else { return nil }
    let surface = action?.surface == "config" ? "config" : "data"
    return URL(string: "moviepilot://plugin/\(pluginId)?surface=\(surface)")
  }

  private func horizontalAlignment(_ raw: String?) -> HorizontalAlignment {
    switch raw {
    case "center": .center
    case "end": .trailing
    default: .leading
    }
  }

  private func verticalAlignment(_ raw: String?) -> VerticalAlignment {
    switch raw {
    case "start": .top
    case "end": .bottom
    default: .center
    }
  }

  private func resolvedFont(size: String?, weight: String?) -> Font {
    let fontWeight: Font.Weight =
      switch weight {
      case "bold": .bold
      case "semibold": .semibold
      case "medium": .medium
      default: .regular
      }
    return switch size {
    case "xs": .caption2.weight(fontWeight)
    case "sm": .caption.weight(fontWeight)
    case "lg": .headline.weight(fontWeight)
    case "xl": .title3.weight(fontWeight)
    default: .subheadline.weight(fontWeight)
    }
  }

  private func mappedSymbol(_ raw: String?) -> String {
    switch raw {
    case "play": "play.fill"
    case "pause": "pause.fill"
    case "download": "arrow.down.circle"
    case "upload": "arrow.up.circle"
    case "check", "success": "checkmark.circle.fill"
    case "warning": "exclamationmark.triangle.fill"
    case "error", "danger": "xmark.octagon.fill"
    case "music": "music.note"
    case "star": "star.fill"
    case "refresh": "arrow.clockwise"
    default: "sparkles"
    }
  }
}

/// 自定义容器节点的统一内边距与语义底色修饰器。
private struct ContainerSurfaceModifier: ViewModifier {
  let node: PluginWidgetNode

  func body(content: Content) -> some View {
    let pad = CGFloat(node.padding ?? 0)
    let radius = CGFloat(node.cornerRadius ?? 10)
    if let tone = node.tone, tone != "default" {
      content
        .padding(pad)
        .frame(
          maxWidth: node.flex != nil ? .infinity : nil,
          alignment: .leading
        )
        .background(
          RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(PluginWidgetTonePalette.badgeBackground(tone))
        )
    } else if pad > 0 || node.flex != nil {
      content
        .padding(pad)
        .frame(
          maxWidth: node.flex != nil ? .infinity : nil,
          alignment: .leading
        )
    } else {
      content
    }
  }
}

extension View {
  @ViewBuilder
  fileprivate func monospacedDigitIfNeeded(_ enabled: Bool) -> some View {
    if enabled {
      self.monospacedDigit()
    } else {
      self
    }
  }
}

/// 插件小组件语义着色与 `#RRGGBB` 颜色解析工具。
private enum PluginWidgetTonePalette {
  static func foreground(_ tone: String?) -> Color {
    if let hex = colorFromHex(tone) { return hex }
    return switch tone {
    case "muted", "secondary": .secondary
    case "accent", "primary": .accentColor
    case "success": Color(red: 0.13, green: 0.77, blue: 0.37)
    case "warning": Color(red: 0.96, green: 0.62, blue: 0.04)
    case "danger": Color(red: 0.94, green: 0.27, blue: 0.27)
    default: .primary
    }
  }

  static func accent(_ tone: String?) -> Color {
    if let hex = colorFromHex(tone) { return hex }
    return switch tone {
    case "success": Color(red: 0.13, green: 0.77, blue: 0.37)
    case "warning": Color(red: 0.96, green: 0.62, blue: 0.04)
    case "danger": Color(red: 0.94, green: 0.27, blue: 0.27)
    default: .accentColor
    }
  }

  static func badgeForeground(_ tone: String?) -> Color {
    if let hex = colorFromHex(tone) { return hex }
    return switch tone {
    case "success": Color(red: 0.13, green: 0.77, blue: 0.37)
    case "warning": Color(red: 0.96, green: 0.62, blue: 0.04)
    case "danger": Color(red: 0.94, green: 0.27, blue: 0.27)
    case "muted", "secondary": .secondary
    default: .accentColor
    }
  }

  static func badgeBackground(_ tone: String?) -> Color {
    accent(tone).opacity(0.16)
  }

  static func colorFromHex(_ raw: String?) -> Color? {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
      raw.hasPrefix("#"), raw.count == 7,
      let value = UInt32(raw.dropFirst(), radix: 16)
    else { return nil }
    let r = Double((value >> 16) & 0xFF) / 255.0
    let g = Double((value >> 8) & 0xFF) / 255.0
    let b = Double(value & 0xFF) / 255.0
    return Color(red: r, green: g, blue: b)
  }
}
