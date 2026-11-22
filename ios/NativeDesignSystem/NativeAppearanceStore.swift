import Combine
import SwiftUI
import UIKit

/// 原生外观主题模式：支持深色、浅色与跟随系统。
enum NativeAppearanceMode: String, CaseIterable, Identifiable {
  case dark
  case light
  case system

  var id: String { rawValue }

  var title: String {
    switch self {
    case .dark: "深色"
    case .light: "浅色"
    case .system: "跟随系统"
    }
  }

  var symbol: String {
    switch self {
    case .dark: "moon.stars.fill"
    case .light: "sun.max.fill"
    case .system: "circle.lefthalf.filled"
    }
  }

  var preferredColorScheme: ColorScheme? {
    switch self {
    case .dark: .dark
    case .light: .light
    case .system: nil
    }
  }

  var uiInterfaceStyle: UIUserInterfaceStyle {
    switch self {
    case .dark: .dark
    case .light: .light
    case .system: .unspecified
    }
  }
}

/// 预设背景渐变色板（同时提供深色与浅色和谐过渡，支持自定义三色渐变）。
enum NativeBackgroundPreset: String, CaseIterable, Identifiable {
  case cinematic
  case ocean
  case forest
  case amber
  case graphite
  case custom

  var id: String { rawValue }

  var title: String {
    switch self {
    case .cinematic: "星夜紫玫"
    case .ocean: "深海极光"
    case .forest: "静谧松林"
    case .amber: "暖阳琥珀"
    case .graphite: "极简石墨"
    case .custom: "自定义"
    }
  }

  /// 深色模式四段渐变色点。
  var darkStops: [Color] {
    switch self {
    case .cinematic:
      return [
        Color(red: 0.19, green: 0.20, blue: 0.29),
        Color(red: 0.29, green: 0.23, blue: 0.34),
        Color(red: 0.34, green: 0.22, blue: 0.29),
        Color(red: 0.14, green: 0.18, blue: 0.25),
      ]
    case .ocean:
      return [
        Color(red: 0.08, green: 0.16, blue: 0.28),
        Color(red: 0.10, green: 0.24, blue: 0.34),
        Color(red: 0.12, green: 0.28, blue: 0.34),
        Color(red: 0.07, green: 0.13, blue: 0.22),
      ]
    case .forest:
      return [
        Color(red: 0.10, green: 0.20, blue: 0.19),
        Color(red: 0.14, green: 0.26, blue: 0.22),
        Color(red: 0.18, green: 0.25, blue: 0.19),
        Color(red: 0.08, green: 0.15, blue: 0.16),
      ]
    case .amber:
      return [
        Color(red: 0.24, green: 0.17, blue: 0.15),
        Color(red: 0.32, green: 0.21, blue: 0.17),
        Color(red: 0.28, green: 0.18, blue: 0.20),
        Color(red: 0.16, green: 0.13, blue: 0.16),
      ]
    case .graphite:
      return [
        Color(red: 0.13, green: 0.14, blue: 0.17),
        Color(red: 0.18, green: 0.19, blue: 0.23),
        Color(red: 0.16, green: 0.17, blue: 0.21),
        Color(red: 0.10, green: 0.11, blue: 0.14),
      ]
    case .custom:
      return NativeBackgroundPreset.cinematic.darkStops
    }
  }

