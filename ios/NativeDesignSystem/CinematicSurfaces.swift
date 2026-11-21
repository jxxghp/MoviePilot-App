import SwiftUI
import UIKit

/// 全局自适应语义色彩体系：基于 iOS UIColor 动态 trait 自动响应深色/浅色主题，统一保障导航栏底色、角标、胶囊、状态色与输入框的高对比可读性。
enum NativeTheme {
  /// 构造自动响应深/浅色环境的动态 SwiftUI Color。
  static func adaptive(light: UIColor, dark: UIColor) -> Color {
    Color(
      uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? dark : light
      })
  }

  // MARK: - 语义状态文字与图标色（浅色深饱和高对比，深色柔和明亮）
  static let success = adaptive(
    light: UIColor(red: 0.08, green: 0.54, blue: 0.28, alpha: 1),
    dark: UIColor(red: 0.46, green: 0.90, blue: 0.64, alpha: 1))
  static let warning = adaptive(
    light: UIColor(red: 0.74, green: 0.42, blue: 0.03, alpha: 1),
    dark: UIColor(red: 1.00, green: 0.80, blue: 0.42, alpha: 1))
  static let danger = adaptive(
    light: UIColor(red: 0.80, green: 0.16, blue: 0.20, alpha: 1),
    dark: UIColor(red: 1.00, green: 0.54, blue: 0.58, alpha: 1))
  static let info = adaptive(
    light: UIColor(red: 0.10, green: 0.44, blue: 0.84, alpha: 1),
    dark: UIColor(red: 0.46, green: 0.78, blue: 1.00, alpha: 1))
  static let brand = adaptive(
    light: UIColor(red: 0.40, green: 0.22, blue: 0.78, alpha: 1),
    dark: UIColor(red: 0.84, green: 0.74, blue: 1.00, alpha: 1))
  static let pink = adaptive(
    light: UIColor(red: 0.76, green: 0.18, blue: 0.46, alpha: 1),
    dark: UIColor(red: 0.96, green: 0.56, blue: 0.74, alpha: 1))
  static let cyan = adaptive(
    light: UIColor(red: 0.05, green: 0.50, blue: 0.62, alpha: 1),
    dark: UIColor(red: 0.46, green: 0.84, blue: 0.90, alpha: 1))

  // MARK: - 胶囊 / 角标 / 输入框 / 次级文案
  static let chipFill = adaptive(
    light: UIColor(white: 0.0, alpha: 0.055),
    dark: UIColor(white: 1.0, alpha: 0.09))
  static let chipBorder = adaptive(
    light: UIColor(white: 0.0, alpha: 0.11),
    dark: UIColor(white: 1.0, alpha: 0.15))
  static let chipText = adaptive(
    light: UIColor(white: 0.14, alpha: 0.88),
    dark: UIColor(white: 1.0, alpha: 0.86))
  static let badgeFill = adaptive(
    light: UIColor(white: 0.0, alpha: 0.06),
    dark: UIColor(white: 1.0, alpha: 0.10))
  static let badgeMutedText = adaptive(
    light: UIColor(white: 0.28, alpha: 0.82),
    dark: UIColor(white: 1.0, alpha: 0.68))
  static let fieldFill = adaptive(
    light: UIColor(white: 0.0, alpha: 0.055),
    dark: UIColor(white: 1.0, alpha: 0.09))
  static let fieldBorder = adaptive(
    light: UIColor(white: 0.0, alpha: 0.10),
    dark: UIColor(white: 1.0, alpha: 0.14))
  static let primaryButtonBackground = adaptive(
    light: UIColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 1),
    dark: UIColor(white: 1.0, alpha: 0.94))
  static let primaryButtonForeground = adaptive(
    light: UIColor.white,
    dark: UIColor(red: 0.12, green: 0.10, blue: 0.16, alpha: 1))
  static let divider = adaptive(
    light: UIColor(white: 0.0, alpha: 0.09),
    dark: UIColor(white: 1.0, alpha: 0.11))

  /// 根据当前外观与背景色板计算顶部状态栏安全区柔和遮罩色（浅色模式无缝贴合浅色底，深色模式无缝贴合深色底）。
  @MainActor
  static func topVeilColor(for colorScheme: ColorScheme, appearance: NativeAppearanceStore) -> Color
  {
    if let first = appearance.backgroundStops(for: colorScheme).first?.color {
      return first
    }
    return colorScheme == .light
      ? Color(red: 0.94, green: 0.93, blue: 0.99)
      : Color(red: 0.17, green: 0.15, blue: 0.21)
  }
}

