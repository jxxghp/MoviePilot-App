import SwiftUI

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
  private let content: Content

  /// 统一边距和圆角，同时允许表单行使用零内边距的同一分组外壳。
  init(padding: CGFloat = 18, @ViewBuilder content: () -> Content) {
    self.padding = padding
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
        color: isLight ? .black.opacity(0.06) : .black.opacity(0.08),
        radius: isLight ? 10 : 12,
        y: isLight ? 4 : 6)
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
