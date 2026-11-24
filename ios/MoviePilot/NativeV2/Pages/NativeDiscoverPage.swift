import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI
import Vision
import os

/// 发现页展示 API 投影的主视觉、海报分区、继续观看与媒体库分类，不持有身份或网络状态。
struct NativeDiscoverContent {
  let featuredItems: [NativeDiscoverFeature]
  let rails: [NativeDiscoverRail]
  let continueWatching: [NativeDiscoverProgress]
  let providers: [NativeDiscoverProvider]
  let categories: [NativeDiscoverCategory]
  let moduleOrder: [NativeDiscoverModuleID]
  let isLoading: Bool
  let loadFailed: Bool

  /// 首条推荐保持向后兼容，供仅展示单个主视觉的场景直接读取。
  var featured: NativeDiscoverFeature? { featuredItems.first }

  /// 后端当前状态与真实内容一起投影，空结果不会被当作网络成功或演示数据。
  init(
    featured: NativeDiscoverFeature? = nil,
    featuredItems: [NativeDiscoverFeature]? = nil,
    rails: [NativeDiscoverRail],
    continueWatching: [NativeDiscoverProgress], providers: [NativeDiscoverProvider],
    categories: [NativeDiscoverCategory],
    moduleOrder: [NativeDiscoverModuleID] = NativeDiscoverModuleID.allCases,
    isLoading: Bool = false, loadFailed: Bool = false
  ) {
    if let featuredItems {
      self.featuredItems = featuredItems
    } else if let featured {
      self.featuredItems = [featured]
    } else {
      self.featuredItems = []
    }
    self.rails = rails
    self.continueWatching = continueWatching
    self.providers = providers
    self.categories = categories
    self.moduleOrder = moduleOrder
    self.isLoading = isLoading
    self.loadFailed = loadFailed
  }
}

/// 主视觉保留后端媒体标识与图片引用；动作及详情路由由原生宿主决定。
struct NativeDiscoverFeature: Identifiable, Hashable {
  let id: String
  let title: String
  let subtitle: String
  let synopsis: String
  let rating: String?
  let backdropReference: String?
  let logoReference: String?
  let logoLanguage: String?
  let originalLanguage: String?

  /// 图片引用不在此处请求或解释成任意 URL，图像边界交由认证宿主处理。
  init(
    id: String, title: String, subtitle: String, synopsis: String,
    rating: String? = nil, backdropReference: String? = nil, logoReference: String? = nil,
    logoLanguage: String? = nil, originalLanguage: String? = nil
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.synopsis = synopsis
    self.rating = rating
    self.backdropReference = backdropReference
    self.logoReference = logoReference
    self.logoLanguage = logoLanguage
    self.originalLanguage = originalLanguage
  }
}

/// 横向分区保存真实的标题、版式与媒体引用，不在页面中复制搜索/发现 API。
struct NativeDiscoverRail: Identifiable, Hashable {
  /// 区分标准 2:3 竖版海报栏、16:9 宽幅横图趋势栏与 1:1 音乐专辑方卡栏。
  enum Style: Hashable { case poster, backdrop, square }

  let id: String
  let title: String
  let items: [NativeDiscoverMedia]
  let hasMore: Bool
  let style: Style

  /// 首屏海报由发现页载入；后续页只在打开完整分区后请求。
  init(
    id: String, title: String, items: [NativeDiscoverMedia], hasMore: Bool = false,
    style: Style = .poster
  ) {
    self.id = id
    self.title = title
    self.items = items
    self.hasMore = hasMore
    self.style = style
  }
}

/// 海报模型只存呈现字段与服务端图片引用，不由缺省演示数据替代真实内容。
struct NativeDiscoverMedia: Identifiable, Hashable {
  let id: String
  let title: String
  let year: String?
  let detail: String?
  let posterReference: String?
  let backdropReference: String?
  let identity: NativeMediaIdentity?
  let mediaServerItemID: String?
  let mediaServerName: String?
  let mediaServerItemType: String?

  /// 后端尚无海报时 posterReference 可为空，卡片显示克制的原生缺图态。
  init(
    id: String, title: String, year: String? = nil, detail: String? = nil,
    posterReference: String? = nil, backdropReference: String? = nil,
    identity: NativeMediaIdentity? = nil,
    mediaServerItemID: String? = nil,
    mediaServerName: String? = nil,
    mediaServerItemType: String? = nil
  ) {
    self.id = id
    self.title = title
    self.year = year
    self.detail = detail
    self.posterReference = posterReference
    self.backdropReference = backdropReference
    self.identity = identity
    self.mediaServerItemID = mediaServerItemID
    self.mediaServerName = mediaServerName
    self.mediaServerItemType = mediaServerItemType
  }
}

/// 继续观看横卡显示原生进度信息，媒体和片段时间由调用方按当前实例提供。
struct NativeDiscoverProgress: Identifiable {
  let media: NativeDiscoverMedia
  let progress: Double
  let progressLabel: String
  let itemID: String?
  let server: String?

  init(
    media: NativeDiscoverMedia, progress: Double, progressLabel: String,
    itemID: String? = nil, server: String? = nil
  ) {
    self.media = media
    self.progress = progress
    self.progressLabel = progressLabel
    self.itemID = itemID
    self.server = server
  }

  /// 观看项沿用作品标识。
  var id: String { media.id }

  /// 限制绘制值到可见范围，仍原样保留后端提供的时间说明。
  var normalizedProgress: Double { progress.isFinite ? min(max(progress, 0), 1) : 0 }
}

/// 媒体平台横幅是数据标签，不引入远程产品标识或账号请求。
/// 媒体库卡片投影，保留媒体服务器原生浏览与外部深度链接所需元数据。
struct NativeDiscoverProvider: Identifiable {
  let id: String
  let name: String
  let itemCount: Int?
  let artworkReference: String?
  let server: String?
  let serverType: String?
  let serverID: String?
  let itemID: String?
  let libraryType: String?
  let link: String?

  /// 负数量代表无有效计数时按缺失处理，不显示伪造的零片目。
  init(
    id: String, name: String, itemCount: Int? = nil, artworkReference: String? = nil,
    server: String? = nil, serverType: String? = nil, serverID: String? = nil,
    itemID: String? = nil, libraryType: String? = nil, link: String? = nil
  ) {
    self.id = id
    self.name = name
    self.itemCount = itemCount.flatMap { $0 >= 0 ? $0 : nil }
    self.artworkReference = artworkReference
    self.server = server
    self.serverType = serverType
    self.serverID = serverID
    self.itemID = itemID
    self.libraryType = libraryType
    self.link = link
  }
}

/// 媒体库分类卡使用该分类实际代表的海报，而非装饰性应用截图。
struct NativeDiscoverCategory: Identifiable {
  let id: String
  let title: String
  let itemCount: Int?
  let posterReference: String?

  /// 分类标识用于原生浏览回调，卡面图像仍由调用方的实例认证加载器提供。
  init(id: String, title: String, itemCount: Int? = nil, posterReference: String? = nil) {
    self.id = id
    self.title = title
    self.itemCount = itemCount.flatMap { $0 >= 0 ? $0 : nil }
    self.posterReference = posterReference
  }
}

/// 图片引用类型区分横幅、海报、透明标题 Logo 及平台素材，调用方可绑定会话安全的缓存加载器。
enum NativeDiscoverArtworkRole { case backdrop, poster, provider, continueWatching, logo }

/// 顶级发现滚动位置驱动背景图的轻量视差，不改变文字滚动距离。
private struct NativeDiscoverScrollOffsetKey: PreferenceKey {
  static let defaultValue: CGFloat = 0

  /// 当前页面只有一条主滚动轴，最后一个上报位置代表其可见偏移。
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// 只在支持的系统放开滚动裁切，较旧 iOS 使用原生 ScrollView 默认边界。
private struct NativeDiscoverScrollClipping: ViewModifier {
  /// 兼容 iOS 16，同时允许较新系统的图片进入透明导航栏区域。
  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 17, *) {
      content.scrollClipDisabled()
    } else {
      content
    }
  }
}

/// 优先从系统滚动几何取得偏移，避免标签容器中的偏好传播让背景停在首屏。
private struct NativeDiscoverScrollObservation: ViewModifier {
  @Binding var offset: CGFloat