/// 统一自适应小角标组件：深浅色主题下均保证高对比度与柔和边框层次。
@MainActor
struct NativeAdaptiveBadge: View {
  let text: String
  let tint: Color?
  let filled: Bool

  init(_ text: String, tint: Color? = nil, filled: Bool = false) {
    self.text = text
    self.tint = tint
    self.filled = filled
  }

  var body: some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(
        filled ? Color.white : (tint ?? NativeTheme.chipText)
      )
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background {
        if filled, let tint {
          Capsule().fill(tint)
        } else if let tint {
          Capsule()
            .fill(tint.opacity(0.14))
            .overlay { Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 0.6) }
        } else {
          Capsule()
            .fill(NativeTheme.chipFill)
            .overlay { Capsule().strokeBorder(NativeTheme.chipBorder, lineWidth: 0.6) }
        }
      }
  }
}

/// 统一自适应筛选/切换胶囊按钮：选中态高对比实色白字，未选态自适应磨砂底与清晰边框文字。
@MainActor
struct NativeAdaptivePill: View {
  let title: String
  let symbol: String?
  let isSelected: Bool
  let tint: Color?

  @ObservedObject private var appearance = NativeAppearanceStore.shared

  init(_ title: String, symbol: String? = nil, isSelected: Bool, tint: Color? = nil) {
    self.title = title
    self.symbol = symbol
    self.isSelected = isSelected
    self.tint = tint
  }

  var body: some View {
    let activeColor = tint ?? appearance.accentColor
    HStack(spacing: 5) {
      if let symbol {
        Image(systemName: symbol)
          .font(.caption2.weight(.semibold))
      }
      Text(title)
        .font(.caption.weight(.semibold))
        .lineLimit(1)
    }
    .foregroundStyle(isSelected ? Color.white : NativeTheme.chipText)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background {
      if isSelected {
        Capsule().fill(activeColor)
      } else {
        Capsule()
          .fill(NativeTheme.chipFill)
          .overlay { Capsule().strokeBorder(NativeTheme.chipBorder, lineWidth: 0.7) }
      }
    }
  }
}

/// Cinematic 单一视觉体系的基础常量；不读取旧版主题、主色或壁纸偏好。
@MainActor
enum CinematicStyle {
  static let margin: CGFloat = 20
  static let radius: CGFloat = 24
  static let background = Color(red: 0.16, green: 0.16, blue: 0.23)
  static let solidSurface = Color(red: 0.28, green: 0.23, blue: 0.32)
  static let separator = Color.white.opacity(0.10)
}

/// 所有原生页面共用连续背景渐变，随用户选择的深/浅色主题及背景过渡配色实时更新，延伸到系统安全区后方。
@MainActor
struct CinematicBackground: View {
  @Environment(\.colorScheme) private var colorScheme
  @ObservedObject private var appearance = NativeAppearanceStore.shared

  /// 背景静止以减少干扰，也避免减弱动态模式下仍有装饰性移动。
  var body: some View {
    LinearGradient(
      stops: appearance.backgroundStops(for: colorScheme),
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    ).ignoresSafeArea().allowsHitTesting(false)
  }
}

