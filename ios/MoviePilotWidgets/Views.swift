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
    VStack(alignment: .leading, spacing: 8) {
      header
      if entry.display.metrics.isEmpty && entry.display.items.isEmpty {
        Spacer(minLength: 0)
        Text(entry.display.state == .empty ? "暂无内容" : (entry.display.message ?? "暂时无法读取"))
          .font(.subheadline).foregroundStyle(.secondary).fixedSize(
            horizontal: false, vertical: true)
        Spacer(minLength: 0)
      } else {
        ViewThatFits(in: .vertical) {
          VStack(alignment: .leading, spacing: 6) { details }
          compactMetrics
        }
        Spacer(minLength: 0)
      }
      footer
    }
  }

  /// 概览用四项指标，其余内容展示主指标和有限媒体摘要，数量不从采样列表推算。
  @ViewBuilder private var details: some View {
    if entry.content == .overview && family != .systemSmall {
      LazyVGrid(
        columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12
      ) {
        ForEach(entry.display.metrics.prefix(family == .systemLarge ? 6 : 4), id: \.id) { metric in
          metricView(metric)
        }
      }
    } else {
      compactMetrics
      if family == .systemSmall {
        if !hasTransferMetrics {
          HStack(spacing: 12) {
            ForEach(entry.display.metrics.dropFirst().prefix(2), id: \.id) { metric in
              VStack(alignment: .leading, spacing: 2) {
                Text(metric.value).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(
                  0.7)
                Text(metric.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
              }
            }
          }
        }
      } else if !entry.display.items.isEmpty {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 8 : 6) {
          ForEach(
            entry.display.items.prefix(
              family == .systemLarge ? 6 : (entry.content == .downloads ? 2 : 3)), id: \.id
          ) { item in
            if let url = entry.display.link {
              Link(destination: url) { itemView(item) }.buttonStyle(.plain)
            } else {
              itemView(item)
            }
          }
        }
      } else if !hasTransferMetrics {
        HStack(alignment: .top, spacing: 16) {
          ForEach(entry.display.metrics.dropFirst().prefix(3), id: \.id) { metric in
            metricView(metric)
          }
        }
      }
    }
  }

  /// 只识别明确的速度指标，不把旧服务的任务总数当作下载速度。
  private var hasTransferMetrics: Bool {
    entry.content == .downloads
      && entry.display.metrics.contains { $0.id == "downloadSpeed" }
      && entry.display.metrics.contains { $0.id == "uploadSpeed" }
  }

  /// 小尺寸保证两种速度可读；其余尺寸追加实际下载目录剩余空间，缺失时不伪造零值。
  @ViewBuilder private var compactMetrics: some View {
    if hasTransferMetrics {
      let metrics = entry.display.metrics.filter {
        $0.id == "downloadSpeed" || $0.id == "uploadSpeed"
          || (family != .systemSmall && $0.id == "freeSpace")
      }
      if family == .systemSmall {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(metrics, id: \.id) { metric in
            HStack(spacing: 5) {
              Image(systemName: metric.icon.symbol).foregroundStyle(.tint).widgetAccentable()
              Text(metric.value).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(
                0.6)
            }.accessibilityLabel("\(metric.title) \(metric.value)")
          }
        }
      } else {
        HStack(alignment: .top, spacing: 8) {
          ForEach(metrics, id: \.id) { metric in metricView(metric) }
        }
      }
    } else {
      primaryMetric
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
        Text(metric.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
    } else {
      Text(entry.display.title).font(.headline).lineLimit(1)
    }
  }

  /// 辅助指标使用语义符号及二级标题，兼容系统深浅色和桌面着色。
  private func metricView(_ metric: WidgetMetric) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Label(metric.title, systemImage: metric.icon.symbol)
        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
      Text(metric.value).font(.headline).lineLimit(1).minimumScaleFactor(0.65).monospacedDigit()
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
      if family == .systemLarge, entry.content != .downloads, let subtitle = item.subtitle,
        !subtitle.isEmpty
      {
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
