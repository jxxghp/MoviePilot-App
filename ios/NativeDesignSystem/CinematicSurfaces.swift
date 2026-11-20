import SwiftUI

/// Rex 单一视觉体系的基础常量；不读取旧版主题、主色或壁纸偏好。
@MainActor
enum CinematicStyle {
  static let margin: CGFloat = 20
  static let radius: CGFloat = 24
  static let background = Color(red: 0.16, green: 0.16, blue: 0.23)
  static let solidSurface = Color(red: 0.28, green: 0.23, blue: 0.32)
  static let separator = Color.white.opacity(0.10)
}

/// 所有原生页面共用连续烟紫/玫瑰/深蓝渐变，延伸到系统安全区后方。
@MainActor
struct CinematicBackground: View {
  /// 背景静止以减少干扰，也避免减弱动态模式下仍有装饰性移动。
  var body: some View {
    LinearGradient(
      stops: [
        .init(color: Color(red: 0.19, green: 0.20, blue: 0.29), location: 0),
        .init(color: Color(red: 0.29, green: 0.23, blue: 0.34), location: 0.33),
        .init(color: Color(red: 0.34, green: 0.22, blue: 0.29), location: 0.70),
        .init(color: Color(red: 0.14, green: 0.18, blue: 0.25), location: 1),
      ], startPoint: .topLeading, endPoint: .bottomTrailing
    ).ignoresSafeArea().allowsHitTesting(false)
  }
}

/// Rex 透明玻璃分组；让全局紫/玫瑰渐变透出，避免均匀灰雾遮住背景色彩。
@MainActor
struct CinematicPanel<Content: View>: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast
  private let padding: CGFloat
  private let content: Content

  /// 统一边距和圆角，同时允许表单行使用零内边距的同一分组外壳。
  init(padding: CGFloat = 18, @ViewBuilder content: () -> Content) {
    self.padding = padding
    self.content = content()
  }

  /// 降低透明度时换为同色系实底，可访问性不生成第二套主题。
  var body: some View {
    content
      .padding(padding)
      .clipShape(shape)
      .modifier(CinematicPanelSurface(reduceTransparency: reduceTransparency, contrast: contrast))
      .overlay(
        shape.strokeBorder(
          LinearGradient(
            colors: [
              .white.opacity(contrast == .increased ? 0.42 : 0.20),
              .white.opacity(contrast == .increased ? 0.28 : 0.075),
              .white.opacity(contrast == .increased ? 0.35 : 0.12),
            ], startPoint: .topLeading, endPoint: .bottomTrailing),
          lineWidth: contrast == .increased ? 1 : 0.7
        ).allowsHitTesting(false)
      )
      .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
  }

  /// 相关卡片、表单与状态面板采用相同的连续圆角。
  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: CinematicStyle.radius, style: .continuous)
  }
}

/// 正文使用低遮罩的系统材质透出底色；导航的系统 Liquid Glass 不跨页面采样正文。
@MainActor
private struct CinematicPanelSurface: ViewModifier {
  let reduceTransparency: Bool
  let contrast: ColorSchemeContrast

  /// 材质本身降低遮罩并添加轻微方向高光，避免大块灰雾或相邻卡片粘连。
  @ViewBuilder
  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: CinematicStyle.radius, style: .continuous)
    let sheen = Color(red: 0.82, green: 0.78, blue: 1)
    if reduceTransparency {
      content.background(CinematicStyle.solidSurface, in: shape)
    } else {
      content.background {
        ZStack {
          shape.fill(.ultraThinMaterial).opacity(contrast == .increased ? 0.45 : 0.22)
          shape.fill(
            LinearGradient(
              colors: [sheen.opacity(0.085), sheen.opacity(0.055), sheen.opacity(0.065)],
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
    .foregroundStyle(.white)
    .modifier(CinematicInteractiveGlass(reduceTransparency: reduceTransparency))
    .accessibilityLabel(title)
  }
}

/// 私有修饰器统一玻璃可用性与降级，不向静态卡片添加触摸变形效果。
@MainActor
private struct CinematicInteractiveGlass: ViewModifier {
  let reduceTransparency: Bool

  /// 布局已由按钮定义，最后再附着玻璃以匹配指定技能的修饰器顺序。
  @ViewBuilder
  func body(content: Content) -> some View {
    if reduceTransparency {
      content.background(CinematicStyle.solidSurface, in: Circle())
    } else if #available(iOS 26, *) {
      content.glassEffect(.regular.interactive(), in: .circle)
    } else {
      content.background(.ultraThinMaterial, in: Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.7))
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

  /// 按钮本身保留原生语义和动态字体，不用图像模拟点击区域。
  var body: some View {
    if #available(iOS 26, *), !reduceTransparency {
      button.buttonStyle(.glassProminent).tint(.white)
        .foregroundStyle(isEnabled ? Color.black : Color.white)
    } else {
      button.buttonStyle(.borderedProminent).tint(.white)
        .foregroundStyle(isEnabled ? Color.black : Color.white)
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