  /// 浅色模式通透柔和渐变色点。
  var lightStops: [Color] {
    switch self {
    case .cinematic:
      return [
        Color(red: 0.94, green: 0.93, blue: 0.99),
        Color(red: 0.96, green: 0.92, blue: 0.97),
        Color(red: 0.98, green: 0.93, blue: 0.95),
        Color(red: 0.92, green: 0.94, blue: 0.99),
      ]
    case .ocean:
      return [
        Color(red: 0.90, green: 0.95, blue: 0.99),
        Color(red: 0.91, green: 0.97, blue: 0.98),
        Color(red: 0.93, green: 0.96, blue: 0.99),
        Color(red: 0.89, green: 0.94, blue: 0.98),
      ]
    case .forest:
      return [
        Color(red: 0.91, green: 0.97, blue: 0.95),
        Color(red: 0.94, green: 0.98, blue: 0.94),
        Color(red: 0.95, green: 0.97, blue: 0.93),
        Color(red: 0.90, green: 0.95, blue: 0.94),
      ]
    case .amber:
      return [
        Color(red: 0.99, green: 0.95, blue: 0.91),
        Color(red: 0.99, green: 0.93, blue: 0.90),
        Color(red: 0.98, green: 0.94, blue: 0.93),
        Color(red: 0.96, green: 0.93, blue: 0.92),
      ]
    case .graphite:
      return [
        Color(red: 0.95, green: 0.95, blue: 0.97),
        Color(red: 0.93, green: 0.94, blue: 0.96),
        Color(red: 0.95, green: 0.95, blue: 0.96),
        Color(red: 0.91, green: 0.92, blue: 0.95),
      ]
    case .custom:
      return NativeBackgroundPreset.cinematic.lightStops
    }
  }
}

/// 预设主题前景色（强调色，用于高亮图标、开关、选中胶囊、进度条与主交互元素）。
enum NativeAccentPreset: String, CaseIterable, Identifiable {
  case violet
  case azure
  case emerald
  case rose
  case amber
  case custom

  var id: String { rawValue }

  var title: String {
    switch self {
    case .violet: "星耀紫"
    case .azure: "极光蓝"
    case .emerald: "翡翠绿"
    case .rose: "珊瑚粉"
    case .amber: "琥珀金"
    case .custom: "自定义"
    }
  }

  var color: Color {
    switch self {
    case .violet: Color(red: 0.62, green: 0.48, blue: 0.96)
    case .azure: Color(red: 0.28, green: 0.64, blue: 0.98)
    case .emerald: Color(red: 0.24, green: 0.78, blue: 0.56)
    case .rose: Color(red: 0.92, green: 0.42, blue: 0.62)
    case .amber: Color(red: 0.95, green: 0.64, blue: 0.24)
    case .custom: Color(red: 0.62, green: 0.48, blue: 0.96)
    }
  }
}

/// 全局原生外观与主题状态存储：实时驱动主题模式（深色/浅色/跟随系统）、背景过渡渐变色与前景色，并持久化至本地偏好。
@MainActor
final class NativeAppearanceStore: ObservableObject {
  static let shared = NativeAppearanceStore()

  private enum Keys {
    static let mode = "nativeV2.appearance.mode"
    static let backgroundPreset = "nativeV2.appearance.bgPreset"
    static let bgStartHex = "nativeV2.appearance.bgStartHex"
    static let bgMidHex = "nativeV2.appearance.bgMidHex"
    static let bgEndHex = "nativeV2.appearance.bgEndHex"
    static let accentPreset = "nativeV2.appearance.accentPreset"
    static let accentHex = "nativeV2.appearance.accentHex"
    static let useCustomText = "nativeV2.appearance.useCustomText"
    static let textHex = "nativeV2.appearance.textHex"
    static let lightTextHex = "nativeV2.appearance.lightTextHex"
    static let animateBackground = "nativeV2.appearance.animateBackground"
  }

  private let defaults: UserDefaults

  @Published var mode: NativeAppearanceMode {
    didSet { defaults.set(mode.rawValue, forKey: Keys.mode) }
  }

  @Published var backgroundPreset: NativeBackgroundPreset {
    didSet { defaults.set(backgroundPreset.rawValue, forKey: Keys.backgroundPreset) }
  }

  @Published var customBackgroundStartHex: String {
    didSet { defaults.set(customBackgroundStartHex, forKey: Keys.bgStartHex) }
  }

  @Published var customBackgroundMidHex: String {
    didSet { defaults.set(customBackgroundMidHex, forKey: Keys.bgMidHex) }
  }

  @Published var customBackgroundEndHex: String {
    didSet { defaults.set(customBackgroundEndHex, forKey: Keys.bgEndHex) }
  }

  @Published var accentPreset: NativeAccentPreset {
    didSet { defaults.set(accentPreset.rawValue, forKey: Keys.accentPreset) }
  }

  @Published var customAccentHex: String {
    didSet { defaults.set(customAccentHex, forKey: Keys.accentHex) }
  }