  /// 保留半像素精度以支持丝滑过渡，旧系统继续使用命名坐标空间。
  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 18, *) {
      content.onScrollGeometryChange(for: CGFloat.self) { geometry in
        let raw = -(geometry.contentOffset.y + geometry.contentInsets.top)
        // 主视觉完全退场后（超过 720pt）底色与柔焦均已定格，截断深滚动偏移避免无意义重算与布局振荡。
        let clamped = max(min(raw, 240), -720)
        return (clamped * 2).rounded() / 2
      } action: { _, value in
        if abs(offset - value) >= 0.5 { offset = value }
      }
    } else {
      content.onPreferenceChange(NativeDiscoverScrollOffsetKey.self) { raw in
        let clamped = max(min(raw, 240), -720)
        if abs(offset - clamped) >= 0.5 { offset = clamped }
      }
    }
  }
}

/// 仅在 iOS 18 以下附加滚动位置偏好探测，iOS 18+ 完全交给系统 onScrollGeometryChange 避免布局反馈环。
private struct NativeDiscoverLegacyScrollProbe: ViewModifier {
  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 18, *) {
      content
    } else {
      content.background {
        GeometryReader { geometry in
          Color.clear.preference(
            key: NativeDiscoverScrollOffsetKey.self,
            value: geometry.frame(in: .named("native-discover-scroll")).minY)
        }
      }
    }
  }
}

/// iOS 26 启用系统顶部软滚动边缘，旧系统保留干净原生行为；支持按滚动状态按需开关。
struct NativeSoftTopScrollEdge: ViewModifier {
  var isActive: Bool = true

  /// 顶部滚动内容在状态栏附近自然柔化，避免文字与状态栏硬碰撞；关闭时保持顶部海报完全无遮挡。
  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 26, *) {
      content
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectHidden(!isActive, for: .top)
    } else {
      content
    }
  }
}

/// 横向轨道在屏幕边缘自然出画，使第四张海报按 Cinematic 版式从右侧探出。
private struct NativeHorizontalEdgeMargins: ViewModifier {
  let horizontal: CGFloat

  /// iOS 17+ 使用系统 contentMargins，iOS 16 通过内部水平边距保持一致留白。
  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 17, *) {
      content.contentMargins(.horizontal, horizontal, for: .scrollContent)
    } else {
      content
    }
  }
}