/// Cinematic 透明玻璃分组；在深色下透出渐变底色，在浅色下呈现通透磨砂白玻璃层次。
@MainActor
struct CinematicPanel<Content: View>: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.colorScheme) private var colorScheme
  @ObservedObject private var appearance = NativeAppearanceStore.shared
  private let padding: CGFloat
  private let showsShadow: Bool
  private let content: Content

  /// 统一边距和圆角，同时允许表单行使用零内边距或禁用阴影避免在 Form 单元格内被裁切。
  init(padding: CGFloat = 18, showsShadow: Bool = true, @ViewBuilder content: () -> Content) {
    self.padding = padding
    self.showsShadow = showsShadow
    self.content = content()
  }

  /// 降低透明度时换为同色系实底，浅色与深色自动匹配边框高光与投影深度。
  var body: some View {
    let isLight = colorScheme == .light
    let borderColors: [Color] =
      isLight
      ? [
        .white.opacity(0.85),
        .black.opacity(contrast == .increased ? 0.20 : 0.08),
        appearance.accentColor.opacity(0.18),
      ]
      : [
        .white.opacity(contrast == .increased ? 0.42 : 0.20),
        .white.opacity(contrast == .increased ? 0.28 : 0.075),
        .white.opacity(contrast == .increased ? 0.35 : 0.12),
      ]
    content
      .padding(padding)
      .clipShape(shape)
      .modifier(
        CinematicPanelSurface(
          reduceTransparency: reduceTransparency,
          contrast: contrast,
          colorScheme: colorScheme,
          accentColor: appearance.accentColor
        )
      )
      .overlay(
        shape.strokeBorder(
          LinearGradient(colors: borderColors, startPoint: .topLeading, endPoint: .bottomTrailing),
          lineWidth: contrast == .increased ? 1 : 0.7
        ).allowsHitTesting(false)
      )
      .shadow(
        color: showsShadow ? (isLight ? .black.opacity(0.055) : .black.opacity(0.08)) : .clear,
        radius: showsShadow ? (isLight ? 8 : 10) : 0,
        y: showsShadow ? (isLight ? 3 : 5) : 0)
  }

  /// 相关卡片、表单与状态面板采用相同的连续圆角。
  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: CinematicStyle.radius, style: .continuous)
  }
}

/// 正文以轻系统材质和主题强调色染色透出底色；支持深色暗透玻璃与浅色磨砂白玻璃。
@MainActor
private struct CinematicPanelSurface: ViewModifier {
  let reduceTransparency: Bool
  let contrast: ColorSchemeContrast
  let colorScheme: ColorScheme
  let accentColor: Color

  @ViewBuilder
  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: CinematicStyle.radius, style: .continuous)
    let isLight = colorScheme == .light
    if reduceTransparency {
      content.background(
        isLight ? Color(red: 0.97, green: 0.97, blue: 0.99) : CinematicStyle.solidSurface,
        in: shape)
    } else if isLight {
      content.background {
        ZStack {
          shape.fill(.ultraThinMaterial).opacity(contrast == .increased ? 0.92 : 0.76)
          shape.fill(Color.white.opacity(contrast == .increased ? 0.78 : 0.56))
          shape.fill(
            LinearGradient(
              colors: [accentColor.opacity(0.05), .clear, accentColor.opacity(0.03)],
              startPoint: .topLeading, endPoint: .bottomTrailing))
        }
      }
    } else {
      content.background {
        ZStack {
          shape.fill(.ultraThinMaterial).opacity(contrast == .increased ? 0.45 : 0.12)
          shape.fill(
            LinearGradient(
              colors: [
                accentColor.opacity(0.08),
                accentColor.opacity(0.05),
                Color(red: 0.70, green: 0.39, blue: 0.59).opacity(0.08),
              ],
              startPoint: .topLeading, endPoint: .bottomTrailing))
        }
      }
    }
  }
}

/// 成组悬浮交互共享原生玻璃容器；iOS 16–25 保留相同布局与系统材质降级。
@MainActor
struct CinematicGlassGroup<Content: View>: View {
  private let content: Content

  /// 调用方只提供真正的导航或动作控件，不把不可交互内容标成交互玻璃。
  init(@ViewBuilder content: () -> Content) { self.content = content() }

  /// 可用性隔离使 App 的最低系统保持 iOS 16。
  var body: some View {
    if #available(iOS 26, *) {
      GlassEffectContainer(spacing: 16) { content }
    } else {
      content
    }
  }
}

/// 圆形原生悬浮动作；效果位于尺寸/外观修饰之后并且仅应用于真实按钮。
@MainActor
struct CinematicCircleButton: View {
  let title: String
  let symbol: String
  let action: () -> Void
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  /// 复用系统玻璃按钮，旧系统使用受支持的材质，而非手写模糊滤镜。
  var body: some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 19, weight: .semibold))
        .frame(width: 46, height: 46)
    }
    .buttonStyle(.plain)
    .foregroundStyle(.primary)
    .modifier(CinematicInteractiveGlass(reduceTransparency: reduceTransparency))
    .accessibilityLabel(title)
  }
}

/// 私有修饰器统一玻璃可用性与降级，不向静态卡片添加触摸变形效果。
@MainActor
private struct CinematicInteractiveGlass: ViewModifier {
  let reduceTransparency: Bool
  @Environment(\.colorScheme) private var colorScheme

