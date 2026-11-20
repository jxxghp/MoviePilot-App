import Charts
import SwiftUI

/// 工作台将 MoviePilot 的服务/媒体/任务语义放入 深色渐变玻璃式透底卡片，数据仅供设计。
@MainActor
struct PreviewDashboard: View {
  @EnvironmentObject private var library: PreviewLibrary
  private let traffic = [2, 5, 4, 12, 7, 18, 24, 21, 36, 28, 39, 33]

  /// 系统大标题、两列状态卡和原生图表提供紧凑而可读的信息层级。
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          HStack(spacing: 12) {
            Image(systemName: "server.rack").font(.title2)
            VStack(alignment: .leading, spacing: 4) {
              Text("我的 MoviePilot").font(.headline)
              Label("服务运行正常", systemImage: "circle.fill").font(.caption).foregroundStyle(.green)
            }
            Spacer()
            Text("11月19日 周四").font(.caption).foregroundStyle(.secondary)
          }.padding(.vertical, 6)
          LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            metric("电影", value: "6,281", symbol: "film", color: .purple)
            metric("剧集", value: "1,604", symbol: "tv", color: .cyan)
          }
          CinematicPanel {
            VStack(alignment: .leading, spacing: 16) {
              HStack {
                Text("下载速率").foregroundStyle(.secondary)
                Spacer()
                Text("最近 1 小时").font(.caption).foregroundStyle(.secondary)
              }
              HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("33.2").font(.system(.largeTitle, design: .rounded).weight(.semibold))
                Text("MB/s").foregroundStyle(.secondary)
                Spacer()
                Text("\(library.downloads.count) 个任务").font(.subheadline).foregroundStyle(
                  .secondary)
              }
              Chart(Array(traffic.enumerated()), id: \.offset) { point in
                AreaMark(x: .value("分钟", point.offset * 5), y: .value("MB/s", point.element))
                  .foregroundStyle(
                    LinearGradient(
                      colors: [.purple.opacity(0.38), .purple.opacity(0)], startPoint: .top,
                      endPoint: .bottom))
                LineMark(x: .value("分钟", point.offset * 5), y: .value("MB/s", point.element))
                  .interpolationMethod(.catmullRom).foregroundStyle(.purple.opacity(0.9))
              }
              .chartYScale(domain: 0...50).chartXAxis(.hidden).chartYAxis(.hidden)
              .frame(height: 90).accessibilityLabel("最近一小时下载速率图")
              HStack {
                Text("21:30")
                Spacer()
                Text("22:30")
              }
              .font(.caption2).foregroundStyle(.secondary)
            }
          }
          CinematicPanel {
            VStack(alignment: .leading, spacing: 16) {
              HStack {
                Text("存储空间").font(.headline)
                Spacer()
                Text("8.6 / 16 TB").font(.subheadline).foregroundStyle(.secondary)
              }
              ProgressView(value: 0.5375).tint(.cyan)
              HStack(spacing: 16) {
                Label("媒体", systemImage: "circle.fill").foregroundStyle(.cyan)
                Label("可用 7.4 TB", systemImage: "circle.fill").foregroundStyle(.white.opacity(0.45))
              }.font(.caption)
            }
          }
          HStack {
            Text("最近订阅").font(.title3.weight(.semibold))
            Spacer()
            Text("\(library.subscriptions.count) 部").foregroundStyle(.secondary)
          }
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 13) {
              ForEach(PreviewMedia.onAir.filter { library.subscriptions.contains($0.id) }) {
                media in
                NavigationLink {
                  PreviewMediaDetail(media: media)
                } label: {
                  PreviewPoster(media: media).frame(width: 112)
                }.buttonStyle(.plain)
              }
            }
          }
        }.padding(CinematicStyle.margin).frame(maxWidth: 960)
          .frame(maxWidth: .infinity).padding(.bottom, 16)
      }
      .background(CinematicBackground()).navigationTitle("工作台")
      .toolbarBackground(.hidden, for: .navigationBar)
    }
  }

  /// 指标有明确图标与数值，色彩仅用作语义强调，不额外包嵌套卡片。
  private func metric(_ title: String, value: String, symbol: String, color: Color) -> some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 12) {
        Image(systemName: symbol).font(.title2).foregroundStyle(color)
        Text(value).font(.system(.title, design: .rounded).weight(.semibold))
        Text(title).font(.subheadline).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// 订阅页复用真实海报组件，订阅状态可由详情页的原生按钮改变。
@MainActor
struct PreviewSubscriptions: View {
  @EnvironmentObject private var library: PreviewLibrary

  /// 正常、空态都留在同一渐变界面内；编辑行为不通过网页完成。
  var body: some View {
    NavigationStack {
      PreviewPosterGrid(
        title: "我的订阅",
        media: ([.odyssey] + PreviewMedia.onAir).filter { library.subscriptions.contains($0.id) }
      )
      .overlay {
        if library.subscriptions.isEmpty {
          VStack(spacing: 12) {
            Image(systemName: "bookmark").font(.largeTitle)
            Text("还没有订阅").font(.headline)
            Text("发现喜欢的电影与剧集，再添加到这里。")
              .font(.subheadline).foregroundStyle(.secondary)
          }.padding(24)
        }
      }
    }
  }
}