/// Cinematic 原生发现页：全宽视差主视觉、滚动渐隐柔焦背景、边缘出画海报栏与原生导航。
@MainActor
struct NativeDiscoverPage: View {
  let session: NativeSession
  let content: NativeDiscoverContent
  let isPreview: Bool
  let artwork: (String?, NativeDiscoverArtworkRole) -> AnyView
  let onOpenSearch: (() -> Void)?
  let onSearchMedia: ((NativeDiscoverMedia) -> Void)?
  let onSubscribeMedia: ((NativeDiscoverMedia) -> Void)?
  let onOpenMedia: (String) -> Void
  let onOpenRail: ((String) -> Void)?
  let onOpenProvider: ((String) -> Void)?
  let onOpenCategory: ((String) -> Void)?
  let onPlayContinueWatching: ((NativeDiscoverProgress) -> Void)?
  let onOpenContinueWatchingDetail: ((NativeDiscoverProgress) -> Void)?
  let onManageModules: (() -> Void)?
  let onLoadMoreRail: ((String) -> Void)?
  let loadingRailIDs: Set<String>
  let onRefresh: (() async -> Void)?
  let onRetry: () -> Void
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorScheme) private var colorScheme
  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @State private var scrollOffset: CGFloat = 0
  @State private var selectedFeatureIndex = 0
  @State private var containerWidth: CGFloat = 0

  /// 页面只消费已认证的业务投影与显式导航动作，默认缺图不发起无身份 URL 请求。
  init(
    session: NativeSession,
    content: NativeDiscoverContent,
    isPreview: Bool = false,
    artwork: @escaping (String?, NativeDiscoverArtworkRole) -> AnyView = {
      reference, role in AnyView(NativeDiscoverArtworkPlaceholder(reference: reference, role: role))
    },
    onOpenSearch: (() -> Void)? = nil,
    onSearchMedia: ((NativeDiscoverMedia) -> Void)? = nil,
    onSubscribeMedia: ((NativeDiscoverMedia) -> Void)? = nil,
    onOpenMedia: @escaping (String) -> Void = { _ in },
    onOpenRail: ((String) -> Void)? = nil,
    onOpenProvider: ((String) -> Void)? = nil,
    onOpenCategory: ((String) -> Void)? = nil,
    onPlayContinueWatching: ((NativeDiscoverProgress) -> Void)? = nil,
    onOpenContinueWatchingDetail: ((NativeDiscoverProgress) -> Void)? = nil,
    onManageModules: (() -> Void)? = nil,
    onLoadMoreRail: ((String) -> Void)? = nil,
    loadingRailIDs: Set<String> = [],
    onRefresh: (() async -> Void)? = nil,
    onRetry: @escaping () -> Void = {}
  ) {
    self.session = session
    self.content = content
    self.isPreview = isPreview
    self.artwork = artwork
    self.onOpenSearch = onOpenSearch
    self.onSearchMedia = onSearchMedia
    self.onSubscribeMedia = onSubscribeMedia
    self.onOpenMedia = onOpenMedia
    self.onOpenRail = onOpenRail
    self.onOpenProvider = onOpenProvider
    self.onOpenCategory = onOpenCategory
    self.onPlayContinueWatching = onPlayContinueWatching
    self.onOpenContinueWatchingDetail = onOpenContinueWatchingDetail
    self.onManageModules = onManageModules
    self.onLoadMoreRail = onLoadMoreRail
    self.loadingRailIDs = loadingRailIDs
    self.onRefresh = onRefresh
    self.onRetry = onRetry
  }

  /// 主视觉延伸至顶部安全区，随滚动柔和退场并过渡为 Cinematic 烟灰紫底色。
  var body: some View {
    GeometryReader { viewport in
      let viewportWidth = viewport.size.width
      let isCompactLandscape = viewportWidth > viewport.size.height && viewport.size.height < 500
      let hasHorizontalInset =
        viewport.safeAreaInsets.leading > 0 || viewport.safeAreaInsets.trailing > 0
      let backdropWidth =
        hasHorizontalInset
        ? viewportWidth + viewport.safeAreaInsets.leading + viewport.safeAreaInsets.trailing
        : viewportWidth
      let heroHeight = NativeDeviceLayout.discoverHeroHeight(
        width: viewportWidth,
        height: viewport.size.height,
        isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
      )
      let progress = transitionProgress(height: heroHeight)
      let eased = smoothstep(progress)
      let populatedRails = content.rails.filter { !$0.items.isEmpty }
      let hasLibrary = !content.providers.isEmpty || !content.categories.isEmpty
      let hasContent =
        !content.featuredItems.isEmpty || !populatedRails.isEmpty
        || !content.continueWatching.isEmpty || hasLibrary
      let activeFeature = currentFeature
      ZStack(alignment: .top) {
        ambientSurface(progress: eased).ignoresSafeArea()
        if let activeFeature {
          if hasHorizontalInset {
            Color.clear
              .frame(width: viewportWidth, height: 1)
              .overlay(alignment: .topLeading) {
                featureBackground(
                  activeFeature, width: backdropWidth, height: heroHeight,
                  progress: progress, eased: eased
                )
                .ignoresSafeArea(edges: [.top, .horizontal])
              }
              .id(activeFeature.id)
              .transition(.opacity)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          } else {
            featureBackground(
              activeFeature, width: viewportWidth, height: heroHeight,
              progress: progress, eased: eased
            )
            .id(activeFeature.id)
            .transition(.opacity)
            .ignoresSafeArea(edges: .top)
          }
        }
        ScrollView {
          VStack(spacing: isCompactLandscape ? 16 : 24) {
            if !hasContent && content.isLoading {
              NativeDiscoverSkeletonView(
                heroHeight: heroHeight, posterWidth: posterWidth, cardWidth: cardWidth
              )
              .transition(.opacity)
            } else {
              if !content.featuredItems.isEmpty {
                heroCarousel(height: heroHeight, isCompactLandscape: isCompactLandscape)
              }
              LazyVStack(alignment: .leading, spacing: 26) {
                if isPreview, content.featuredItems.isEmpty {
                  previewMarker.padding(.horizontal, horizontalMargin)
                }
                if hasContent {
                  orderedSections(populatedRails: populatedRails, hasLibrary: hasLibrary)
                  if let onManageModules {
                    HStack {
                      Spacer()
                      Button(action: onManageModules) {
                        Label("管理发现模块", systemImage: "slider.horizontal.3")
                          .font(.footnote.weight(.medium))
                          .foregroundStyle(.primary.opacity(0.82))
                          .padding(.horizontal, 16)
                          .padding(.vertical, 10)
                          .background {
                            Capsule()
                              .fill(.primary.opacity(0.09))
                              .overlay {
                                Capsule().strokeBorder(.primary.opacity(0.16), lineWidth: 0.6)
                              }
                          }
                      }
                      .buttonStyle(.plain)
                      .accessibilityIdentifier("native-discover-manage-modules")
                      Spacer()
                    }
                    .padding(.top, 4)
                  }
                }
                if !hasContent || content.loadFailed {
                  discoveryStatus.padding(.horizontal, horizontalMargin)
                }
              }
            }
          }
          .animation(.easeOut(duration: 0.24), value: hasContent)
          .frame(maxWidth: .infinity)
          .padding(.bottom, 28)
          .modifier(NativeDiscoverLegacyScrollProbe())
        }
        .coordinateSpace(name: "native-discover-scroll")
        .scrollIndicators(.hidden)
        .refreshable { await onRefresh?() }
        .modifier(NativeDiscoverScrollClipping())
        .modifier(NativeSoftTopScrollEdge(isActive: eased > 0.01))
        .ignoresSafeArea(edges: .top)
        .modifier(NativeDiscoverScrollObservation(offset: $scrollOffset))
        if eased > 0.005 {
          topSafeAreaVeil(
            progress: eased,
            height: viewport.safeAreaInsets.top > 0 ? viewport.safeAreaInsets.top + 42 : 44
          )
        }
      }
    }
    .nativeTrackContainerWidth($containerWidth)
    .onChange(of: content.featuredItems.map(\.id)) { ids in
      if selectedFeatureIndex >= ids.count { selectedFeatureIndex = 0 }
    }
    .accessibilityIdentifier("native-discover-page")
  }

  /// 按用户持久化的模块顺序渲染发现区块，先过滤出非空项避免 LazyVStack 产生空占位节点。
  @ViewBuilder
  private func orderedSections(
    populatedRails: [NativeDiscoverRail], hasLibrary: Bool
  ) -> some View {
    let railsByID = Dictionary(uniqueKeysWithValues: populatedRails.map { ($0.id, $0) })
    let activeModules = content.moduleOrder.filter { module in
      switch module {
      case .continueWatching: !content.continueWatching.isEmpty
      case .movies: railsByID["movies"] != nil
      case .television: railsByID["television"] != nil
      case .trending: railsByID["trending"] != nil
      case .doubanMusic: railsByID["doubanMusic"] != nil
      case .doubanShowing: railsByID["doubanShowing"] != nil
      case .doubanTop250: railsByID["doubanTop250"] != nil
      case .latest: railsByID["latest"] != nil
      case .mediaLibrary: hasLibrary && !content.providers.isEmpty
      case .categories: !content.categories.isEmpty
      }
    }
    ForEach(activeModules, id: \.self) { module in
      switch module {
      case .continueWatching:
        continueWatching
      case .movies:
        if let rail = railsByID["movies"] { posterRail(rail) }
      case .television:
        if let rail = railsByID["television"] { posterRail(rail) }
      case .trending:
        if let rail = railsByID["trending"] { posterRail(rail) }
      case .doubanMusic:
        if let rail = railsByID["doubanMusic"] { posterRail(rail) }
      case .doubanShowing:
        if let rail = railsByID["doubanShowing"] { posterRail(rail) }
      case .doubanTop250:
        if let rail = railsByID["doubanTop250"] { posterRail(rail) }
      case .latest:
        if let rail = railsByID["latest"] { posterRail(rail) }
      case .mediaLibrary:
        mediaLibrarySection
      case .categories:
        categoriesSection
      }
    }
    let knownRailIDs: Set<String> = [
      "movies", "television", "trending", "doubanMusic", "doubanShowing", "doubanTop250", "latest",
    ]
    let extraRails = populatedRails.filter { !knownRailIDs.contains($0.id) }
    if !extraRails.isEmpty {
      ForEach(extraRails) { rail in
        posterRail(rail)
      }
    }
  }

  /// 当前主视觉与轮播索引保持同步，数据刷新时自动回落至首条有效条目。
  private var currentFeature: NativeDiscoverFeature? {
    guard !content.featuredItems.isEmpty else { return nil }
    let clamped = min(max(selectedFeatureIndex, 0), content.featuredItems.count - 1)
    return content.featuredItems[clamped]
  }

  /// 预览主视觉缺席时仍清楚标明演示数据边界。
  private var previewMarker: some View {
    Text("预览数据")
      .font(.caption.weight(.medium))
      .foregroundStyle(.secondary)
      .accessibilityIdentifier("native-discover-preview-label")
  }

  /// 三次平滑步进避免线性突兀感，让底色、柔焦和透明同步衔接。
  private func smoothstep(_ t: CGFloat) -> CGFloat {
    let clamped = min(max(t, 0), 1)
    return clamped * clamped * (3 - 2 * clamped)
  }

  /// 前景退场时平滑衔接到当前主题背景渐变（深色模式保留首屏微暗压底，浅色模式保持通透明亮底色）。
  @ViewBuilder
  private func ambientSurface(progress: CGFloat) -> some View {
    ZStack {
      CinematicBackground()
      if colorScheme == .dark {
        Color(red: 10 / 255, green: 10 / 255, blue: 22 / 255)
          .opacity(max(0, 1 - Double(progress) * 1.15) * 0.55)
      }
    }
  }

  /// 以主视觉退场距离计算连续进度，向下回滚时自然恢复首屏背景。
  private func transitionProgress(height: CGFloat) -> CGFloat {
    min(max(-scrollOffset / max(height * 0.62, 1), 0), 1)
  }

  /// 主视觉固定于滚动层后方，上滚时轻视差 + 渐进柔焦 + 多段软边溶解，下拉时自然延展。
  private func featureBackground(
    _ item: NativeDiscoverFeature, width: CGFloat, height: CGFloat,
    progress: CGFloat, eased: CGFloat
  ) -> some View {
    let scrollUp = max(-scrollOffset, 0)
    let pullDown = max(scrollOffset, 0)
    let backdropHeight = height * 1.08 + pullDown
    let parallax = reduceMotion ? 0 : -min(scrollUp, height) * 0.07
    let blurRadius: CGFloat = (reduceMotion || reduceTransparency) ? 0 : eased * 18
    let visibility = max(0, 1 - Double(eased) * 0.94)
    let isLight = colorScheme == .light
    let fadeBase =
      isLight
      ? NativeTheme.topVeilColor(for: .light, appearance: appearance)
      : Color(red: 10 / 255, green: 10 / 255, blue: 22 / 255)
    return ZStack(alignment: .bottom) {
      artwork(item.backdropReference, .backdrop)
        .frame(width: width, height: backdropHeight)
        .clipped()
        .blur(radius: blurRadius, opaque: false)
      // 仅底部多段平滑融底：默认首屏顶部保持 100% 无遮挡，仅在向上滚动后呈现顶部渐变模糊。
      LinearGradient(
        stops: isLight
          ? [
            .init(color: .clear, location: 0.34),
            .init(color: fadeBase.opacity(0.56), location: 0.62),
            .init(color: fadeBase.opacity(0.92), location: 0.82),
            .init(color: fadeBase, location: 1),
          ]
          : [
            .init(color: .clear, location: 0.36),
            .init(color: fadeBase.opacity(0.45), location: 0.64),
            .init(color: fadeBase.opacity(0.86), location: 0.86),
            .init(color: fadeBase, location: 1),
          ], startPoint: .top, endPoint: .bottom
      )
      .frame(width: width, height: backdropHeight)
      .opacity(max(0, 1 - Double(eased) * (isLight ? 0.25 : 0.6)))
    }
    .offset(y: parallax)
    .overlay(
      isLight ? fadeBase.opacity(Double(eased) * 0.32) : .black.opacity(Double(eased) * 0.22)
    )
    .mask(alignment: .top) {
      LinearGradient(
        stops: [
          .init(color: .white, location: 0),
          .init(color: .white, location: 0.44),
          .init(color: .white.opacity(0.86), location: 0.60),
          .init(color: .white.opacity(0.42), location: 0.78),
          .init(color: .white.opacity(0.10), location: 0.90),
          .init(color: .clear, location: 1),
        ], startPoint: .top, endPoint: .bottom
      )
      .frame(height: backdropHeight)
      .offset(y: min(scrollOffset, 0) * 0.88)
    }
    .opacity(progress >= 0.99 ? 0 : visibility)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  /// 滚动离顶后在状态栏安全区呈现渐进柔化过渡，浅/深色自动匹配当前背景主题色。
  private func topSafeAreaVeil(progress: CGFloat, height: CGFloat) -> some View {
    let opacity = Double(progress)
    let surface = NativeTheme.topVeilColor(for: colorScheme, appearance: appearance)
    return LinearGradient(
      stops: [
        .init(color: surface.opacity(opacity), location: 0),
        .init(color: surface.opacity(0.94 * opacity), location: 0.44),
        .init(color: surface.opacity(0.62 * opacity), location: 0.72),
        .init(color: .clear, location: 1),
      ], startPoint: .top, endPoint: .bottom
    )
    .frame(height: height)
    .ignoresSafeArea(edges: [.top, .horizontal])
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  /// 多条推荐支持横向滑动切换，底部圆点指示器与 Cinematic 发现首屏一致。
  private func heroCarousel(height: CGFloat, isCompactLandscape: Bool = false) -> some View {
    VStack(spacing: isCompactLandscape ? 6 : 10) {
      if content.featuredItems.count > 1 {
        let pageHeight = max(height - (isCompactLandscape ? 16 : 22), 140)
        TabView(selection: $selectedFeatureIndex) {
          ForEach(Array(content.featuredItems.enumerated()), id: \.element.id) { index, item in
            featureForeground(
              item, height: pageHeight, isCompactLandscape: isCompactLandscape
            )
            .tag(index)
          }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: pageHeight)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: selectedFeatureIndex)
        carouselIndicators
      } else if let item = content.featuredItems.first {
        featureForeground(item, height: height, isCompactLandscape: isCompactLandscape)
      }
    }
    .frame(maxWidth: .infinity)
  }

  /// 圆点指示器只呈现真实推荐数量，浅/深色下均清晰可见。
  private var carouselIndicators: some View {
    HStack(spacing: 7) {
      ForEach(Array(content.featuredItems.enumerated()), id: \.element.id) { index, _ in
        let selected = index == selectedFeatureIndex
        Circle()
          .fill(
            colorScheme == .light
              ? Color.primary.opacity(selected ? 0.84 : 0.24)
              : Color.white.opacity(selected ? 0.95 : 0.30)
          )
          .frame(width: selected ? 6.5 : 5.5, height: selected ? 6.5 : 5.5)
          .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selectedFeatureIndex)
      }
    }
    .padding(.top, 2)
    .accessibilityHidden(true)
  }

  /// 标题、评分与简介浮于独立背景上方，随列表正常上移，深浅色自适应高对比前景。
  private func featureForeground(
    _ item: NativeDiscoverFeature, height: CGFloat, isCompactLandscape: Bool = false
  ) -> some View {
    Button {
      onOpenMedia(item.id)
    } label: {
      VStack(spacing: 0) {
        Spacer(minLength: isCompactLandscape ? 36 : 0)
        featureInformation(item, isCompactLandscape: isCompactLandscape)
          .padding(.horizontal, CinematicStyle.margin + 4)
      }
      .frame(maxWidth: .infinity)
      .frame(height: height)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(colorScheme == .light ? Color.primary : Color.white)
    .accessibilityIdentifier("native-discover-feature-\(item.id)")
  }

  /// 海报前景优先展示后端中文透明媒体标题 Logo，无中文 Logo 时以海报级大字标题自然降级，下方紧凑排布类型、简介与多维评分标。
  private func featureInformation(
    _ item: NativeDiscoverFeature, isCompactLandscape: Bool = false
  ) -> some View {
    let isLight = colorScheme == .light
    let isWide = containerWidth >= 680
    return VStack(alignment: .center, spacing: isCompactLandscape ? 5 : 8) {
      if let logoRef = item.logoReference, !logoRef.isEmpty {
        NativeDiscoverLogoBanner(
          session: session,
          reference: logoRef,
          fallbackTitle: item.title,
          isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
          logoLanguage: item.logoLanguage,
          originalLanguage: item.originalLanguage,
          maxWidth: isCompactLandscape ? 220 : 278,
          maxHeight: isCompactLandscape ? 48 : 76,
          isWide: isWide,
          isCompactLandscape: isCompactLandscape,
          fallbackColor: isLight ? Color.primary : Color.white
        )
      } else {
        NativeHeroPosterTitleView(
          title: item.title,
          isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
          isWide: isWide,
          isCompactLandscape: isCompactLandscape,
          textAlignment: .center,
          color: isLight ? Color.primary : Color.white
        )
      }
      if !item.subtitle.isEmpty {
        Text(item.subtitle)
          .font(isCompactLandscape ? .footnote.weight(.medium) : .subheadline.weight(.medium))
          .foregroundStyle(isLight ? Color.primary.opacity(0.80) : Color.white.opacity(0.86))
          .lineLimit(1)
      }
      if !item.synopsis.isEmpty {
        Text(item.synopsis)
          .font(.footnote)
          .foregroundStyle(isLight ? Color.secondary : Color.white.opacity(0.76))
          .lineLimit(isCompactLandscape ? 1 : 2)
      }
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 12) { featureLabels(item) }
        VStack(alignment: .center, spacing: 6) { featureLabels(item) }
      }
      .font(.caption.weight(.semibold))
      .foregroundStyle(isLight ? Color.primary : Color.white)
      .padding(.top, isCompactLandscape ? 0 : 2)
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: 680, alignment: .center)
    .padding(.bottom, isCompactLandscape ? 6 : 10)
  }

  /// 紧凑评分微标排布：深/浅色均保持高对比可读性。
  @ViewBuilder private func featureLabels(_ item: NativeDiscoverFeature) -> some View {
    let isLight = colorScheme == .light
    if let rating = item.rating, !rating.isEmpty {
      HStack(spacing: 5) {
        Text("TheMovieDB")
          .font(.system(size: 9.5, weight: .heavy))
          .foregroundStyle(.black)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(
            Color(red: 0.42, green: 0.86, blue: 0.78),
            in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        Text(rating)
          .font(.caption.monospacedDigit().weight(.bold))
          .foregroundStyle(isLight ? Color.primary : Color.white)
      }
    }
    HStack(spacing: 4) {
      Image(systemName: "star.fill")
        .font(.caption2)
        .foregroundStyle(
          isLight
            ? Color(red: 0.84, green: 0.56, blue: 0.04) : Color(red: 0.98, green: 0.78, blue: 0.30))
      Text("查看详情")
        .foregroundStyle(isLight ? Color.primary.opacity(0.82) : Color.white.opacity(0.88))
    }
  }

  /// 横向观看记录保持媒体画面与进度在首屏可见，点击仍回到宿主媒体详情。
  private var continueWatching: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader("继续观看")
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: 13) {
          ForEach(content.continueWatching) { item in
            Button {
              if item.itemID != nil, let onPlayContinueWatching {
                onPlayContinueWatching(item)
              } else {
                onOpenMedia(item.media.id)
              }
            } label: {
              VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .bottomLeading) {
                  artwork(item.media.posterReference, .continueWatching)
                    .aspectRatio(16.0 / 9.0, contentMode: .fill)
                    .frame(width: cardWidth, height: cardWidth * 9.0 / 16.0).clipped()
                  LinearGradient(
                    colors: [.clear, .black.opacity(0.68)], startPoint: .center, endPoint: .bottom)
                  VStack(alignment: .leading, spacing: 6) {
                    Text(item.progressLabel)
                      .font(.caption.weight(.semibold)).foregroundStyle(.white)
                    GeometryReader { bar in
                      ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.28))
                        Capsule().fill(.white.opacity(0.92))
                          .frame(width: bar.size.width * item.normalizedProgress)
                      }
                    }
                    .frame(height: 3)
                  }
                  .padding(.horizontal, 11).padding(.bottom, 10)
                }
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay {
                  RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.6)
                }
                Text(item.media.title).font(.subheadline.weight(.medium)).lineLimit(1)
                if let detail = item.media.detail, !detail.isEmpty {
                  Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
              }
              .frame(width: cardWidth, alignment: .leading)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
              if item.itemID != nil, let onPlayContinueWatching {
                Button {
                  onPlayContinueWatching(item)
                } label: {
                  Label("立即播放", systemImage: "play.fill")
                }
              }
              Button {
                if let onOpenContinueWatchingDetail {
                  onOpenContinueWatchingDetail(item)
                } else {
                  onOpenMedia(item.media.id)
                }
              } label: {
                Label("查看详情", systemImage: "info.circle")
              }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("继续观看，\(item.media.title)，\(item.progressLabel)")
            .accessibilityIdentifier("native-discover-continue-\(item.id)")
          }
        }
        .padding(.horizontal, legacyHorizontalPadding)
      }
      .modifier(NativeHorizontalEdgeMargins(horizontal: horizontalMargin))
      .scrollIndicators(.hidden)
    }
  }

  /// 海报或横图轨道边缘出画，窄屏保留三列加右侧探头或 16:9 宽幅趋势卡层次。
  private func posterRail(_ rail: NativeDiscoverRail) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader(rail.title, action: onOpenRail.map { openRail in { openRail(rail.id) } })
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: rail.style == .backdrop ? 13 : 11) {
          ForEach(Array(rail.items.enumerated()), id: \.element.id) { index, item in
            Group {
              if item.identity != nil || item.mediaServerItemID != nil {
                Button {
                  onOpenMedia(item.id)
                } label: {
                  railCard(item, style: rail.style, showExistsBadge: rail.id != "latest")
                }
                .buttonStyle(.plain)
                .contextMenu {
                  Button {
                    onOpenMedia(item.id)
                  } label: {
                    Label("查看详情", systemImage: "info.circle")
                  }
                  if let onSubscribeMedia, item.identity != nil {
                    Button {
                      onSubscribeMedia(item)
                    } label: {
                      Label("订阅", systemImage: "bookmark.fill")
                    }
                  }
                  if let onSearchMedia {
                    Button {
                      onSearchMedia(item)
                    } label: {
                      Label("搜索", systemImage: "magnifyingglass")
                    }
                  } else if let onOpenSearch {
                    Button {
                      onOpenSearch()
                    } label: {
                      Label("搜索", systemImage: "magnifyingglass")
                    }
                  }
                }
              } else {
                railCard(item, style: rail.style, showExistsBadge: rail.id != "latest")
              }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("native-discover-poster-\(item.id)")
            .onAppear {
              if rail.hasMore && !loadingRailIDs.contains(rail.id)
                && index >= max(rail.items.count - 3, 0)
              {
                onLoadMoreRail?(rail.id)
              }
            }
          }
          if loadingRailIDs.contains(rail.id) {
            ProgressView()
              .tint(.primary)
              .frame(width: 48, height: rail.style == .backdrop ? 130 : 156)
          }
        }
        .padding(.horizontal, legacyHorizontalPadding)
      }
      .modifier(NativeHorizontalEdgeMargins(horizontal: horizontalMargin))
      .scrollIndicators(.hidden)
    }
  }

  /// 按轨道样式选择 2:3 竖版居中海报或 16:9 宽幅趋势横卡。
  @ViewBuilder
  private func railCard(
    _ item: NativeDiscoverMedia, style: NativeDiscoverRail.Style, showExistsBadge: Bool = true
  ) -> some View {
    switch style {
    case .poster:
      poster(item, showExistsBadge: showExistsBadge)
    case .backdrop:
      backdropCard(item, showExistsBadge: showExistsBadge)
    case .square:
      squareCard(item)
    }
  }

  /// 1:1 音乐专辑方卡：方形封面居中展示，下方呈现专辑名与艺人/年份副标。
  private func squareCard(_ item: NativeDiscoverMedia) -> some View {
    let side = max(posterWidth + 14, 122)
    return VStack(alignment: .leading, spacing: 6) {
      artwork(item.posterReference, .poster)
        .frame(width: side, height: side).clipped()
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
        }
      Text(item.title)
        .font(.footnote.weight(.medium))
        .foregroundStyle(.primary.opacity(0.95))
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
      let caption = [item.detail, item.year].compactMap { $0 }.filter { !$0.isEmpty }
        .joined(separator: " · ")
      if !caption.isEmpty {
        Text(caption)
          .font(.caption)
          .foregroundStyle(.primary.opacity(0.58))
          .lineLimit(1)
      }
    }
    .frame(width: side, alignment: .leading)
    .contentShape(Rectangle())
  }

  /// 16:9 宽幅趋势横卡：背景剧照为主视觉，下方左对齐标题与年份/类型摘要。
  private func backdropCard(_ item: NativeDiscoverMedia, showExistsBadge: Bool = true) -> some View
  {
    VStack(alignment: .leading, spacing: 7) {
      artwork(item.backdropReference ?? item.posterReference, .continueWatching)
        .aspectRatio(16.0 / 9.0, contentMode: .fill)
        .frame(width: cardWidth, height: cardWidth * 9.0 / 16.0).clipped()
        .clipShape(.rect(cornerRadius: 15))
        .overlay {
          RoundedRectangle(cornerRadius: 15, style: .continuous)
            .strokeBorder(.white.opacity(0.12), lineWidth: 0.6)
        }
        .nativeMediaExistsOverlay(
          session: session,
          source: item.identity?.source,
          mediaID: item.identity?.mediaID,
          title: item.title,
          year: item.year,
          type: item.identity?.type,
          enabled: showExistsBadge
        )
      Text(item.title)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.primary.opacity(0.95))
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
      let subtitle = [item.year, item.detail].compactMap { $0 }.filter { !$0.isEmpty }
        .joined(separator: " · ")
      if !subtitle.isEmpty {
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.primary.opacity(0.58))
          .lineLimit(1)
      }
    }
    .frame(width: cardWidth, alignment: .leading)
    .contentShape(Rectangle())
  }

  /// Cinematic 居中排版海报卡：2:3 比例、细微边缘高光、居中标题与克制年份。
  private func poster(_ item: NativeDiscoverMedia, showExistsBadge: Bool = true) -> some View {
    VStack(alignment: .center, spacing: 6) {
      artwork(item.posterReference, .poster)
        .frame(width: posterWidth, height: posterWidth * 1.5).clipped()
        .clipShape(.rect(cornerRadius: 13))
        .overlay {
          RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
        }
        .nativeMediaExistsOverlay(
          session: session,
          source: item.identity?.source,
          mediaID: item.identity?.mediaID,
          title: item.title,
          year: item.year,
          type: item.identity?.type,
          enabled: showExistsBadge
        )
      Text(item.title)
        .font(.footnote.weight(.medium))
        .foregroundStyle(.primary.opacity(0.95))
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        .frame(maxWidth: .infinity, alignment: .center)
      if let secondaryText = posterCaption(for: item) {
        Text(secondaryText)
          .font(.caption)
          .foregroundStyle(.primary.opacity(0.58))
          .lineLimit(1)
      }
    }
    .multilineTextAlignment(.center)
    .frame(width: posterWidth, alignment: .center)
    .contentShape(Rectangle())
  }

  /// 优先展示简洁年份，缺少年份时才回退展示评分等简短摘要。
  private func posterCaption(for item: NativeDiscoverMedia) -> String? {
    if let year = item.year, !year.isEmpty { return year }
    if let detail = item.detail, !detail.isEmpty { return detail }
    return nil
  }

  /// 独立「媒体库」模块：展示媒体服务器封面横卡。
  private var mediaLibrarySection: some View {
    VStack(alignment: .leading, spacing: 14) {
      sectionHeader("媒体库")
      ScrollView(.horizontal) {
        LazyHStack(spacing: 12) {
          ForEach(content.providers) { provider in
            Group {
              if let onOpenProvider {
                Button {
                  onOpenProvider(provider.id)
                } label: {
                  providerArtwork(provider)
                }
                .buttonStyle(.plain)
              } else {
                providerArtwork(provider)
              }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("native-discover-provider-\(provider.id)")
          }
        }
        .padding(.horizontal, legacyHorizontalPadding)
      }
      .modifier(NativeHorizontalEdgeMargins(horizontal: horizontalMargin))
      .scrollIndicators(.hidden)
    }
  }

  /// 独立「分类浏览」模块：展示带真实海报的多来源分类探索入口，可与媒体库独立开关和排序。
  private var categoriesSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      sectionHeader("分类浏览")
      let perRow = NativeDeviceLayout.discoverCategoryColumns(
        for: containerWidth, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
      let rows = stride(from: 0, to: content.categories.count, by: perRow).map {
        Array(content.categories[$0..<min($0 + perRow, content.categories.count)])
      }
      VStack(spacing: 12) {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
          HStack(spacing: 12) {
            ForEach(row) { category in
              Group {
                if let onOpenCategory {
                  Button {
                    onOpenCategory(category.id)
                  } label: {
                    categoryArtwork(category)
                  }
                  .buttonStyle(.plain)
                } else {
                  categoryArtwork(category)
                }
              }
              .accessibilityElement(children: .combine)
              .accessibilityIdentifier("native-discover-category-\(category.id)")
            }
            if row.count < perRow {
              ForEach(0..<(perRow - row.count), id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity)
              }
            }
          }
        }
      }
      .padding(.horizontal, horizontalMargin)
    }
  }

  /// 媒体库卡片直接呈现服务端封面原图，不叠加名称遮罩，仅在右上角以轻透角标展示入库数量。
  private func providerArtwork(_ provider: NativeDiscoverProvider) -> some View {
    let providerHeight: CGFloat = NativeDeviceLayout.isWideCanvas(containerWidth) ? 136 : 112
    return ZStack(alignment: .topTrailing) {
      artwork(provider.artworkReference, .provider)
        .frame(width: cardWidth, height: providerHeight).clipped()
      if let count = provider.itemCount {
        Text(count.formatted(.number))
          .font(.caption2.monospacedDigit().weight(.bold))
          .foregroundStyle(.white)
          .padding(.horizontal, 8)
          .padding(.vertical, 3.5)
          .background {
            Capsule()
              .fill(.ultraThinMaterial)
              .overlay { Capsule().fill(Color.black.opacity(0.36)) }
              .overlay { Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 0.6) }
          }
          .padding(8)
      }
    }
    .clipShape(.rect(cornerRadius: 19))
    .overlay {
      RoundedRectangle(cornerRadius: 19, style: .continuous)
        .strokeBorder(.white.opacity(0.16), lineWidth: 0.7)
    }
    .frame(width: cardWidth, height: providerHeight)
    .accessibilityLabel(provider.name)
    .accessibilityValue(provider.itemCount.map { "\($0) 项内容" } ?? "")
  }

  /// 没有接入分类查询时保持分类海报信息可见，但不会显示无效操作。
  private func categoryArtwork(_ category: NativeDiscoverCategory) -> some View {
    HStack(spacing: 11) {
      artwork(category.posterReference, .poster)
        .aspectRatio(2.0 / 3.0, contentMode: .fill)
        .frame(width: 46, height: 69).clipped()
        .clipShape(.rect(cornerRadius: 9))
      VStack(alignment: .leading, spacing: 5) {
        Text(category.title).font(.subheadline.weight(.semibold))
          .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
        if let count = category.itemCount {
          Text("\(count) 部").font(.caption).foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
      if onOpenCategory != nil {
        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
          .foregroundStyle(.secondary).accessibilityHidden(true)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
    .padding(10)
    .contentShape(.rect(cornerRadius: CinematicStyle.radius))
    .background { CinematicPanel(padding: 0) { Color.clear } }
  }

  /// 区块头部遵循 Cinematic 极简层级：左侧粗标题、右侧单个原生箭头并保留 44pt 触控区。
  private func sectionHeader(_ title: String, action: (() -> Void)? = nil) -> some View {
    HStack(alignment: .center) {
      Text(title).font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
      Spacer()
      if let action {
        Button(action: action) {
          Image(systemName: "chevron.right")
            .font(.subheadline.weight(.semibold))
            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.84))
        .accessibilityLabel("查看全部\(title)")
        .accessibilityIdentifier("native-discover-more-\(title)")
      }
    }
    .padding(.horizontal, horizontalMargin)
  }

  /// 页面没有可浏览的数据时，用一张卡片反馈当前状态和可用的后续操作。
  private var discoveryStatus: some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 6) {
        if content.isLoading {
          HStack(spacing: 12) {
            ProgressView().tint(.white).accessibilityHidden(true)
            Text("正在载入发现内容…").font(.headline)
          }
        } else if content.loadFailed {
          Label("暂时无法载入发现内容", systemImage: "exclamationmark.triangle")
            .font(.headline)
          Button(action: onRetry) {
            Label("重新载入", systemImage: "arrow.clockwise")
              .frame(minHeight: 44).contentShape(Rectangle())
          }
          .buttonStyle(.plain).accessibilityIdentifier("native-discover-retry")
        } else {
          Label("还没有可展示的内容", systemImage: "sparkles.tv")
            .font(.headline)
          if let onOpenSearch {
            Button(action: onOpenSearch) {
              Label("搜索媒体", systemImage: "magnifyingglass")
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("native-discover-empty-search")
          }
        }
      }
      .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    }
  }

  /// 按当前容器宽度返回发现页外边距（iPad 适度加宽，窄屏保持 16pt）。
  private var horizontalMargin: CGFloat {
    NativeDeviceLayout.horizontalMargin(for: containerWidth)
  }

  /// iOS 16 没有 ScrollView.contentMargins，回退为内容内部水平留白。
  private var legacyHorizontalPadding: CGFloat {
    if #available(iOS 17, *) { return 0 }
    return horizontalMargin
  }

  /// 按当前画布宽度自适应海报宽度（iPhone 3 列加探头，iPad 宽屏清晰大海报）。
  private var posterWidth: CGFloat {
    NativeDeviceLayout.discoverPosterWidth(
      for: containerWidth, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
  }

  /// 按当前画布宽度自适应 16:9 横幅卡宽度。
  private var cardWidth: CGFloat {
    NativeDeviceLayout.discoverCardWidth(
      for: containerWidth, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
  }
}

/// 发现栏目的完整海报网格从首屏快照开始，保留已浏览作品并独立翻页。
@MainActor
struct NativeDiscoverRailGrid<Destination: View>: View {
  private let session: NativeSession
  private let rail: NativeDiscoverRail
  private let loadPage: (Int) async throws -> (items: [NativeDiscoverMedia], hasMore: Bool)
  private let destination: (NativeMediaIdentity) -> Destination

  @State private var items: [NativeDiscoverMedia]
  @State private var hasMore: Bool
  @State private var seenPageIDs: Set<Set<String>>
  @State private var nextPage = 2
  @State private var loadRequest: UUID?
  @State private var loadFailed = false
  @ScaledMetric(relativeTo: .body) private var tileWidth = 104.0

  /// 沿用当前栏目第一页，下一页才向相同实例请求，浏览详情期间保留网格状态。
  init(
    session: NativeSession, rail: NativeDiscoverRail,
    loadPage: @escaping (Int) async throws -> (items: [NativeDiscoverMedia], hasMore: Bool),
    @ViewBuilder destination: @escaping (NativeMediaIdentity) -> Destination
  ) {
    self.session = session
    self.rail = rail
    self.loadPage = loadPage
    self.destination = destination
    var initialIDs: Set<String> = []
    _items = State(initialValue: rail.items.filter { initialIDs.insert($0.id).inserted })
    _hasMore = State(initialValue: rail.hasMore)
    _seenPageIDs = State(initialValue: [initialIDs])
  }

  /// 系统网格保留 Cinematic 三列海报密度，大字号和宽屏按可用空间自动决定列数。
  var body: some View {
    let request = loadRequest
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(spacing: 24) {
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: tileWidth), spacing: 11)], spacing: 18
          ) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
              Group {
                if let identity = item.identity {
                  NavigationLink {
                    destination(identity)
                  } label: {
                    tile(item)
                  }
                  .buttonStyle(.plain)
                } else if let msItemID = item.mediaServerItemID, !msItemID.isEmpty {
                  NavigationLink {
                    NativeMediaServerDetailPage(
                      session: session,
                      server: item.mediaServerName,
                      itemID: msItemID,
                      fallbackTitle: item.title,
                      fallbackItemType: item.mediaServerItemType,
                      fallbackPoster: item.posterReference
                    )
                  } label: {
                    tile(item)
                  }
                  .buttonStyle(.plain)
                } else {
                  tile(item)
                }
              }
              .accessibilityIdentifier("native-discover-grid-poster-\(item.id)")
              .onAppear { requestNextPageIfNeeded(afterShowing: index) }
            }
          }
          if loadRequest != nil || loadFailed { paginationFooter }
        }
        .frame(maxWidth: 1240)
        .padding(.horizontal, NativeDeviceLayout.isIPad ? 24 : 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .modifier(NativeSoftTopScrollEdge())
    }
    .navigationTitle(rail.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .accessibilityIdentifier("native-discover-grid")
    .task(id: request) {
      if let request { await appendPage(for: request) }
    }
  }

  /// 作品缺少规范详情身份时仍保留可浏览的海报和居中元数据。
  private func tile(_ item: NativeDiscoverMedia) -> some View {
    VStack(spacing: 6) {
      Color.clear.aspectRatio(rail.style == .square ? 1.0 : 2.0 / 3.0, contentMode: .fit)
        .overlay {
          NativeMediaArtwork(
            session: session, reference: item.posterReference, role: .poster, maximumWidth: 420)
        }
        .clipShape(.rect(cornerRadius: 13))
        .overlay {
          RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
        }
        .nativeMediaExistsOverlay(
          session: session,
          source: item.identity?.source,
          mediaID: item.identity?.mediaID,
          title: item.title,
          year: item.year,
          type: item.identity?.type,
          enabled: rail.id != "latest" && rail.style != .square
        )
      Text(item.title).font(.footnote.weight(.medium)).lineLimit(2)
      if let year = item.year { Text(year).font(.caption).foregroundStyle(.secondary) }
    }
    .frame(maxWidth: .infinity, alignment: .top)
    .multilineTextAlignment(.center)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  /// 下一页自动加载仅显示简洁转圈图标（无方框无文案）；仅失败时展示重试按钮。
  @ViewBuilder
  private var paginationFooter: some View {
    if loadRequest != nil {
      ProgressView()
        .tint(.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    } else {
      CinematicPanel(padding: 10) {
        VStack(spacing: 4) {
          Text("暂时无法载入更多作品").font(.footnote).foregroundStyle(.secondary)
          Button("重试") {
            loadFailed = false
            loadRequest = UUID()
          }
          .frame(minHeight: 44)
          .accessibilityIdentifier("native-discover-grid-retry")
        }
      }
    }
  }

  /// 最后几张海报进入原生滚动缓冲区时启动下一页，无需翻页按钮。
  private func requestNextPageIfNeeded(afterShowing index: Int) {
    guard hasMore, !loadFailed, loadRequest == nil, index >= max(items.count - 3, 0) else {
      return
    }
    loadRequest = UUID()
  }

  /// 关闭栏目时任务取消；乱序、失败或重复响应不会覆盖页面和分页位置。
  private func appendPage(for request: UUID) async {
    guard loadRequest == request, hasMore, !Task.isCancelled else { return }
    defer {
      if loadRequest == request { loadRequest = nil }
    }
    do {
      let page = try await loadPage(nextPage)
      guard loadRequest == request, !Task.isCancelled else { return }
      let incomingIDs = Set(page.items.map(\.id))
      guard !incomingIDs.isEmpty, seenPageIDs.insert(incomingIDs).inserted else {
        hasMore = false
        return
      }
      var seenIDs = Set(items.map(\.id))
      let additions = page.items.filter { seenIDs.insert($0.id).inserted }
      guard !additions.isEmpty else {
        hasMore = false
        return
      }
      items.append(contentsOf: additions)
      hasMore = page.hasMore
      nextPage += 1
    } catch {
      guard loadRequest == request, !Task.isCancelled, !(error is CancellationError) else { return }
      loadFailed = true
    }
  }
}

/// 无图片时提供轻量系统占位符；它只用于缺图状态，不伪装为媒体海报。
@MainActor
private struct NativeDiscoverArtworkPlaceholder: View {
  let reference: String?
  let role: NativeDiscoverArtworkRole

  /// 图片加载前仅呈现极简空白占位框，不显示占位背景图或系统图标。
  var body: some View {
    Rectangle()
      .fill(Color.primary.opacity(0.05))
      .accessibilityHidden(true)
  }
}

/// 缓存当前实例的媒体元数据语言设置（后端 `TMDB_LOCALE`），无服务端值时平滑回退到当前 App 语言。
@MainActor
final class NativeMediaLanguageStore: ObservableObject {
  static let shared = NativeMediaLanguageStore()

  @Published private var localesByInstance: [UUID: String] = [:]
  private var inFlightInstances: Set<UUID> = []

  private init() {}

  /// 当前实例生效的媒体语言代码（优先服务端 `TMDB_LOCALE`，否则回退 App 语言）。
  func preferredMediaLanguage(for session: NativeSession) -> String {
    if let configured = localesByInstance[session.scope.instanceID],
      !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return configured
    }
    return AppLanguage.current.rawValue
  }

  /// 更新指定实例的媒体语言缓存（供系统设置保存或刷新后即时生效）。
  func update(_ locale: String?, for instanceID: UUID) {
    let trimmed = locale?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if trimmed.isEmpty {
      localesByInstance.removeValue(forKey: instanceID)
    } else if localesByInstance[instanceID] != trimmed {
      localesByInstance[instanceID] = trimmed
    }
  }

  /// 从后端静默同步当前实例的 `TMDB_LOCALE`：优先所有用户可读的 `/system/global/user`，旧版后端下管理员再回退 `/system/env`。
  func refresh(using session: NativeSession, force: Bool = false) async {
    let instanceID = session.scope.instanceID
    if !force, localesByInstance[instanceID] != nil { return }
    guard inFlightInstances.insert(instanceID).inserted else { return }
    defer { inFlightInstances.remove(instanceID) }

    struct LocalePayload: Decodable, Sendable {
      let tmdbLocale: String?
      private enum CodingKeys: String, CodingKey {
        case tmdbLocale = "TMDB_LOCALE"
      }
    }
    struct LocaleEnvelope: Decodable, Sendable {
      let data: LocalePayload?
      let tmdbLocale: String?
      private enum CodingKeys: String, CodingKey {
        case data
        case tmdbLocale = "TMDB_LOCALE"
      }
      var resolvedLocale: String? {
        let nested = data?.tmdbLocale?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let nested, !nested.isEmpty { return nested }
        let direct = tmdbLocale?.trimmingCharacters(in: .whitespacesAndNewlines)
        return direct?.isEmpty == false ? direct : nil
      }
    }

    if let endpoint = try? APIEndpoint(path: ["system", "global", "user"]),
      let response = try? await session.request(
        endpoint, as: LocaleEnvelope.self, requiring: .init(category: .discovery)
      ).value,
      let locale = response.resolvedLocale
    {
      update(locale, for: instanceID)
      return
    }

    if session.user.isSuperuser,
      let endpoint = try? APIEndpoint(path: ["system", "env"]),
      let response = try? await session.request(endpoint, as: LocaleEnvelope.self).value,
      let locale = response.resolvedLocale
    {
      update(locale, for: instanceID)
    }
  }
}