  /// 布局已由按钮定义，最后再附着玻璃以匹配指定技能的修饰器顺序。
  @ViewBuilder
  func body(content: Content) -> some View {
    if reduceTransparency {
      content.background(
        colorScheme == .light ? Color.white : CinematicStyle.solidSurface, in: Circle())
    } else if #available(iOS 26, *) {
      content.glassEffect(.regular.interactive(), in: .circle)
    } else {
      content.background(.ultraThinMaterial, in: Circle())
        .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 0.7))
    }
  }
}

/// 主要动作保持清楚的胶囊层级，使用原生玻璃突出按钮及早期系统回退。
@MainActor
struct CinematicPrimaryAction: View {
  let title: String
  let symbol: String
  let action: () -> Void
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.colorScheme) private var colorScheme
  @ObservedObject private var appearance = NativeAppearanceStore.shared

  /// 按钮本身保留原生语义和动态字体，深色白底黑字、浅色主题强调色底白字。
  var body: some View {
    let buttonTint: Color = colorScheme == .light ? appearance.accentColor : .white
    let labelColor: Color =
      colorScheme == .light
      ? .white
      : (isEnabled ? Color.black : Color.white)
    if #available(iOS 26, *), !reduceTransparency {
      button.buttonStyle(.glassProminent).tint(buttonTint)
        .foregroundStyle(labelColor)
    } else {
      button.buttonStyle(.borderedProminent).tint(buttonTint)
        .foregroundStyle(labelColor)
    }
  }

  /// 最小触控高度与文字大小独立，辅助功能字号下允许按钮自然增高。
  private var button: some View {
    Button(action: action) {
      Label(title, systemImage: symbol).font(.body.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: 40).padding(.vertical, 4)
    }.buttonBorderShape(.capsule)
  }
}

/// 高透液态玻璃弹层与悬浮输入容器表面：iOS 26+ 使用原生 `.glassEffect(.regular.interactive())`，旧系统回退高透毛玻璃加镜面描边。
@MainActor
struct NativeLiquidGlassPopoverSurface: ViewModifier {
  let cornerRadius: CGFloat
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorScheme) private var colorScheme

  @ViewBuilder
  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    if reduceTransparency {
      content
        .background(
          colorScheme == .light ? Color.white : CinematicStyle.solidSurface, in: shape
        )
        .overlay {
          shape.strokeBorder(
            colorScheme == .light ? Color.black.opacity(0.12) : Color.white.opacity(0.20),
            lineWidth: 0.7)
        }
        .shadow(
          color: colorScheme == .light ? .black.opacity(0.12) : .black.opacity(0.32),
          radius: 14, y: 8)
    } else if #available(iOS 26, *) {
      content
        .background {
          shape.fill(colorScheme == .light ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
        }
        .glassEffect(.regular.interactive(), in: shape)
        .shadow(
          color: colorScheme == .light ? .black.opacity(0.10) : .black.opacity(0.28),
          radius: 14, y: 8)
    } else {
      content
        .background {
          shape
            .fill(.ultraThinMaterial)
            .overlay {
              shape.fill(
                LinearGradient(
                  colors: [
                    Color.white.opacity(colorScheme == .light ? 0.42 : 0.14),
                    Color.white.opacity(colorScheme == .light ? 0.18 : 0.04),
                  ],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                ))
            }
            .overlay {
              shape.strokeBorder(
                LinearGradient(
                  colors: [
                    Color.white.opacity(colorScheme == .light ? 0.65 : 0.34),
                    Color.white.opacity(colorScheme == .light ? 0.18 : 0.08),
                  ],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                ),
                lineWidth: 0.8)
            }
        }
        .shadow(
          color: colorScheme == .light ? .black.opacity(0.12) : .black.opacity(0.32),
          radius: 14, y: 8)
    }
  }
}

// MARK: - 全局占位骨架屏（Skeleton）加载过渡体系

/// 轻量呼吸动效修饰符：单层统一驱动整个骨架屏区块的明暗过渡，自动尊重系统「减弱动态效果」设置。
@MainActor
struct NativeSkeletonShimmerModifier: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var pulsing = false

  func body(content: Content) -> some View {
    content
      .opacity(reduceMotion ? 0.84 : (pulsing ? 0.50 : 1.0))
      .onAppear {
        guard !reduceMotion, !pulsing else { return }
        withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
          pulsing = true
        }
      }
      .accessibilityHidden(true)
  }
}

