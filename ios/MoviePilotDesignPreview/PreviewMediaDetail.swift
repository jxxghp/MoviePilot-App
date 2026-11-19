import SwiftUI

/// 媒体详情以大图、明确主操作与少量信息呈现，不引入网页详情页。
@MainActor
struct PreviewMediaDetail: View {
  let media: PreviewMedia
  @EnvironmentObject private var library: PreviewLibrary
  @State private var showResources = false

  /// 内容图像与全局渐变衔接；操作、表单和弹层均为原生组件。
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        ZStack(alignment: .bottomLeading) {
          GeometryReader { geometry in
            Image(media.id).resizable().scaledToFill()
              .frame(width: geometry.size.width, height: geometry.size.height).clipped()
          }.frame(height: 410)
            .mask(
              LinearGradient(
                stops: [
                  .init(color: .white, location: 0), .init(color: .white, location: 0.45),
                  .init(color: .clear, location: 1),
                ],
                startPoint: .top, endPoint: .bottom))
          VStack(alignment: .leading, spacing: 10) {
            Text(media.title).font(.largeTitle.bold())
            Text("\(media.year)  ·  \(media.genre)").font(.subheadline).foregroundStyle(.secondary)
            Label(media.rating, systemImage: "star.fill").foregroundStyle(.yellow)
          }.padding(CinematicStyle.margin)
        }
        VStack(alignment: .leading, spacing: 24) {
          CinematicGlassGroup {
            HStack(spacing: 12) {
              CinematicPrimaryAction(title: "搜索资源", symbol: "magnifyingglass") {
                showResources = true
              }
              .accessibilityIdentifier("preview-search-resources")
              CinematicCircleButton(
                title: library.subscriptions.contains(media.id) ? "取消订阅" : "添加订阅",
                symbol: library.subscriptions.contains(media.id) ? "bookmark.fill" : "bookmark"
              ) { library.toggleSubscription(media) }
            }
          }
          Text("剧情简介").font(.title3.weight(.semibold))
          Text("一段漫长旅程，一次关于勇气与归属的选择。跨越未知的边界，在熟悉与陌生之间寻找答案。")
            .font(.body).lineSpacing(5).foregroundStyle(.white.opacity(0.78))
          CinematicPanel {
            VStack(alignment: .leading, spacing: 14) {
              Label("订阅与媒体库", systemImage: "rectangle.stack").font(.headline)
              HStack {
                Text(library.subscriptions.contains(media.id) ? "正在订阅" : "尚未订阅")
                Spacer()
                Text(library.downloads.contains(media.id) ? "下载中" : "暂无下载任务")
                  .foregroundStyle(.secondary)
              }.font(.subheadline)
            }
          }
          Text("你可能也喜欢").font(.title3.weight(.semibold))
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 13) {
              ForEach(PreviewMedia.theatrical) { item in
                NavigationLink {
                  PreviewMediaDetail(media: item)
                } label: {
                  PreviewPoster(media: item).frame(width: 112)
                }.buttonStyle(.plain)
              }
            }
          }
        }.padding(.horizontal, CinematicStyle.margin).padding(.bottom, 24)
      }
    }
    .background(CinematicBackground()).ignoresSafeArea(edges: .top)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .sheet(isPresented: $showResources) { PreviewResourceSheet(media: media) }
  }
}

/// 资源确认弹层只改变预览内存队列，不发送下载或站点请求。
@MainActor
struct PreviewResourceSheet: View {
  let media: PreviewMedia
  @EnvironmentObject private var library: PreviewLibrary
  @Environment(\.dismiss) private var dismiss
  @State private var source = "全部站点"

  /// 原生选择器、玻璃分组与明确完成反馈覆盖主操作的视觉闭环。
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Text(media.title).font(.title2.bold())
          CinematicPanel {
            Picker("站点", selection: $source) {
              ForEach(["全部站点", "主站", "备用站"], id: \.self) { Text($0) }
            }.tint(.white)
          }
          CinematicPanel {
            VStack(alignment: .leading, spacing: 14) {
              Label("2160p · BluRay · HEVC", systemImage: "film").font(.headline)
              Text("48.6 GB  ·  中文  ·  做种 32").font(.subheadline).foregroundStyle(.secondary)
              Text("优先级匹配").font(.caption.weight(.medium)).foregroundStyle(.green)
              CinematicPrimaryAction(
                title: library.downloads.contains(media.id) ? "已添加到队列" : "添加到下载",
                symbol: "arrow.down"
              ) {
                library.downloads.insert(media.id)
              }.disabled(library.downloads.contains(media.id))
                .accessibilityIdentifier("preview-queue-action")
            }
          }
        }.padding(CinematicStyle.margin)
      }
      .background(CinematicBackground()).navigationTitle("搜索资源").navigationBarTitleDisplayMode(
        .inline
      )
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
      .toolbarBackground(.hidden, for: .navigationBar)
    }.preferredColorScheme(.dark).presentationDetents([.medium, .large])
  }
}