/// 海报级大字标题：当作品没有匹配当前媒体语言设置的透明 Logo 时，在发现页、媒体详情与媒体库详情提供统一电影感大字片名。
@MainActor
struct NativeHeroPosterTitleView: View {
  let title: String
  let isAccessibilitySize: Bool
  var isWide: Bool = false
  var isCompactLandscape: Bool = false
  var textAlignment: TextAlignment = .center
  var color: Color? = nil

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let count = trimmed.count
    let isLight = colorScheme == .light
    let resolvedColor = color ?? (isLight ? Color.primary : Color.white)
    let pointSize: CGFloat =
      if isCompactLandscape {
        if count <= 4 {
          30
        } else if count <= 8 {
          26
        } else {
          22
        }
      } else if count <= 4 {
        isWide ? 48 : 42
      } else if count <= 8 {
        isWide ? 42 : 36
      } else {
        isWide ? 35 : 30
      }
    let tracking: CGFloat =
      if count <= 4 {
        isCompactLandscape ? 3 : 5
      } else if count <= 8 {
        isCompactLandscape ? 1.5 : 2.5
      } else {
        1
      }

    Text(trimmed.isEmpty ? title : trimmed)
      .font(
        isAccessibilitySize
          ? .system(isCompactLandscape ? .title2 : .largeTitle, design: .serif).weight(.bold)
          : .system(size: pointSize, weight: count <= 4 ? .heavy : .bold, design: .serif)
      )
      .tracking(isAccessibilitySize ? 1 : tracking)
      .foregroundStyle(resolvedColor)
      .multilineTextAlignment(textAlignment)
      .lineSpacing(isCompactLandscape ? 1.5 : 3)
      .lineLimit(isAccessibilitySize ? nil : (isCompactLandscape ? 1 : 2))
      .minimumScaleFactor(isAccessibilitySize ? 1.0 : 0.72)
      .shadow(color: isLight ? .clear : .black.opacity(0.68), radius: 14, y: 4)
      .shadow(color: isLight ? .clear : .black.opacity(0.32), radius: 4, y: 1)
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// 主视觉与详情页共用透明标题 Logo 视图：仅当 Logo 语言适配当前用户的媒体语言设置时展示图片，否则回退为海报级大字标题。
@MainActor
struct NativeDiscoverLogoBanner: View {
  nonisolated private static let publicLogoHosts: Set<String> = [
    "assets.fanart.tv", "image.tmdb.org",
  ]
  nonisolated private static let publicLogoSession: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.httpShouldSetCookies = false
    config.httpCookieStorage = nil
    config.urlCredentialStorage = nil
    config.timeoutIntervalForRequest = 12
    config.timeoutIntervalForResource = 15
    return URLSession(configuration: config)
  }()
  nonisolated private static let languageVerdictCache = OSAllocatedUnfairLock<[String: Bool]>(
    initialState: [:])