extension View {
  /// 为骨架屏容器附加统一的柔和呼吸占位动效。
  func nativeSkeletonShimmer() -> some View {
    modifier(NativeSkeletonShimmerModifier())
  }
}

/// 语义自适应骨架占位色块：深色模式使用柔和白透色、浅色模式使用柔和灰透色，贴合 Cinematic 玻璃体系。
@MainActor
struct NativeSkeletonBlock: View {
  var width: CGFloat? = nil
  var height: CGFloat
  var cornerRadius: CGFloat = 8
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      .fill(colorScheme == .light ? Color.black.opacity(0.085) : Color.white.opacity(0.11))
      .frame(width: width, height: height)
      .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
      .accessibilityHidden(true)
  }
}

/// 发现页占位骨架布局：对齐全幅主视觉、2:3 海报横栏与 16:9 横幅横栏，消除初次进入空白闪跳。
@MainActor
struct NativeDiscoverSkeletonView: View {
  var heroHeight: CGFloat = 460
  var posterWidth: CGFloat = 112
  var cardWidth: CGFloat = 238

  var body: some View {
    VStack(alignment: .leading, spacing: 26) {
      ZStack(alignment: .bottom) {
        NativeSkeletonBlock(height: heroHeight, cornerRadius: 0)
        VStack(spacing: 12) {
          NativeSkeletonBlock(width: 210, height: 36, cornerRadius: 10)
          NativeSkeletonBlock(width: 150, height: 14, cornerRadius: 7)
          HStack(spacing: 10) {
            NativeSkeletonBlock(width: 112, height: 38, cornerRadius: 19)
            NativeSkeletonBlock(width: 84, height: 38, cornerRadius: 19)
          }
          .padding(.top, 4)
        }
        .padding(.bottom, 28)
      }

      ForEach(0..<2, id: \.self) { _ in
        VStack(alignment: .leading, spacing: 12) {
          NativeSkeletonBlock(width: 110, height: 20, cornerRadius: 6)
            .padding(.horizontal, CinematicStyle.margin)
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
              ForEach(0..<4, id: \.self) { _ in
                VStack(spacing: 7) {
                  NativeSkeletonBlock(
                    width: posterWidth, height: posterWidth * 1.5, cornerRadius: 13)
                  NativeSkeletonBlock(width: posterWidth * 0.78, height: 12, cornerRadius: 5)
                  NativeSkeletonBlock(width: posterWidth * 0.45, height: 10, cornerRadius: 5)
                }
              }
            }
            .padding(.horizontal, CinematicStyle.margin)
          }
          .allowsHitTesting(false)
        }
      }

      VStack(alignment: .leading, spacing: 12) {
        NativeSkeletonBlock(width: 120, height: 20, cornerRadius: 6)
          .padding(.horizontal, CinematicStyle.margin)
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 12) {
            ForEach(0..<2, id: \.self) { _ in
              VStack(alignment: .leading, spacing: 7) {
                NativeSkeletonBlock(
                  width: cardWidth, height: cardWidth * 9.0 / 16.0, cornerRadius: 15)
                NativeSkeletonBlock(width: cardWidth * 0.72, height: 13, cornerRadius: 5)
                NativeSkeletonBlock(width: cardWidth * 0.46, height: 11, cornerRadius: 5)
              }
            }
          }
          .padding(.horizontal, CinematicStyle.margin)
        }
        .allowsHitTesting(false)
      }
    }
    .nativeSkeletonShimmer()
  }
}

/// 海报/方卡多列网格占位骨架：用于探索页、音乐榜单、全局搜索与订阅广场。
@MainActor
struct NativePosterGridSkeletonView: View {
  var columns: Int = 3
  var count: Int = 9
  var aspectRatio: CGFloat = 2.0 / 3.0
  var cornerRadius: CGFloat = 13

  var body: some View {
    let gridColumns = Array(
      repeating: GridItem(.flexible(), spacing: 12), count: max(columns, 1))
    LazyVGrid(columns: gridColumns, spacing: 16) {
      ForEach(0..<max(count, 1), id: \.self) { _ in
        VStack(alignment: .leading, spacing: 7) {
          Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
              NativeSkeletonBlock(height: 1000, cornerRadius: cornerRadius)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
          NativeSkeletonBlock(height: 12, cornerRadius: 5)
          NativeSkeletonBlock(width: 52, height: 10, cornerRadius: 5)
        }
      }
    }
    .nativeSkeletonShimmer()
  }
}

