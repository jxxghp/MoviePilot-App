import MoviePilotSession
import SwiftUI

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

  /// 图片引用不在此处请求或解释成任意 URL，图像边界交由认证宿主处理。
  init(
    id: String, title: String, subtitle: String, synopsis: String,
    rating: String? = nil, backdropReference: String? = nil, logoReference: String? = nil
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.synopsis = synopsis
    self.rating = rating
    self.backdropReference = backdropReference
    self.logoReference = logoReference
  }
}

/// 横向分区保存真实的标题、版式与媒体引用，不在页面中复制搜索/发现 API。
struct NativeDiscoverRail: Identifiable, Hashable {
  /// 区分标准 2:3 竖版海报栏与 16:9 宽幅横图趋势栏。
  enum Style: Hashable { case poster, backdrop }

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

  /// 后端尚无海报时 posterReference 可为空，卡片显示克制的原生缺图态。
  init(
    id: String, title: String, year: String? = nil, detail: String? = nil,
    posterReference: String? = nil, backdropReference: String? = nil,
    identity: NativeMediaIdentity? = nil
  ) {
    self.id = id
    self.title = title
    self.year = year
    self.detail = detail
    self.posterReference = posterReference
    self.backdropReference = backdropReference
    self.identity = identity
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
struct NativeDiscoverProvider: Identifiable {
  let id: String
  let name: String
  let itemCount: Int?
  let artworkReference: String?

  /// 负数量代表无有效计数时按缺失处理，不显示伪造的零片目。
  init(id: String, name: String, itemCount: Int? = nil, artworkReference: String? = nil) {
    self.id = id
    self.name = name
    self.itemCount = itemCount.flatMap { $0 >= 0 ? $0 : nil }
    self.artworkReference = artworkReference
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

/// iOS 26 启用系统顶部软滚动边缘，旧系统保留干净原生行为。
struct NativeSoftTopScrollEdge: ViewModifier {
  /// 顶部滚动内容在状态栏附近自然柔化，避免文字与状态栏硬碰撞。
  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 26, *) {
      content.scrollEdgeEffectStyle(.soft, for: .top)
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
  let onOpenMedia: (String) -> Void
  let onOpenRail: ((String) -> Void)?
  let onOpenProvider: ((String) -> Void)?
  let onOpenCategory: ((String) -> Void)?
  let onPlayContinueWatching: ((NativeDiscoverProgress) -> Void)?
  let onManageModules: (() -> Void)?
  let onRetry: () -> Void
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @State private var scrollOffset: CGFloat = 0
  @State private var selectedFeatureIndex = 0

  /// 页面只消费已认证的业务投影与显式导航动作，默认缺图不发起无身份 URL 请求。
  init(
    session: NativeSession,
    content: NativeDiscoverContent,
    isPreview: Bool = false,
    artwork: @escaping (String?, NativeDiscoverArtworkRole) -> AnyView = {
      reference, role in AnyView(NativeDiscoverArtworkPlaceholder(reference: reference, role: role))
    },
    onOpenSearch: (() -> Void)? = nil,
    onOpenMedia: @escaping (String) -> Void = { _ in },
    onOpenRail: ((String) -> Void)? = nil,
    onOpenProvider: ((String) -> Void)? = nil,
    onOpenCategory: ((String) -> Void)? = nil,
    onPlayContinueWatching: ((NativeDiscoverProgress) -> Void)? = nil,
    onManageModules: (() -> Void)? = nil,
    onRetry: @escaping () -> Void = {}
  ) {
    self.session = session
    self.content = content
    self.isPreview = isPreview
    self.artwork = artwork
    self.onOpenSearch = onOpenSearch
    self.onOpenMedia = onOpenMedia
    self.onOpenRail = onOpenRail
    self.onOpenProvider = onOpenProvider
    self.onOpenCategory = onOpenCategory
    self.onPlayContinueWatching = onPlayContinueWatching
    self.onManageModules = onManageModules
    self.onRetry = onRetry
  }

  /// 主视觉延伸至顶部安全区，随滚动柔和退场并过渡为 Cinematic 烟灰紫底色。
  var body: some View {
    GeometryReader { viewport in
      let heroHeight = resolvedHeroHeight(viewportHeight: viewport.size.height)
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
          featureBackground(
            activeFeature, width: viewport.size.width, height: heroHeight,
            progress: progress, eased: eased
          )
          .id(activeFeature.id)
          .transition(.opacity)
          .ignoresSafeArea(edges: .top)
        }
        ScrollView {
          VStack(spacing: 24) {
            if !content.featuredItems.isEmpty {
              heroCarousel(height: heroHeight)
            }
            LazyVStack(alignment: .leading, spacing: 26) {
              if isPreview, content.featuredItems.isEmpty {
                previewMarker.padding(.horizontal, CinematicStyle.margin)
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
                discoveryStatus.padding(.horizontal, CinematicStyle.margin)
              }
            }
          }
          .frame(maxWidth: .infinity)
          .padding(.bottom, 28)
          .modifier(NativeDiscoverLegacyScrollProbe())
        }
        .coordinateSpace(name: "native-discover-scroll")
        .scrollIndicators(.hidden)
        .modifier(NativeDiscoverScrollClipping())
        .modifier(NativeSoftTopScrollEdge())
        .ignoresSafeArea(edges: .top)
        .modifier(NativeDiscoverScrollObservation(offset: $scrollOffset))
        topSafeAreaVeil(progress: eased, height: max(viewport.safeAreaInsets.top, 48) + 42)
      }
    }
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
      case .doubanShowing: railsByID["doubanShowing"] != nil
      case .doubanTop250: railsByID["doubanTop250"] != nil
      case .latest: railsByID["latest"] != nil
      case .mediaLibrary: hasLibrary
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
      case .doubanShowing:
        if let rail = railsByID["doubanShowing"] { posterRail(rail) }
      case .doubanTop250:
        if let rail = railsByID["doubanTop250"] { posterRail(rail) }
      case .latest:
        if let rail = railsByID["latest"] { posterRail(rail) }
      case .mediaLibrary:
        mediaLibrary
      }
    }
    let knownRailIDs: Set<String> = [
      "movies", "television", "trending", "doubanShowing", "doubanTop250", "latest",
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

  /// 首屏主视觉占约三分之二高度，使首条海报栏在首屏底部自然露出。
  private func resolvedHeroHeight(viewportHeight: CGFloat) -> CGFloat {
    if dynamicTypeSize.isAccessibilitySize {
      return max(580, viewportHeight * 0.78)
    }
    return min(max(viewportHeight * 0.67, 470), 640)
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

  /// 前景退场时平滑衔接到当前主题背景渐变（支持深/浅色与用户自定义背景过渡颜色）。
  @ViewBuilder
  private func ambientSurface(progress: CGFloat) -> some View {
    ZStack {
      CinematicBackground()
      Color(red: 10 / 255, green: 10 / 255, blue: 22 / 255)
        .opacity(max(0, 1 - Double(progress) * 1.15) * 0.55)
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
    return ZStack(alignment: .bottom) {
      artwork(item.backdropReference, .backdrop)
        .frame(width: width, height: backdropHeight)
        .clipped()
        .blur(radius: blurRadius, opaque: false)
      // 底部多段深色压暗保证明亮剧照上的白色文字与评分清晰可读。
      LinearGradient(
        stops: [
          .init(color: .clear, location: 0.36),
          .init(
            color: Color(red: 10 / 255, green: 10 / 255, blue: 22 / 255).opacity(0.45),
            location: 0.64),
          .init(
            color: Color(red: 10 / 255, green: 10 / 255, blue: 22 / 255).opacity(0.86),
            location: 0.86),
          .init(color: Color(red: 10 / 255, green: 10 / 255, blue: 22 / 255), location: 1),
        ], startPoint: .top, endPoint: .bottom
      )
      .frame(width: width, height: backdropHeight)
      .opacity(max(0, 1 - Double(eased) * 0.6))
    }
    .offset(y: parallax)
    .overlay(.black.opacity(Double(eased) * 0.22))
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

  /// 滚动离顶后在状态栏安全区呈现渐进柔化过渡，确保退场标题与正文不与系统状态栏硬重叠。
  private func topSafeAreaVeil(progress: CGFloat, height: CGFloat) -> some View {
    let opacity = Double(progress)
    let surface = Color(red: 43 / 255, green: 39 / 255, blue: 52 / 255)
    return LinearGradient(
      stops: [
        .init(color: surface.opacity(opacity), location: 0),
        .init(color: surface.opacity(0.94 * opacity), location: 0.44),
        .init(color: surface.opacity(0.62 * opacity), location: 0.72),
        .init(color: .clear, location: 1),
      ], startPoint: .top, endPoint: .bottom
    )
    .frame(height: height)
    .ignoresSafeArea(edges: .top)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  /// 多条推荐支持横向滑动切换，底部圆点指示器与 Cinematic 发现首屏一致。
  private func heroCarousel(height: CGFloat) -> some View {
    VStack(spacing: 10) {
      if content.featuredItems.count > 1 {
        TabView(selection: $selectedFeatureIndex) {
          ForEach(Array(content.featuredItems.enumerated()), id: \.element.id) { index, item in
            featureForeground(item, height: height - 22)
              .tag(index)
          }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: height - 22)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: selectedFeatureIndex)
        carouselIndicators
      } else if let item = content.featuredItems.first {
        featureForeground(item, height: height)
      }
    }
    .frame(maxWidth: .infinity)
  }

  /// 圆点指示器只呈现真实推荐数量，不伪造固定数量的装饰点。
  private var carouselIndicators: some View {
    HStack(spacing: 7) {
      ForEach(Array(content.featuredItems.enumerated()), id: \.element.id) { index, _ in
        let selected = index == selectedFeatureIndex
        Circle()
          .fill(.white.opacity(selected ? 0.95 : 0.30))
          .frame(width: selected ? 6.5 : 5.5, height: selected ? 6.5 : 5.5)
          .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selectedFeatureIndex)
      }
    }
    .padding(.top, 2)
    .accessibilityHidden(true)
  }

  /// 标题、评分与简介浮于独立背景上方，随列表正常上移，不与图片捆成卡片。
  private func featureForeground(_ item: NativeDiscoverFeature, height: CGFloat) -> some View {
    Button {
      onOpenMedia(item.id)
    } label: {
      VStack(spacing: 0) {
        Spacer(minLength: 0)
        featureInformation(item)
          .padding(.horizontal, CinematicStyle.margin + 4)
      }
      .frame(maxWidth: .infinity)
      .frame(height: height)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(.white)
    .accessibilityIdentifier("native-discover-feature-\(item.id)")
  }

  /// 海报前景优先展示后端透明媒体标题 Logo，无 Logo 时以电影感大字标题自然降级，下方紧凑排布类型、简介与多维评分标。
  private func featureInformation(_ item: NativeDiscoverFeature) -> some View {
    VStack(alignment: .center, spacing: 8) {
      if let logoRef = item.logoReference, !logoRef.isEmpty {
        NativeDiscoverLogoBanner(
          session: session,
          reference: logoRef,
          fallbackTitle: item.title,
          isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        )
      } else {
        Text(item.title)
          .font(.system(.largeTitle, design: .serif).weight(.bold))
          .tracking(item.title.count <= 6 ? 4 : 1)
          .shadow(color: .black.opacity(0.45), radius: 10, y: 3)
          .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
      }
      if !item.subtitle.isEmpty {
        Text(item.subtitle)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.white.opacity(0.86))
      }
      if !item.synopsis.isEmpty {
        Text(item.synopsis)
          .font(.footnote)
          .foregroundStyle(.white.opacity(0.76))
          .lineLimit(2)
      }
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 12) { featureLabels(item) }
        VStack(alignment: .center, spacing: 6) { featureLabels(item) }
      }
      .font(.caption.weight(.semibold)).foregroundStyle(.white)
      .padding(.top, 2)
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(.bottom, 10)
  }

  /// 参照视觉参考 06 的评分微标排布：紧凑徽章与评分数值并列，辅助字号下自动分行。
  @ViewBuilder private func featureLabels(_ item: NativeDiscoverFeature) -> some View {
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
          .foregroundStyle(.white)
      }
    }
    HStack(spacing: 4) {
      Image(systemName: "star.fill")
        .font(.caption2)
        .foregroundStyle(Color(red: 0.98, green: 0.78, blue: 0.30))
      Text("查看详情")
        .foregroundStyle(.white.opacity(0.88))
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
                  Text(detail).font(.caption).foregroundStyle(.white.opacity(0.58)).lineLimit(1)
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
                onOpenMedia(item.media.id)
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
      .modifier(NativeHorizontalEdgeMargins(horizontal: CinematicStyle.margin))
      .scrollIndicators(.hidden)
    }
  }

  /// 海报或横图轨道边缘出画，窄屏保留三列加右侧探头或 16:9 宽幅趋势卡层次。
  private func posterRail(_ rail: NativeDiscoverRail) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader(rail.title, action: onOpenRail.map { openRail in { openRail(rail.id) } })
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: rail.style == .backdrop ? 13 : 11) {
          ForEach(rail.items) { item in
            Group {
              if item.identity != nil {
                Button {
                  onOpenMedia(item.id)
                } label: {
                  railCard(item, style: rail.style)
                }
                .buttonStyle(.plain)
                .contextMenu {
                  Button {
                    onOpenMedia(item.id)
                  } label: {
                    Label("查看详情", systemImage: "info.circle")
                  }
                  if let onOpenSearch {
                    Button {
                      onOpenSearch()
                    } label: {
                      Label("全局搜索", systemImage: "magnifyingglass")
                    }
                  }
                }
              } else {
                railCard(item, style: rail.style)
              }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("native-discover-poster-\(item.id)")
          }
        }
        .padding(.horizontal, legacyHorizontalPadding)
      }
      .modifier(NativeHorizontalEdgeMargins(horizontal: CinematicStyle.margin))
      .scrollIndicators(.hidden)
    }
  }

  /// 按轨道样式选择 2:3 竖版居中海报或 16:9 宽幅趋势横卡。
  @ViewBuilder
  private func railCard(_ item: NativeDiscoverMedia, style: NativeDiscoverRail.Style) -> some View {
    switch style {
    case .poster:
      poster(item)
    case .backdrop:
      backdropCard(item)
    }
  }

  /// 16:9 宽幅趋势横卡：背景剧照为主视觉，下方左对齐标题与年份/类型摘要。
  private func backdropCard(_ item: NativeDiscoverMedia) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      artwork(item.backdropReference ?? item.posterReference, .continueWatching)
        .aspectRatio(16.0 / 9.0, contentMode: .fill)
        .frame(width: cardWidth, height: cardWidth * 9.0 / 16.0).clipped()
        .clipShape(.rect(cornerRadius: 15))
        .overlay {
          RoundedRectangle(cornerRadius: 15, style: .continuous)
            .strokeBorder(.white.opacity(0.12), lineWidth: 0.6)
        }
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
  private func poster(_ item: NativeDiscoverMedia) -> some View {
    VStack(alignment: .center, spacing: 6) {
      artwork(item.posterReference, .poster)
        .frame(width: posterWidth, height: posterWidth * 1.5).clipped()
        .clipShape(.rect(cornerRadius: 13))
        .overlay {
          RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
        }
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

  /// 媒体库先显示来源平台玻璃横卡，再显示带真实分类海报的多来源探索入口。
  private var mediaLibrary: some View {
    VStack(alignment: .leading, spacing: 14) {
      if !content.providers.isEmpty {
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
        .modifier(NativeHorizontalEdgeMargins(horizontal: CinematicStyle.margin))
        .scrollIndicators(.hidden)
      }
      if !content.categories.isEmpty {
        sectionHeader("分类探索")
        let perRow = dynamicTypeSize.isAccessibilitySize ? 1 : 2
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
                Color.clear.frame(maxWidth: .infinity)
              }
            }
          }
        }
        .padding(.horizontal, CinematicStyle.margin)
      }
    }
  }

  /// 媒体库卡片直接呈现服务端封面原图，不叠加名称遮罩，仅在右上角以轻透角标展示入库数量。
  private func providerArtwork(_ provider: NativeDiscoverProvider) -> some View {
    ZStack(alignment: .topTrailing) {
      artwork(provider.artworkReference, .provider)
        .frame(width: cardWidth, height: 112).clipped()
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
    .frame(width: cardWidth, height: 112)
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
    .padding(.horizontal, CinematicStyle.margin)
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

  /// iOS 16 没有 ScrollView.contentMargins，回退为内容内部水平留白。
  private var legacyHorizontalPadding: CGFloat {
    if #available(iOS 17, *) { return 0 }
    return CinematicStyle.margin
  }

  /// 普通窄屏选用接近 既定深色渐变玻璃的三列加右侧探头海报宽度，大字号自动让出文字空间。
  private var posterWidth: CGFloat { dynamicTypeSize.isAccessibilitySize ? 146 : 112 }

  /// 大字号继续观看和平台横卡保留较宽的文字区域。
  private var cardWidth: CGFloat { dynamicTypeSize.isAccessibilitySize ? 260 : 238 }
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
        .frame(maxWidth: 900)
        .padding(.horizontal, 16)
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
      Color.clear.aspectRatio(2.0 / 3.0, contentMode: .fit)
        .overlay {
          NativeMediaArtwork(
            session: session, reference: item.posterReference, role: .poster, maximumWidth: 420)
        }
        .clipShape(.rect(cornerRadius: 13))
        .overlay {
          RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
        }
      Text(item.title).font(.footnote.weight(.medium)).lineLimit(2)
      if let year = item.year { Text(year).font(.caption).foregroundStyle(.white.opacity(0.56)) }
    }
    .frame(maxWidth: .infinity, alignment: .top)
    .multilineTextAlignment(.center)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  /// 下一页自动加载；只在失败时用系统按钮显式重试同一页。
  private var paginationFooter: some View {
    CinematicPanel(padding: 10) {
      VStack(spacing: 3) {
        if loadRequest != nil {
          ProgressView("正在载入更多…").frame(minHeight: 44)
        } else {
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

  /// 主视觉、海报、平台和继续观看缺图分别使用原生符号说明内容类型。
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.34, green: 0.28, blue: 0.43),
          Color(red: 0.26, green: 0.22, blue: 0.35),
          Color(red: 0.18, green: 0.20, blue: 0.29),
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
      Image(systemName: symbol).font(.system(size: role == .backdrop ? 50 : 28, weight: .light))
        .foregroundStyle(.white.opacity(0.28))
      if role == .backdrop {
        RadialGradient(
          colors: [.clear, .black.opacity(0.28)], center: .center, startRadius: 35, endRadius: 310)
      }
    }
    .accessibilityHidden(true)
  }

  /// 图像角色按数据字段区分，不依赖业务文字解析路由。
  private var symbol: String {
    switch role {
    case .backdrop: "sparkles.tv"
    case .poster: "film"
    case .provider: "play.rectangle.on.rectangle"
    case .continueWatching: "play.rectangle"
    case .logo: "textformat"
    }
  }
}

/// 发现页主视觉透明标题 Logo 视图：经当前实例图片代理无底色加载透明标题图，缺图或加载中平滑降级为电影感大字标题。
@MainActor
private struct NativeDiscoverLogoBanner: View {
  private static let publicLogoHosts: Set<String> = ["assets.fanart.tv", "image.tmdb.org"]
  private static let publicLogoSession: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.httpShouldSetCookies = false
    config.httpCookieStorage = nil
    config.urlCredentialStorage = nil
    config.timeoutIntervalForRequest = 12
    config.timeoutIntervalForResource = 15
    return URLSession(configuration: config)
  }()

  let session: NativeSession
  let reference: String
  let fallbackTitle: String
  let isAccessibilitySize: Bool
  @State private var logoImage: UIImage?

  var body: some View {
    Group {
      if let logoImage {
        Image(uiImage: logoImage)
          .resizable()
          .scaledToFit()
          .frame(maxWidth: 278, maxHeight: 76)
          .shadow(color: .black.opacity(0.55), radius: 12, y: 4)
          .accessibilityLabel(fallbackTitle)
      } else {
        Text(fallbackTitle)
          .font(.system(.largeTitle, design: .serif).weight(.bold))
          .tracking(fallbackTitle.count <= 6 ? 4 : 1)
          .shadow(color: .black.opacity(0.45), radius: 10, y: 3)
          .lineLimit(isAccessibilitySize ? nil : 2)
      }
    }
    .task(id: reference) {
      let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
      let normalized: String
      if trimmed.hasPrefix("/") {
        normalized = "https://image.tmdb.org/t/p/w500" + trimmed
      } else {
        normalized = trimmed
      }
      guard let url = URL(string: normalized) else { return }
      if let response = try? await session.requestImage(url, maximumWidth: 640),
        !Task.isCancelled, !response.data.isEmpty,
        let decoded = UIImage(data: response.data)
      {
        logoImage = decoded
        return
      }
      // 后端图片代理默认白名单不含 Fanart CDN 时，仅对公开片名 Logo 域名使用无凭据、无 Cookie 的临时会话直连。
      guard url.scheme?.lowercased() == "https",
        let host = url.host?.lowercased(),
        Self.publicLogoHosts.contains(host)
      else {
        logoImage = nil
        return
      }
      do {
        var req = URLRequest(url: url)
        req.httpShouldHandleCookies = false
        let (data, response) = try await Self.publicLogoSession.data(for: req)
        guard !Task.isCancelled,
          let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
          !data.isEmpty, data.count <= 4 * 1024 * 1024,
          let decoded = UIImage(data: data)
        else { return }
        logoImage = decoded
      } catch {
        logoImage = nil
      }
    }
  }
}