  let session: NativeSession
  let reference: String
  let fallbackTitle: String
  let isAccessibilitySize: Bool
  var logoLanguage: String? = nil
  var originalLanguage: String? = nil
  var maxWidth: CGFloat = 278
  var maxHeight: CGFloat = 76
  var isWide: Bool = false
  var isCompactLandscape: Bool = false
  var textAlignment: TextAlignment = .center
  var fallbackColor: Color? = nil
  @ObservedObject private var mediaLanguageStore = NativeMediaLanguageStore.shared
  @State private var logoImage: UIImage?

  var body: some View {
    let preferredLanguage = mediaLanguageStore.preferredMediaLanguage(for: session)
    let decision = NativeMediaLogoLanguagePolicy.metadataDecision(
      logoLanguage: logoLanguage,
      preferredMediaLanguage: preferredLanguage
    )
    let key = logoCacheKey
    let verdictKey =
      "\(key)|\(NativeMediaLogoLanguagePolicy.baseLanguageCode(preferredLanguage) ?? preferredLanguage)"
    let cachedVerdict = Self.languageVerdictCache.withLock { $0[verdictKey] }
    let resolved: UIImage? = {
      switch decision {
      case .confirmedMismatch:
        return nil
      case .confirmedMatch:
        return logoImage ?? NativeMediaArtworkCache.shared.memoryImage(for: key)
      case .needsImageVerification:
        guard cachedVerdict == true else { return nil }
        return logoImage ?? NativeMediaArtworkCache.shared.memoryImage(for: key)
      }
    }()

    return Group {
      if let resolved {
        Image(uiImage: resolved)
          .resizable()
          .scaledToFit()
          .frame(maxWidth: maxWidth, maxHeight: maxHeight)
          .shadow(color: .black.opacity(0.55), radius: 12, y: 4)
          .accessibilityLabel(fallbackTitle)
      } else {
        NativeHeroPosterTitleView(
          title: fallbackTitle,
          isAccessibilitySize: isAccessibilitySize,
          isWide: isWide,
          isCompactLandscape: isCompactLandscape,
          textAlignment: textAlignment,
          color: fallbackColor
        )
      }
    }
    .task(id: "\(logoTaskKey)|\(preferredLanguage)") {
      await mediaLanguageStore.refresh(using: session)
      let activeLanguage = mediaLanguageStore.preferredMediaLanguage(for: session)
      let currentDecision = NativeMediaLogoLanguagePolicy.metadataDecision(
        logoLanguage: logoLanguage,
        preferredMediaLanguage: activeLanguage
      )
      if currentDecision == .confirmedMismatch {
        logoImage = nil
        return
      }
      let activeVerdictKey =
        "\(key)|\(NativeMediaLogoLanguagePolicy.baseLanguageCode(activeLanguage) ?? activeLanguage)"
      if currentDecision == .needsImageVerification,
        let cached = Self.languageVerdictCache.withLock({ $0[activeVerdictKey] }), !cached
      {
        logoImage = nil
        return
      }

      let candidate: UIImage?
      if let cached = NativeMediaArtworkCache.shared.memoryImage(for: key) {
        candidate = cached
      } else {
        let scopeDir = NativeMediaArtworkCache.scopeDirectoryName(for: session)
        if let disk = await NativeMediaArtworkCache.shared.diskImage(
          for: key, scopeDir: scopeDir, limit: 640)
        {
          candidate = disk
        } else {
          let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
          let normalized: String
          if trimmed.hasPrefix("/") {
            normalized = "https://image.tmdb.org/t/p/w500" + trimmed
          } else {
            normalized = trimmed
          }
          guard let url = URL(string: normalized) else { return }
          candidate = await NativeMediaArtworkCache.shared.fetchAndCache(
            key: key, scopeDir: scopeDir, limit: 640
          ) {
            if let response = try? await session.requestImage(url, maximumWidth: 640),
              !response.data.isEmpty
            {
              return response.data
            }
            guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              Self.publicLogoHosts.contains(host)
            else { throw URLError(.badURL) }
            var req = URLRequest(url: url)
            req.httpShouldHandleCookies = false
            let (data, response) = try await Self.publicLogoSession.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              !data.isEmpty, data.count <= 4 * 1024 * 1024
            else { throw URLError(.badServerResponse) }
            return data
          }
        }
      }

      guard !Task.isCancelled, let candidate else { return }

      if currentDecision == .confirmedMatch {
        logoImage = candidate
        return
      }

      if let cached = Self.languageVerdictCache.withLock({ $0[activeVerdictKey] }) {
        logoImage = cached ? candidate : nil
        return
      }

      guard let cgImage = candidate.cgImage else { return }
      let origLang = originalLanguage
      let accepted = await Task.detached(priority: .userInitiated) {
        Self.verifyLogoMatchesMediaLanguage(
          cgImage: cgImage,
          preferredMediaLanguage: activeLanguage,
          originalLanguage: origLang
        )
      }.value
      Self.languageVerdictCache.withLock { $0[activeVerdictKey] = accepted }
      guard !Task.isCancelled else { return }
      logoImage = accepted ? candidate : nil
    }
  }