/// 影视/音乐详情页占位骨架布局：对齐全幅剧照、海报卡、操作按钮、简介段与演职员横排。
@MainActor
struct NativeMediaDetailSkeletonView: View {
  var heroHeight: CGFloat = 310

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      NativeSkeletonBlock(height: heroHeight, cornerRadius: 0)

      VStack(alignment: .leading, spacing: 16) {
        HStack(alignment: .bottom, spacing: 14) {
          NativeSkeletonBlock(width: 96, height: 144, cornerRadius: 13)
          VStack(alignment: .leading, spacing: 9) {
            NativeSkeletonBlock(height: 22, cornerRadius: 7)
            NativeSkeletonBlock(width: 140, height: 13, cornerRadius: 6)
            HStack(spacing: 8) {
              NativeSkeletonBlock(width: 54, height: 22, cornerRadius: 11)
              NativeSkeletonBlock(width: 68, height: 22, cornerRadius: 11)
            }
          }
        }

        HStack(spacing: 10) {
          NativeSkeletonBlock(height: 44, cornerRadius: 22)
          NativeSkeletonBlock(width: 116, height: 44, cornerRadius: 22)
        }

        CinematicPanel(padding: 15) {
          VStack(alignment: .leading, spacing: 9) {
            NativeSkeletonBlock(width: 72, height: 14, cornerRadius: 5)
            NativeSkeletonBlock(height: 12, cornerRadius: 5)
            NativeSkeletonBlock(height: 12, cornerRadius: 5)
            NativeSkeletonBlock(width: 210, height: 12, cornerRadius: 5)
          }
        }

        VStack(alignment: .leading, spacing: 12) {
          NativeSkeletonBlock(width: 84, height: 16, cornerRadius: 6)
          HStack(spacing: 14) {
            ForEach(0..<4, id: \.self) { _ in
              VStack(spacing: 7) {
                NativeSkeletonBlock(width: 64, height: 64, cornerRadius: 32)
                NativeSkeletonBlock(width: 52, height: 10, cornerRadius: 5)
              }
            }
          }
        }
      }
      .padding(.horizontal, CinematicStyle.margin)
    }
    .nativeSkeletonShimmer()
  }
}

/// 仪表盘（「我的」页）占位骨架布局：对齐 2×2 核心指标卡、趋势图表卡与后台服务列表，无多余搜索栏或编辑按钮。
@MainActor
struct NativeDashboardSkeletonView: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        LazyVGrid(
          columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
          spacing: 12
        ) {
          ForEach(0..<4, id: \.self) { _ in
            CinematicPanel(padding: 15) {
              VStack(alignment: .leading, spacing: 12) {
                HStack {
                  NativeSkeletonBlock(width: 58, height: 12, cornerRadius: 5)
                  Spacer()
                  NativeSkeletonBlock(width: 28, height: 28, cornerRadius: 14)
                }
                NativeSkeletonBlock(width: 86, height: 26, cornerRadius: 7)
                NativeSkeletonBlock(width: 108, height: 11, cornerRadius: 5)
              }
            }
          }
        }

        CinematicPanel(padding: 16) {
          VStack(alignment: .leading, spacing: 14) {
            HStack {
              NativeSkeletonBlock(width: 96, height: 15, cornerRadius: 6)
              Spacer()
              NativeSkeletonBlock(width: 64, height: 13, cornerRadius: 6)
            }
            NativeSkeletonBlock(height: 116, cornerRadius: 12)
          }
        }

        CinematicPanel(padding: 16) {
          VStack(alignment: .leading, spacing: 14) {
            NativeSkeletonBlock(width: 90, height: 15, cornerRadius: 6)
            ForEach(0..<3, id: \.self) { idx in
              if idx > 0 { Divider().overlay(NativeTheme.divider) }
              HStack(spacing: 12) {
                NativeSkeletonBlock(width: 26, height: 26, cornerRadius: 8)
                VStack(alignment: .leading, spacing: 6) {
                  NativeSkeletonBlock(width: 140, height: 13, cornerRadius: 5)
                  NativeSkeletonBlock(width: 96, height: 11, cornerRadius: 5)
                }
                Spacer()
              }
            }
          }
        }
      }
      .frame(maxWidth: 820, alignment: .leading)
      .padding(.horizontal, CinematicStyle.margin)
      .padding(.top, 8)
      .padding(.bottom, 36)
      .frame(maxWidth: .infinity)
    }
    .scrollIndicators(.hidden)
    .allowsHitTesting(false)
    .nativeSkeletonShimmer()
  }
}