  @Published var useCustomTextColor: Bool {
    didSet { defaults.set(useCustomTextColor, forKey: Keys.useCustomText) }
  }

  @Published var customTextHex: String {
    didSet { defaults.set(customTextHex, forKey: Keys.textHex) }
  }

  @Published var customLightTextHex: String {
    didSet { defaults.set(customLightTextHex, forKey: Keys.lightTextHex) }
  }

  /// 是否启用缓慢微弱的同色系动态流光背景（减弱动态效果与低电量模式下自动暂停）。
  @Published var animateBackground: Bool {
    didSet { defaults.set(animateBackground, forKey: Keys.animateBackground) }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    mode =
      NativeAppearanceMode(rawValue: defaults.string(forKey: Keys.mode) ?? "") ?? .dark
    backgroundPreset =
      NativeBackgroundPreset(rawValue: defaults.string(forKey: Keys.backgroundPreset) ?? "")
      ?? .cinematic
    customBackgroundStartHex = defaults.string(forKey: Keys.bgStartHex) ?? "#30334A"
    customBackgroundMidHex = defaults.string(forKey: Keys.bgMidHex) ?? "#4A3B57"
    customBackgroundEndHex = defaults.string(forKey: Keys.bgEndHex) ?? "#242E40"
    accentPreset =
      NativeAccentPreset(rawValue: defaults.string(forKey: Keys.accentPreset) ?? "") ?? .violet
    customAccentHex = defaults.string(forKey: Keys.accentHex) ?? "#9E7AF5"
    useCustomTextColor = defaults.bool(forKey: Keys.useCustomText)
    customTextHex = defaults.string(forKey: Keys.textHex) ?? "#F5F2FF"
    customLightTextHex = defaults.string(forKey: Keys.lightTextHex) ?? "#1C1A24"
    animateBackground =
      defaults.object(forKey: Keys.animateBackground) as? Bool ?? true
    // 导航栏默认入口与返回按钮统一采用系统文本色，避免被主题强调色染成彩色。
    UINavigationBar.appearance().tintColor = .label
  }

  /// 当前生效的 SwiftUI 外观模式（`nil` 表示跟随系统）。
  var preferredColorScheme: ColorScheme? { mode.preferredColorScheme }

  /// 当前生效的主题强调前景色。
  var accentColor: Color {
    accentPreset == .custom
      ? (Self.color(fromHex: customAccentHex) ?? NativeAccentPreset.violet.color)
      : accentPreset.color
  }

  /// 按当前深/浅色环境返回对应的自定义文字前景色（浅色默认深炭灰 `#1C1A24`，深色默认柔和白 `#F5F2FF`）。
  func customTextColor(for scheme: ColorScheme) -> Color {
    if scheme == .light {
      return Self.color(fromHex: customLightTextHex) ?? Color(red: 0.11, green: 0.10, blue: 0.14)
    }
    return Self.color(fromHex: customTextHex) ?? Color(red: 0.96, green: 0.95, blue: 1.0)
  }

  /// 更新当前深/浅色模式对应的自定义文字前景色。
  func setCustomTextColor(_ color: Color, for scheme: ColorScheme) {
    let hex = Self.hexString(from: color)
    if scheme == .light {
      customLightTextHex = hex
    } else {
      customTextHex = hex
    }
  }

  /// 当前外观概要文案，供设置列表副标题展示。
  var summaryText: String {
    "\(mode.title) · \(backgroundPreset.title)"
  }

  /// 当前自定义背景起/中/止三色 Color 投影。
  var customBackgroundStartColor: Color {
    Self.color(fromHex: customBackgroundStartHex) ?? Color(red: 0.19, green: 0.20, blue: 0.29)
  }

  var customBackgroundMidColor: Color {
    Self.color(fromHex: customBackgroundMidHex) ?? Color(red: 0.29, green: 0.23, blue: 0.34)
  }

  var customBackgroundEndColor: Color {
    Self.color(fromHex: customBackgroundEndHex) ?? Color(red: 0.14, green: 0.18, blue: 0.25)
  }