  private var logoCacheKey: String {
    "hero-logo|\(session.scope.instanceID.uuidString)|\(session.scope.userID)|\(reference)"
  }

  private var logoTaskKey: String {
    "\(logoCacheKey)|\(logoLanguage ?? "")|\(originalLanguage ?? "")"
  }

  /// 将透明 PNG Logo 叠放在高对比纯色底上做本地 Vision 文字识别，兼容旧版未返回 `logo_language` 的后端。
  nonisolated private static func verifyLogoMatchesMediaLanguage(
    cgImage: CGImage,
    preferredMediaLanguage: String,
    originalLanguage: String?
  ) -> Bool {
    let targetImage = compositeOnContrastingBackground(cgImage) ?? cgImage
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
    request.usesLanguageCorrection = false
    let handler = VNImageRequestHandler(cgImage: targetImage, options: [:])
    do {
      try handler.perform([request])
    } catch {
      return NativeMediaLogoLanguagePolicy.matches(
        logoLanguage: originalLanguage,
        preferredMediaLanguage: preferredMediaLanguage
      )
    }
    let recognized = (request.results ?? [])
      .compactMap { $0.topCandidates(1).first?.string }
      .joined(separator: " ")
    return NativeMediaLogoLanguagePolicy.evaluateRecognizedText(
      recognized,
      preferredMediaLanguage: preferredMediaLanguage,
      originalLanguage: originalLanguage
    )
  }

