import Foundation
import SwiftUI
import UIKit

/// Vue 联邦插件本地预热运行时偏好配置。
enum PluginRuntimePreferences {
  static let useLegacyWebContainerKey = "nativeV2.plugin.useLegacyWebContainer"

  static var useLegacyWebContainer: Bool {
    get { UserDefaults.standard.bool(forKey: useLegacyWebContainerKey) }
    set { UserDefaults.standard.set(newValue, forKey: useLegacyWebContainerKey) }
  }
}

/// 后端 `/api/v1/plugin/remotes` 返回的单个联邦远程入口描述。
struct PluginRemoteDescriptor: Decodable, Equatable, Sendable {
  let id: String
  let url: String
  let name: String?
  let sourcePluginId: String?
  let version: String?
  let bundleHash: String?

  enum CodingKeys: String, CodingKey {
    case id
    case url
    case name
    case sourcePluginId = "source_plugin_id"
    case version
    case bundleHash = "bundle_hash"
  }

  /// 缓存失效标识优先级：`bundle_hash` > `version` > URL query `v=`（由 `PluginRemoteRuntime` 兜底）。
  var preferredCacheVersion: String {
    if let hash = bundleHash?.trimmingCharacters(in: .whitespacesAndNewlines), !hash.isEmpty {
      if let ver = version?.trimmingCharacters(in: .whitespacesAndNewlines), !ver.isEmpty {
        return "\(ver)-\(hash)"
      }
      return hash
    }
    return version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }
}

struct PluginVisualSemanticTokens: Codable, Equatable, Sendable {
  let success: String
  let warning: String
  let danger: String
  let info: String
  let brand: String
}

/// 原生外观到 Web 运行时的四层视觉融合 Token 快照（与 `MoviePilot-Frontend/src/plugin-shell/types.ts` `NativeVisualTokens` 1:1 对齐）。
struct PluginVisualTokensSnapshot: Codable, Equatable, Sendable {
  let mode: String
  let platform: String
  let backgroundPreset: String
  let isAmoledBlack: Bool
  let highContrast: Bool
  let accentHex: String
  let onAccentHex: String
  let textPrimaryHex: String
  let textSecondaryHex: String
  let surfaceGlassRgba: String
  let surfaceElevatedRgba: String
  let surfaceBorderRgba: String
  let surfaceBlurPx: Int
  let solidSurfaceHex: String
  let fieldFillRgba: String
  let fieldBorderRgba: String
  let chipFillRgba: String
  let chipBorderRgba: String
  let dividerRgba: String
  let panelRadiusPx: Int
  let sheetRadiusPx: Int
  let borderWidthPx: Double
  let semantic: PluginVisualSemanticTokens

  @MainActor
  static func make(
    from appearance: NativeAppearanceStore,
    colorScheme: ColorScheme
  ) -> PluginVisualTokensSnapshot {
    let resolvedScheme: ColorScheme
    switch appearance.mode {
    case .dark: resolvedScheme = .dark
    case .light: resolvedScheme = .light
    case .system: resolvedScheme = colorScheme
    }
    let isDark = resolvedScheme == .dark
    let accentHex = NativeAppearanceStore.hexString(from: appearance.accentColor)
    let accentRGB = rgbComponents(from: appearance.accentColor)
    let luminance =
      0.299 * Double(accentRGB.r) + 0.587 * Double(accentRGB.g) + 0.114 * Double(accentRGB.b)
    let onAccentHex = luminance > 186 ? "#18181B" : "#FFFFFF"

    let backdropColor = appearance.solidBackgroundColor(for: resolvedScheme)
    let solidSurfaceHex = NativeAppearanceStore.hexString(from: backdropColor)

    let textPrimaryHex: String
    if appearance.useCustomTextColor {
      textPrimaryHex = NativeAppearanceStore.hexString(
        from: appearance.customTextColor(for: resolvedScheme))
    } else {
      textPrimaryHex = isDark ? "#F5F2FF" : "#1C1A24"
    }
    let textSecondaryHex = isDark ? "#B7B1CC" : "#5B566E"
    let highContrast = UIAccessibility.isDarkerSystemColorsEnabled

    return PluginVisualTokensSnapshot(
      mode: isDark ? "dark" : "light",
      platform: "ios",
      backgroundPreset: appearance.backgroundPreset.rawValue,
      isAmoledBlack: false,
      highContrast: highContrast,
      accentHex: accentHex,
      onAccentHex: onAccentHex,
      textPrimaryHex: textPrimaryHex,
      textSecondaryHex: textSecondaryHex,
      surfaceGlassRgba: isDark
        ? (highContrast ? "rgba(24,26,38,0.82)" : "rgba(255,255,255,0.09)")
        : (highContrast ? "rgba(255,255,255,0.90)" : "rgba(255,255,255,0.68)"),
      surfaceElevatedRgba: isDark
        ? (highContrast ? "rgba(32,35,50,0.90)" : "rgba(30,28,44,0.84)")
        : (highContrast ? "rgba(255,255,255,0.96)" : "rgba(255,255,255,0.88)"),
      surfaceBorderRgba: isDark
        ? (highContrast ? "rgba(255,255,255,0.28)" : "rgba(255,255,255,0.16)")
        : (highContrast ? "rgba(28,26,36,0.20)" : "rgba(28,26,36,0.10)"),
      surfaceBlurPx: 20,
      solidSurfaceHex: solidSurfaceHex,
      fieldFillRgba: isDark ? "rgba(255,255,255,0.07)" : "rgba(255,255,255,0.78)",
      fieldBorderRgba: isDark ? "rgba(255,255,255,0.18)" : "rgba(28,26,36,0.16)",
      chipFillRgba: isDark ? "rgba(255,255,255,0.11)" : "rgba(28,26,36,0.06)",
      chipBorderRgba: isDark ? "rgba(255,255,255,0.16)" : "rgba(28,26,36,0.12)",
      dividerRgba: isDark ? "rgba(255,255,255,0.12)" : "rgba(28,26,36,0.10)",
      panelRadiusPx: 18,
      sheetRadiusPx: 22,
      borderWidthPx: 0.75,
      semantic: PluginVisualSemanticTokens(
        success: isDark ? "#34D399" : "#16A34A",
        warning: isDark ? "#FBBF24" : "#D97706",
        danger: isDark ? "#F87171" : "#DC2626",
        info: isDark ? "#38BDF8" : "#0284C7",
        brand: accentHex
      )
    )
  }

  private static func rgbComponents(from color: Color) -> (r: Int, g: Int, b: Int) {
    let ui = UIColor(color)
    var r: CGFloat = 0.62
    var g: CGFloat = 0.48
    var b: CGFloat = 0.96
    var a: CGFloat = 1
    ui.getRed(&r, green: &g, blue: &b, alpha: &a)
    return (
      Int((min(max(r, 0), 1) * 255).rounded()),
      Int((min(max(g, 0), 1) * 255).rounded()),
      Int((min(max(b, 0), 1) * 255).rounded())
    )
  }
}

/// 插件上报的原生 Toast 通知。
struct PluginToastPayload: Equatable, Sendable {
  let id: UUID
  let level: String
  let message: String

  init(id: UUID = UUID(), level: String, message: String) {
    self.id = id
    self.level = level
    self.message = message
  }
}
