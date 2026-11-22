import Darwin
import SwiftUI
import UIKit

/// 跨形态设备与响应式宽度布局中心：统一识别 iPad、iPhone Duo 硬件与系统竖向侧边操作区，并按实时容器宽度计算栅格、边距与首屏比例。
enum NativeDeviceLayout {
  /// 系统竖向侧边操作区所在边缘（iPhone Duo 展开态由系统动态指派左侧或右侧，普通 iPhone / iPad 为 `.none`）。
  enum VerticalBarEdge: Hashable, Sendable {
    case none
    case leading
    case trailing

    /// 当前是否处于系统竖向侧边操作区激活状态。
    var isActive: Bool { self != .none }
  }

  /// Apple iPhone Duo 机型标识集合。
  private static let duoModelIdentifiers: Set<String> = ["iPhone19,4"]

  /// 当前设备是否为 iPad。
  @MainActor
  static var isIPad: Bool {
    UIDevice.current.userInterfaceIdiom == .pad
  }

  /// 是否运行在 iPhone Duo 硬件或对应模拟器机型上；不依赖高版本 SDK 符号，确保旧版 CI 工具链打包仍能生效。
  @MainActor
  static var isIPhoneDuoHardware: Bool {
    guard UIDevice.current.userInterfaceIdiom == .phone else { return false }
    let model =
      ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]
      ?? machineIdentifier()
    return duoModelIdentifiers.contains(model)
  }

  /// 读取当前设备的内核型号标识（真机优先于模拟器环境变量兜底）。
  private static func machineIdentifier() -> String {
    var size: size_t = 0
    guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else { return "" }
    var machine = [CChar](repeating: 0, count: Int(size))
    guard sysctlbyname("hw.machine", &machine, &size, nil, 0) == 0 else { return "" }
    return String(
      decoding: machine.map { UInt8(bitPattern: $0) }.prefix { $0 != 0 }, as: UTF8.self)
  }

  /// 是否处于宽屏画布（全屏 iPad、iPad 2/3 分屏、iPad mini 横屏等；iPad Slide Over 与常规 iPhone 为 `false`）。
  static func isWideCanvas(_ width: CGFloat) -> Bool {
    width >= 680
  }

  /// 是否处于超宽画布（iPad Pro 11"/13" 横屏与 13" 竖屏全屏等）。
  static func isExpandedCanvas(_ width: CGFloat) -> Bool {
    width >= 960
  }

  /// 按当前容器宽度返回舒适水平外边距，避免 iPad 贴边或窄分屏挤压内容。
  @MainActor
  static func horizontalMargin(for width: CGFloat) -> CGFloat {
    if width >= 960 { return 28 }
    if width >= 680 { return 24 }
    return CinematicStyle.margin
  }

  /// 2:3 竖版海报网格列数：随实际容器宽度在 3~6 列间平滑自适应，无障碍大字号自动减一列保障可读性。
  static func posterGridCount(for width: CGFloat, isAccessibilitySize: Bool) -> Int {
    let base: Int
    if width >= 1040 {
      base = 6
    } else if width >= 780 {
      base = 5
    } else if width >= 540 {
      base = 4
    } else {
      base = 3
    }
    return isAccessibilitySize ? max(2, base - 1) : base
  }

  /// 1:1 音乐专辑方卡网格列数：随实际容器宽度在 2~5 列间自适应。
  static func squareGridCount(for width: CGFloat, isAccessibilitySize: Bool) -> Int {
    let base: Int
    if width >= 980 {
      base = 5
    } else if width >= 720 {
      base = 4
    } else if width >= 500 {
      base = 3
    } else {
      base = 2
    }
    return isAccessibilitySize ? max(1, base - 1) : base
  }

  /// 业务信息卡片（订阅、下载、站点、工作流、整理历史、插件等）列数：宽屏双列排布，窄屏或无障碍大字号保持单列。
  static func cardGridCount(for width: CGFloat, isAccessibilitySize: Bool) -> Int {
    guard !isAccessibilitySize else { return 1 }
    return width >= 740 ? 2 : 1
  }

  /// 发现页横向海报卡宽度：iPad 宽屏适度放大海报尺寸，兼顾清晰度与每屏露出张数。
  static func discoverPosterWidth(for width: CGFloat, isAccessibilitySize: Bool) -> CGFloat {
    if isAccessibilitySize { return width >= 680 ? 168 : 146 }
    if width >= 960 { return 148 }
    if width >= 680 { return 136 }
    return 112
  }

  /// 发现页 16:9 横幅卡（继续观看、热门趋势、媒体库封面）宽度。
  static func discoverCardWidth(for width: CGFloat, isAccessibilitySize: Bool) -> CGFloat {
    if isAccessibilitySize { return width >= 680 ? 320 : 260 }
    if width >= 960 { return 316 }
    if width >= 680 { return 288 }
    return 238
  }

  /// 发现页「分类浏览」每行列数。
  static func discoverCategoryColumns(for width: CGFloat, isAccessibilitySize: Bool) -> Int {
    if isAccessibilitySize { return 1 }
    if width >= 960 { return 4 }
    if width >= 660 { return 3 }
    return 2
  }

  /// 发现页首屏主视觉高度：宽屏横版控制高宽比，避免 16:9 剧照过度裁剪并让首条海报栏自然探头。
  static func discoverHeroHeight(
    width: CGFloat, height: CGFloat, isAccessibilitySize: Bool
  ) -> CGFloat {
    if isAccessibilitySize {
      return max(560, min(height * 0.76, 680))
    }
    if width >= 740 && width > height {
      return min(max(height * 0.60, 420), 560)
    }
    if width >= 740 {
      return min(max(height * 0.54, 480), 620)
    }
    return min(max(height * 0.67, 470), 640)
  }

  /// 影视与媒体库详情页首屏头图高度：加大海报默认占据面积以呈现沉浸式无遮挡影院首屏，同时在 iPad 与横屏下保持优雅比例。
  static func detailHeroHeight(
    width: CGFloat, height: CGFloat, isAccessibilitySize: Bool
  ) -> CGFloat {
    if isAccessibilitySize {
      return max(560, min(height * 0.74, 700))
    }
    if width >= 740 && width > height {
      return min(max(height * 0.62, 460), 600)
    }
    if width >= 740 {
      return min(max(height * 0.56, 540), 680)
    }
    return min(max(height * 0.68, 520), 660)
  }
}