  /// 采样不透明像素亮度并铺设反色纯底，防止白字透明 Logo 在默认白底上丢失轮廓。
  nonisolated private static func compositeOnContrastingBackground(_ cgImage: CGImage) -> CGImage? {
    let sampleSize = 48
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    var samplePixels = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)
    guard
      let sampleCtx = CGContext(
        data: &samplePixels,
        width: sampleSize,
        height: sampleSize,
        bitsPerComponent: 8,
        bytesPerRow: sampleSize * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
      )
    else { return nil }
    sampleCtx.clear(CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))
    sampleCtx.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

    var luminanceSum = 0.0
    var opaqueCount = 0
    for idx in stride(from: 0, to: samplePixels.count, by: 4) {
      let alpha = Double(samplePixels[idx + 3])
      if alpha > 40 {
        let scale = 255.0 / alpha
        let r = min(255.0, Double(samplePixels[idx]) * scale) / 255.0
        let g = min(255.0, Double(samplePixels[idx + 1]) * scale) / 255.0
        let b = min(255.0, Double(samplePixels[idx + 2]) * scale) / 255.0
        luminanceSum += 0.299 * r + 0.587 * g + 0.114 * b
        opaqueCount += 1
      }
    }
    let useDarkBackground = opaqueCount == 0 || (luminanceSum / Double(opaqueCount)) > 0.45

    let maxDim: CGFloat = 640
    let srcW = CGFloat(cgImage.width)
    let srcH = CGFloat(cgImage.height)
    let ratio = min(1.0, maxDim / max(srcW, srcH, 1))
    let drawW = max(1, Int((srcW * ratio).rounded()))
    let drawH = max(1, Int((srcH * ratio).rounded()))
    let pad = 20
    let outW = drawW + pad * 2
    let outH = drawH + pad * 2

    guard
      let outCtx = CGContext(
        data: nil,
        width: outW,
        height: outH,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
      )
    else { return nil }

    if useDarkBackground {
      outCtx.setFillColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1.0)
    } else {
      outCtx.setFillColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1.0)
    }
    outCtx.fill(CGRect(x: 0, y: 0, width: outW, height: outH))
    outCtx.interpolationQuality = .high
    outCtx.draw(cgImage, in: CGRect(x: pad, y: pad, width: drawW, height: drawH))
    return outCtx.makeImage()
  }
}
