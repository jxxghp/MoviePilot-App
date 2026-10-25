import MoviePilotCore
import SwiftUI
import WidgetKit

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
        Text(entry.display.state == .empty ? "暂无内容" : (entry.display.message ?? "暂时无法读取"))
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
    case .imports: return "总入库"
    case .subscriptions: return "总订阅"
    case .downloads: return "下载任务"
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
      if let progress = item.progress { ProgressView(value: progress).accessibilityLabel("进度") }
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
        .accessibilityLabel("下载速度 \(download.value)，上传速度 \(upload.value)")
    } else {
      Label(
        entry.display.metrics.first?.value ?? "打开 MoviePilot", systemImage: entry.content.symbol)
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
          Text(entry.display.metrics.first?.value ?? "打开 App")
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
        Text(entry.display.state == .empty ? "暂无内容" : "在 App 中检查小组件")
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
            Label("剩余 \(metric.value)", systemImage: metric.icon.symbol)
              .lineLimit(1).minimumScaleFactor(0.85)
              .accessibilityLabel("\(metric.title) \(metric.value)")
            if entry.display.state == .stale {
              Image(systemName: "clock.badge.exclamationmark")
                .accessibilityLabel("数据待更新")
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