/// 在 SwiftUI 环境树中透传系统竖向侧边操作区边缘，屏蔽不同版本 Xcode SDK 的编译差异。
private struct NativeVerticalBarEdgeEnvironmentKey: EnvironmentKey {
  static let defaultValue: NativeDeviceLayout.VerticalBarEdge = .none
}

extension EnvironmentValues {
  /// 当前场景是否激活了 iPhone Duo 系统竖向侧边操作区及其停靠边缘。
  var nativeVerticalBarEdge: NativeDeviceLayout.VerticalBarEdge {
    get { self[NativeVerticalBarEdgeEnvironmentKey.self] }
    set { self[NativeVerticalBarEdgeEnvironmentKey.self] = newValue }
  }
}

/// 读取 iOS 27.1+ `toolbarVerticalEdge` 环境值并注入 `\.nativeVerticalBarEdge`；旧版 SDK 编译时对 iPhone Duo 机型自动回退至 `.trailing`。
struct NativeVerticalBarEdgeProvider: ViewModifier {
  func body(content: Content) -> some View {
    #if compiler(>=6.4)
      if #available(iOS 27.1, *) {
        content.modifier(NativeIOS27VerticalBarEdgeBridge())
      } else {
        content.environment(
          \.nativeVerticalBarEdge,
          NativeDeviceLayout.isIPhoneDuoHardware ? .trailing : .none)
      }
    #else
      content.environment(
        \.nativeVerticalBarEdge,
        NativeDeviceLayout.isIPhoneDuoHardware ? .trailing : .none)
    #endif
  }
}

#if compiler(>=6.4)
  @available(iOS 27.1, *)
  private struct NativeIOS27VerticalBarEdgeBridge: ViewModifier {
    @Environment(\.toolbarVerticalEdge) private var toolbarVerticalEdge

    private var mappedEdge: NativeDeviceLayout.VerticalBarEdge {
      switch toolbarVerticalEdge {
      case .leading:
        return .leading
      case .trailing:
        return .trailing
      case nil:
        return .none
      @unknown default:
        return .trailing
      }
    }

    func body(content: Content) -> some View {
      content.environment(\.nativeVerticalBarEdge, mappedEdge)
    }
  }
#endif

extension View {
  /// 在当前视图子树启用系统竖向侧边操作区状态透传。
  func nativeProvideVerticalBarEdge() -> some View {
    modifier(NativeVerticalBarEdgeProvider())
  }

  /// 实时追踪当前容器可见宽度，驱动 iPad 全屏、分屏、侧栏展开与 iPhone Duo 下的自适应栅格列数。
  func nativeTrackContainerWidth(_ width: Binding<CGFloat>) -> some View {
    onGeometryChange(for: CGFloat.self) { proxy in
      proxy.size.width
    } action: { newWidth in
      if newWidth > 0, abs(width.wrappedValue - newWidth) > 1 {
        width.wrappedValue = newWidth
      }
    }
  }

  /// 在 iPadOS 18+ 上让业务弹窗以宽敞的 page 尺寸呈现，iPhone 与旧系统保持原生默认形态。
  @ViewBuilder
  func nativeAdaptiveSheetSizing() -> some View {
    if #available(iOS 18.0, *) {
      presentationSizing(.page)
    } else {
      self
    }
  }

  /// 在 iPhone Duo 竖向侧边操作区空间紧张时优先保留自定义操作栏按钮，防止核心导航与功能键被过早折叠。
  @ViewBuilder
  func nativeDuoPrefersToolbarItems() -> some View {
    #if compiler(>=6.4)
      if #available(iOS 27.1, *) {
        toolbarVerticalCompressionBehavior(.prefersToolbarItems)
      } else {
        self
      }
    #else
      self
    #endif
  }
}

extension ToolbarContent {
  /// 将工具栏项显式偏好放置到 iPhone Duo 的系统竖向侧边操作区，旧版 SDK 与非 Duo 设备保持标准横向排布。
  @ToolbarContentBuilder
  func nativeDuoVerticalPreferred() -> some ToolbarContent {
    #if compiler(>=6.4)
      if #available(iOS 27.1, *) {
        self.axisBehavior(.verticalPreferred)
      } else {
        self
      }
    #else
      self
    #endif
  }
}
