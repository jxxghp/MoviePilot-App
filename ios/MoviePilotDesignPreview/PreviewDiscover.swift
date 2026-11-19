import SwiftUI

/// 发现页采用电影主视觉、横向海报与留白，而不是文字/指标卡墙。
@MainActor
struct PreviewDiscover: View {
  @EnvironmentObject private var library: PreviewLibrary
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var showingInfo = false

  /// 首页向上延伸电影图像，底栏由原生 TabView 绘制。
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 30) {
          hero
          VStack(spacing: 32) {
            wideRail
            posterRail("正在热映", media: PreviewMedia.theatrical)
            posterRail("正在播出", media: PreviewMedia.onAir)
          }.padding(.horizontal, CinematicStyle.margin)
            .padding(.bottom, 28)
        }
      }
      .background(CinematicBackground())
      .ignoresSafeArea(edges: .top)
      .toolbar(.hidden, for: .navigationBar)
      .sheet(isPresented: $showingInfo) { PreviewAbout() }
    }
  }

  /// 原生文本叠在独立电影图像之上，状态栏与系统装饰不包含在图片里。
  private var hero: some View {
    ZStack(alignment: .bottom) {
      GeometryReader { geometry in
        Image("odyssey-hero").resizable().scaledToFill()
          .frame(width: geometry.size.width, height: geometry.size.height).clipped()
      }.frame(height: typeSize.isAccessibilitySize ? 650 : 575)
        .mask(
          LinearGradient(
            stops: [
              .init(color: .white, location: 0), .init(color: .white, location: 0.5),
              .init(color: .clear, location: 1),
            ],
            startPoint: .top, endPoint: .bottom))
      VStack(spacing: 11) {
        NavigationLink {
          PreviewMediaDetail(media: .odyssey)
        } label: {
          Text("奥 德 赛").font(.largeTitle.weight(.bold)).foregroundStyle(.white)
        }.accessibilityIdentifier("preview-hero-detail")
        Text("冒险 · 动作 · 2026").font(.subheadline).foregroundStyle(.white.opacity(0.82))
        Text("穿越风暴与神话，踏上一段漫长归途。")
          .font(.footnote).foregroundStyle(.white.opacity(0.74)).lineLimit(2)
        HStack(spacing: 15) {
          Label("8.4", systemImage: "star.fill").foregroundStyle(.yellow)
          Text("TMDB 8.0")
          Text("94% 好评")
        }.font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.85))
        NavigationLink {
          PreviewMediaDetail(media: .odyssey)
        } label: {
          Label("查看详情", systemImage: "arrow.right").font(.footnote.weight(.semibold))
        }.padding(.top, 2).foregroundStyle(.white)
      }.multilineTextAlignment(.center).padding(.horizontal, 24).padding(.bottom, 12)
    }
    .overlay(alignment: .topTrailing) {
      CinematicGlassGroup {
        HStack(spacing: 12) {
          CinematicCircleButton(
            title: library.subscriptions.contains(PreviewMedia.odyssey.id) ? "取消订阅" : "订阅奥德赛",
            symbol: library.subscriptions.contains(PreviewMedia.odyssey.id)
              ? "bookmark.fill" : "bookmark"
          ) { library.toggleSubscription(.odyssey) }
          CinematicCircleButton(title: "关于预览", symbol: "ellipsis") { showingInfo = true }
        }
      }.padding(.trailing, 20).padding(.top, 62)
    }
  }

  /// 横幅与海报承担不同内容比例，避免把每一行都装进玻璃卡片。
  private var wideRail: some View {
    VStack(alignment: .leading, spacing: 14) {
      NavigationLink {
        PreviewPosterGrid(title: "本周趋势", media: [.odyssey] + PreviewMedia.theatrical)
      } label: {
        PreviewSectionTitle(title: "本周趋势")
      }.buttonStyle(.plain)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: 14) {
          wideCard(image: "odyssey-wide", media: .odyssey)
          wideCard(image: "avengers-wide", media: .avengers)
        }
      }
    }
  }

  /// 使用来源中的真正横幅艺术素材，点击后进入原生详情。
  private func wideCard(image: String, media: PreviewMedia) -> some View {
    NavigationLink {
      PreviewMediaDetail(media: media)
    } label: {
      VStack(alignment: .leading, spacing: 7) {
        Image(image).resizable().aspectRatio(16.0 / 9.0, contentMode: .fill)
          .frame(width: 238, height: 134).clipped()
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        Text(media.title).font(.subheadline.weight(.medium))
        Text("\(media.year) · \(media.genre)").font(.caption).foregroundStyle(.secondary)
      }.frame(width: 238, alignment: .leading).foregroundStyle(.primary)
    }.buttonStyle(.plain)
  }

  /// 分区可进入网格，单张海报可进入详情，均保留原生导航返回。
  private func posterRail(_ title: String, media: [PreviewMedia]) -> some View {
    VStack(spacing: 14) {
      NavigationLink {
        PreviewPosterGrid(title: title, media: media)
      } label: {
        PreviewSectionTitle(title: title)
      }.buttonStyle(.plain).accessibilityIdentifier("preview-section-\(title)")
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: 13) {
          ForEach(media) { item in
            NavigationLink {
              PreviewMediaDetail(media: item)
            } label: {
              PreviewPoster(media: item).frame(width: typeSize.isAccessibilitySize ? 154 : 112)
            }.buttonStyle(.plain)
          }
        }
      }
    }
  }
}

/// 海报网格在大字和 iPad 上自动改变列数，不固定设备像素坐标。
@MainActor
struct PreviewPosterGrid: View {
  let title: String
  let media: [PreviewMedia]
  @Environment(\.dynamicTypeSize) private var typeSize

  /// 正常 iPhone 约三列，辅助功能字号放宽单列，标题保持可读。
  var body: some View {
    ScrollView {
      LazyVGrid(
        columns: [
          GridItem(
            .adaptive(minimum: typeSize.isAccessibilitySize ? 155 : 105), spacing: 13,
            alignment: .top)
        ],
        alignment: .leading, spacing: 22
      ) {
        ForEach(media) { item in
          NavigationLink {
            PreviewMediaDetail(media: item)
          } label: {
            PreviewPoster(media: item)
          }.buttonStyle(.plain).accessibilityIdentifier("preview-poster-\(item.id)")
        }
      }.padding(CinematicStyle.margin)
    }
    .background(CinematicBackground()).navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline).toolbarBackground(.hidden, for: .navigationBar)
  }
}

/// 原生搜索用真实输入和内存筛选证明视觉下的键盘/空态交互，不访问后端。
@MainActor
struct PreviewSearch: View {
  @State private var query = ""

  /// 搜索与其它页面共享图片/卡片，数据来源仍明确属于预览。
  var body: some View {
    NavigationStack {
      PreviewPosterGrid(title: "搜索", media: results)
        .searchable(text: $query, prompt: "电影、剧集、人物")
        .overlay {
          if results.isEmpty {
            VStack(spacing: 10) {
              Image(systemName: "magnifyingglass").font(.largeTitle)
              Text("没有找到相关内容").font(.headline)
              Text("试试其它名称").foregroundStyle(.secondary)
            }
          }
        }
    }
  }

  /// 空输入展示可浏览内容，输入变化只筛选当前隔离的数据集。
  private var results: [PreviewMedia] {
    let all = [PreviewMedia.odyssey] + PreviewMedia.theatrical + PreviewMedia.onAir
    return query.isEmpty ? all : all.filter { $0.title.localizedCaseInsensitiveContains(query) }
  }
}