  /// 按当前深/浅色环境计算背景多段过渡色点。
  func backgroundStops(for scheme: ColorScheme) -> [Gradient.Stop] {
    if backgroundPreset == .custom {
      return [
        .init(color: customBackgroundStartColor, location: 0),
        .init(color: customBackgroundMidColor, location: 0.50),
        .init(color: customBackgroundEndColor, location: 1),
      ]
    }
    let colors = scheme == .light ? backgroundPreset.lightStops : backgroundPreset.darkStops
    return [
      .init(color: colors[0], location: 0),
      .init(color: colors[1], location: 0.33),
      .init(color: colors[2], location: 0.70),
      .init(color: colors[3], location: 1),
    ]
  }

  /// 返回用于网格流光渐变的 4 节点同源色板，确保动态流动严格限定在用户所选配色内。
  func backgroundPalette(for scheme: ColorScheme) -> [Color] {
    if backgroundPreset == .custom {
      return [
        customBackgroundStartColor,
        customBackgroundMidColor,
        customBackgroundMidColor,
        customBackgroundEndColor,
      ]
    }
    return scheme == .light ? backgroundPreset.lightStops : backgroundPreset.darkStops
  }

  /// 隐私遮罩与纯色降级底色。
  func solidBackgroundColor(for scheme: ColorScheme) -> Color {
    if backgroundPreset == .custom {
      return customBackgroundStartColor
    }
    let colors = scheme == .light ? backgroundPreset.lightStops : backgroundPreset.darkStops
    return colors.first ?? CinematicStyle.background
  }

  /// 恢复默认「深色 + 星夜紫玫 + 星耀紫 + 自动文字前景色」。
  func resetToDefaults() {
    mode = .dark
    backgroundPreset = .cinematic
    customBackgroundStartHex = "#30334A"
    customBackgroundMidHex = "#4A3B57"
    customBackgroundEndHex = "#242E40"
    accentPreset = .violet
    customAccentHex = "#9E7AF5"
    useCustomTextColor = false
    customTextHex = "#F5F2FF"
    customLightTextHex = "#1C1A24"
    animateBackground = true
  }

  /// 将十六进制色值解析为 `Color`。
  static func color(fromHex hex: String) -> Color? {
    let cleaned = hex.trimmingCharacters(
      in: CharacterSet(charactersIn: "# ").union(.whitespacesAndNewlines))
    guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
    let r = Double((value >> 16) & 0xFF) / 255.0
    let g = Double((value >> 8) & 0xFF) / 255.0
    let b = Double(value & 0xFF) / 255.0
    return Color(red: r, green: g, blue: b)
  }

  /// 将 SwiftUI `Color` 编码为标准 6 位十六进制字符串。
  static func hexString(from color: Color) -> String {
    let uiColor = UIColor(color)
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else {
      return "#9E7AF5"
    }
    return String(
      format: "#%02X%02X%02X",
      Int(round(min(max(r, 0), 1) * 255)),
      Int(round(min(max(g, 0), 1) * 255)),
      Int(round(min(max(b, 0), 1) * 255))
    )
  }
}

/// 统一根视图与弹层的外观修饰器：应用深/浅色主题、前景色（强调色与按深浅色独立配对的文字前景色）。
@MainActor
struct NativeAppearanceRootModifier: ViewModifier {
  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @Environment(\.colorScheme) private var systemColorScheme

  private var resolvedScheme: ColorScheme {
    appearance.preferredColorScheme ?? systemColorScheme
  }

  @ViewBuilder
  func body(content: Content) -> some View {
    if appearance.useCustomTextColor {
      content
        .tint(appearance.accentColor)
        .foregroundStyle(appearance.customTextColor(for: resolvedScheme))
        .preferredColorScheme(appearance.preferredColorScheme)
    } else {
      content
        .tint(appearance.accentColor)
        .preferredColorScheme(appearance.preferredColorScheme)
    }
  }
}

extension View {
  /// 为原生页面或独立弹层应用全局主题外观（深/浅色、强调前景色与可选自定义文字前景色）。
  func nativeAppearanceRoot() -> some View {
    modifier(NativeAppearanceRootModifier())
  }
}