/// 通用卡片与表单占位骨架集合：覆盖订阅、下载、整理历史、站点、插件、工作流、消息、设置与会话等全部列表/表单形态。
@MainActor
struct NativeCardListSkeletonView: View {
  enum Style {
    /// 左海报 + 右标题/标签/两行摘要（订阅、下载、整理历史、追剧日历、资源搜索）
    case posterRow
    /// 左方形图标 + 右标题/副标题/尾标（站点、用户、渠道授权、下载器、媒体服务器、文件管理、系统模块）
    case iconRow
    /// 双层插件卡：上区标题描述+右图标，下区作者头像与指标（我的插件、插件市场、插件目录）
    case pluginCard
    /// 工作流卡：标题+状态徽章+两行描述+底栏信息（我的工作流、社区工作流分享）
    case workflowCard
    /// 消息卡片：顶栏标签+时间+标题+正文多行（消息中心）
    case messageCard
    /// 舒朗分组表单面板：多行键值对/开关占位（设置子页、系统设置、插件表单、诊断工具）
    case formPanel
    /// 交替气泡会话占位（智能助手对话、历史会话）
    case chatBubbles
    /// 纵向连接节点画布占位（工作流画布）
    case workflowCanvas
  }

  var count: Int = 5
  var style: Style = .iconRow

  var body: some View {
    VStack(alignment: .leading, spacing: style == .formPanel ? 16 : 12) {
      switch style {
      case .posterRow:
        ForEach(0..<max(count, 1), id: \.self) { _ in
          CinematicPanel(padding: 13) {
            HStack(alignment: .top, spacing: 12) {
              NativeSkeletonBlock(width: 58, height: 86, cornerRadius: 10)
              VStack(alignment: .leading, spacing: 8) {
                NativeSkeletonBlock(height: 15, cornerRadius: 6)
                HStack(spacing: 6) {
                  NativeSkeletonBlock(width: 48, height: 18, cornerRadius: 9)
                  NativeSkeletonBlock(width: 56, height: 18, cornerRadius: 9)
                  NativeSkeletonBlock(width: 42, height: 18, cornerRadius: 9)
                }
                NativeSkeletonBlock(height: 12, cornerRadius: 5)
                NativeSkeletonBlock(width: 128, height: 11, cornerRadius: 5)
              }
            }
          }
        }

      case .iconRow:
        ForEach(0..<max(count, 1), id: \.self) { _ in
          CinematicPanel(padding: 14) {
            HStack(spacing: 13) {
              NativeSkeletonBlock(width: 40, height: 40, cornerRadius: 10)
              VStack(alignment: .leading, spacing: 7) {
                NativeSkeletonBlock(width: 146, height: 15, cornerRadius: 6)
                NativeSkeletonBlock(height: 12, cornerRadius: 5)
              }
              Spacer(minLength: 8)
              NativeSkeletonBlock(width: 46, height: 22, cornerRadius: 11)
            }
          }
        }

      case .pluginCard:
        ForEach(0..<max(count, 1), id: \.self) { _ in
          CinematicPanel(padding: 0) {
            VStack(spacing: 0) {
              HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                  HStack(spacing: 8) {
                    NativeSkeletonBlock(width: 126, height: 16, cornerRadius: 6)
                    NativeSkeletonBlock(width: 44, height: 14, cornerRadius: 5)
                  }
                  NativeSkeletonBlock(height: 12, cornerRadius: 5)
                  NativeSkeletonBlock(width: 170, height: 12, cornerRadius: 5)
                }
                Spacer(minLength: 8)
                NativeSkeletonBlock(width: 46, height: 46, cornerRadius: 12)
              }
              .padding(.horizontal, 14)
              .padding(.vertical, 13)
              Divider().overlay(NativeTheme.divider)
              HStack(spacing: 8) {
                NativeSkeletonBlock(width: 18, height: 18, cornerRadius: 9)
                NativeSkeletonBlock(width: 78, height: 11, cornerRadius: 5)
                Spacer()
                NativeSkeletonBlock(width: 52, height: 11, cornerRadius: 5)
              }
              .padding(.horizontal, 14)
              .padding(.vertical, 10)
            }
          }
        }

      case .workflowCard:
        ForEach(0..<max(count, 1), id: \.self) { _ in
          CinematicPanel(padding: 15) {
            VStack(alignment: .leading, spacing: 10) {
              HStack {
                NativeSkeletonBlock(width: 152, height: 16, cornerRadius: 6)
                Spacer()
                NativeSkeletonBlock(width: 54, height: 20, cornerRadius: 10)
              }
              NativeSkeletonBlock(height: 12, cornerRadius: 5)
              NativeSkeletonBlock(width: 196, height: 12, cornerRadius: 5)
              HStack(spacing: 10) {
                NativeSkeletonBlock(width: 76, height: 18, cornerRadius: 9)
                NativeSkeletonBlock(width: 64, height: 18, cornerRadius: 9)
              }
            }
          }
        }

      case .messageCard:
        ForEach(0..<max(count, 1), id: \.self) { _ in
          CinematicPanel(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
              HStack {
                NativeSkeletonBlock(width: 64, height: 20, cornerRadius: 10)
                Spacer()
                NativeSkeletonBlock(width: 112, height: 12, cornerRadius: 5)
              }
              NativeSkeletonBlock(height: 16, cornerRadius: 6)
              NativeSkeletonBlock(height: 12, cornerRadius: 5)
              NativeSkeletonBlock(width: 210, height: 12, cornerRadius: 5)
            }
          }
        }

      case .formPanel:
        ForEach(0..<max(min(count, 3), 1), id: \.self) { groupIdx in
          VStack(alignment: .leading, spacing: 9) {
            NativeSkeletonBlock(width: 92, height: 13, cornerRadius: 5)
              .padding(.horizontal, 8)
            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                let rows = groupIdx == 0 ? 3 : 2
                ForEach(0..<rows, id: \.self) { rowIdx in
                  if rowIdx > 0 { CinematicFormDivider() }
                  HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                      NativeSkeletonBlock(width: 118, height: 14, cornerRadius: 5)
                      NativeSkeletonBlock(width: 172, height: 11, cornerRadius: 5)
                    }
                    Spacer(minLength: 8)
                    NativeSkeletonBlock(width: 56, height: 22, cornerRadius: 11)
                  }
                  .padding(.horizontal, 16)
                  .padding(.vertical, 14)
                }
              }
            }
          }
        }

      case .chatBubbles:
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            Spacer(minLength: 72)
            NativeSkeletonBlock(width: 196, height: 42, cornerRadius: 18)
          }
          HStack(alignment: .top, spacing: 10) {
            NativeSkeletonBlock(width: 28, height: 28, cornerRadius: 14)
            CinematicPanel(padding: 13) {
              VStack(alignment: .leading, spacing: 8) {
                NativeSkeletonBlock(height: 13, cornerRadius: 5)
                NativeSkeletonBlock(height: 13, cornerRadius: 5)
                NativeSkeletonBlock(width: 156, height: 13, cornerRadius: 5)
              }
            }
          }
          HStack {
            Spacer(minLength: 96)
            NativeSkeletonBlock(width: 158, height: 38, cornerRadius: 18)
          }
          HStack(alignment: .top, spacing: 10) {
            NativeSkeletonBlock(width: 28, height: 28, cornerRadius: 14)
            CinematicPanel(padding: 13) {
              VStack(alignment: .leading, spacing: 8) {
                NativeSkeletonBlock(height: 13, cornerRadius: 5)
                NativeSkeletonBlock(width: 188, height: 13, cornerRadius: 5)
              }
            }
          }
        }

      case .workflowCanvas:
        VStack(spacing: 0) {
          ForEach(0..<3, id: \.self) { idx in
            if idx > 0 {
              NativeSkeletonBlock(width: 2, height: 28, cornerRadius: 1)
                .frame(maxWidth: .infinity)
            }
            CinematicPanel(padding: 15) {
              VStack(alignment: .leading, spacing: 9) {
                HStack {
                  NativeSkeletonBlock(width: 24, height: 24, cornerRadius: 12)
                  NativeSkeletonBlock(width: 148, height: 15, cornerRadius: 6)
                  Spacer()
                  NativeSkeletonBlock(width: 48, height: 18, cornerRadius: 9)
                }
                NativeSkeletonBlock(height: 12, cornerRadius: 5)
              }
            }
            .frame(maxWidth: 320)
            .frame(maxWidth: .infinity)
          }
        }
        .padding(.vertical, 24)
      }
    }
    .nativeSkeletonShimmer()
  }
}
