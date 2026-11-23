// 自动生成自 shared/design-tokens/*.json，请勿手工修改；请运行 python3 tools/sync-all.py。
import SwiftUI
import UIKit

/// 三端同源视觉 Token（由 shared/design-tokens 单一事实源自动生成）。
enum GeneratedDesignTokens {
  /// 背景流光色板（深色/浅色四段色点）。
  enum BackgroundStops {
    static let cinematicDark: [Color] = [Color(red: 0.1882, green: 0.2000, blue: 0.2902), Color(red: 0.2902, green: 0.2314, blue: 0.3412), Color(red: 0.3412, green: 0.2196, blue: 0.2902), Color(red: 0.1412, green: 0.1804, blue: 0.2510)]
    static let cinematicLight: [Color] = [Color(red: 0.9412, green: 0.9294, blue: 0.9882), Color(red: 0.9608, green: 0.9216, blue: 0.9686), Color(red: 0.9804, green: 0.9294, blue: 0.9490), Color(red: 0.9216, green: 0.9412, blue: 0.9882)]
    static let oceanDark: [Color] = [Color(red: 0.0784, green: 0.1608, blue: 0.2784), Color(red: 0.1020, green: 0.2392, blue: 0.3412), Color(red: 0.1216, green: 0.2784, blue: 0.3412), Color(red: 0.0706, green: 0.1294, blue: 0.2196)]
    static let oceanLight: [Color] = [Color(red: 0.9020, green: 0.9490, blue: 0.9882), Color(red: 0.9098, green: 0.9686, blue: 0.9804), Color(red: 0.9294, green: 0.9608, blue: 0.9882), Color(red: 0.8902, green: 0.9412, blue: 0.9804)]
    static let forestDark: [Color] = [Color(red: 0.1020, green: 0.2000, blue: 0.1882), Color(red: 0.1412, green: 0.2588, blue: 0.2196), Color(red: 0.1804, green: 0.2510, blue: 0.1882), Color(red: 0.0784, green: 0.1490, blue: 0.1608)]
    static let forestLight: [Color] = [Color(red: 0.9098, green: 0.9686, blue: 0.9490), Color(red: 0.9412, green: 0.9804, blue: 0.9412), Color(red: 0.9490, green: 0.9686, blue: 0.9294), Color(red: 0.9020, green: 0.9490, blue: 0.9412)]
    static let amberDark: [Color] = [Color(red: 0.2392, green: 0.1686, blue: 0.1490), Color(red: 0.3216, green: 0.2118, blue: 0.1686), Color(red: 0.2784, green: 0.1804, blue: 0.2000), Color(red: 0.1608, green: 0.1294, blue: 0.1608)]
    static let amberLight: [Color] = [Color(red: 0.9882, green: 0.9490, blue: 0.9098), Color(red: 0.9882, green: 0.9294, blue: 0.9020), Color(red: 0.9804, green: 0.9412, blue: 0.9294), Color(red: 0.9608, green: 0.9294, blue: 0.9216)]
    static let graphiteDark: [Color] = [Color(red: 0.1294, green: 0.1412, blue: 0.1686), Color(red: 0.1804, green: 0.1882, blue: 0.2314), Color(red: 0.1608, green: 0.1686, blue: 0.2118), Color(red: 0.1020, green: 0.1098, blue: 0.1412)]
    static let graphiteLight: [Color] = [Color(red: 0.9490, green: 0.9490, blue: 0.9686), Color(red: 0.9294, green: 0.9412, blue: 0.9608), Color(red: 0.9490, green: 0.9490, blue: 0.9608), Color(red: 0.9098, green: 0.9216, blue: 0.9490)]
    static let customDark: [Color] = [Color(red: 0.1882, green: 0.2000, blue: 0.2902), Color(red: 0.2902, green: 0.2314, blue: 0.3412), Color(red: 0.3412, green: 0.2196, blue: 0.2902), Color(red: 0.1412, green: 0.1804, blue: 0.2510)]
    static let customLight: [Color] = [Color(red: 0.9412, green: 0.9294, blue: 0.9882), Color(red: 0.9608, green: 0.9216, blue: 0.9686), Color(red: 0.9804, green: 0.9294, blue: 0.9490), Color(red: 0.9216, green: 0.9412, blue: 0.9882)]
  }

  /// 主题强调前景色。
  enum Accents {
    static let violet = Color(red: 0.6196, green: 0.4784, blue: 0.9608)
    static let azure = Color(red: 0.2784, green: 0.6392, blue: 0.9804)
    static let emerald = Color(red: 0.2392, green: 0.7804, blue: 0.5608)
    static let rose = Color(red: 0.9216, green: 0.4196, blue: 0.6196)
    static let amber = Color(red: 0.9490, green: 0.6392, blue: 0.2392)
    static let custom = Color(red: 0.6196, green: 0.4784, blue: 0.9608)
  }

  /// 自适应语义状态色。
  enum Semantic {
    static let success = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.4588, green: 0.9020, blue: 0.6392, alpha: 1.0000) : UIColor(red: 0.0784, green: 0.5412, blue: 0.2784, alpha: 1.0000) })
    static let warning = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1.0000, green: 0.8000, blue: 0.4196, alpha: 1.0000) : UIColor(red: 0.7412, green: 0.4196, blue: 0.0314, alpha: 1.0000) })
    static let danger = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1.0000, green: 0.5412, blue: 0.5804, alpha: 1.0000) : UIColor(red: 0.8000, green: 0.1608, blue: 0.2000, alpha: 1.0000) })
    static let info = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.4588, green: 0.7804, blue: 1.0000, alpha: 1.0000) : UIColor(red: 0.1020, green: 0.4392, blue: 0.8392, alpha: 1.0000) })
    static let brand = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.8392, green: 0.7412, blue: 1.0000, alpha: 1.0000) : UIColor(red: 0.4000, green: 0.2196, blue: 0.7804, alpha: 1.0000) })
    static let pink = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.9608, green: 0.5608, blue: 0.7412, alpha: 1.0000) : UIColor(red: 0.7608, green: 0.1804, blue: 0.4588, alpha: 1.0000) })
    static let cyan = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.4588, green: 0.8392, blue: 0.9020, alpha: 1.0000) : UIColor(red: 0.0510, green: 0.5020, blue: 0.6196, alpha: 1.0000) })
    static let chipFill = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1.0000, green: 1.0000, blue: 1.0000, alpha: 0.0902) : UIColor(red: 0.0000, green: 0.0000, blue: 0.0000, alpha: 0.0549) })
    static let chipBorder = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1.0000, green: 1.0000, blue: 1.0000, alpha: 0.1490) : UIColor(red: 0.0000, green: 0.0000, blue: 0.0000, alpha: 0.1098) })
    static let chipText = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1.0000, green: 1.0000, blue: 1.0000, alpha: 0.8588) : UIColor(red: 0.1412, green: 0.1412, blue: 0.1412, alpha: 0.8784) })
    static let badgeFill = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1.0000, green: 1.0000, blue: 1.0000, alpha: 0.1020) : UIColor(red: 0.0000, green: 0.0000, blue: 0.0000, alpha: 0.0588) })
    static let badgeMutedText = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1.0000, green: 1.0000, blue: 1.0000, alpha: 0.6784) : UIColor(red: 0.2784, green: 0.2784, blue: 0.2784, alpha: 0.8196) })
    static let fieldFill = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1.0000, green: 1.0000, blue: 1.0000, alpha: 0.0902) : UIColor(red: 0.0000, green: 0.0000, blue: 0.0000, alpha: 0.0549) })
    static let fieldBorder = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1.0000, green: 1.0000, blue: 1.0000, alpha: 0.1412) : UIColor(red: 0.0000, green: 0.0000, blue: 0.0000, alpha: 0.1020) })
    static let primaryButtonBackground = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1.0000, green: 1.0000, blue: 1.0000, alpha: 0.9412) : UIColor(red: 0.1216, green: 0.1216, blue: 0.1608, alpha: 1.0000) })
    static let primaryButtonForeground = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.1216, green: 0.1020, blue: 0.1608, alpha: 1.0000) : UIColor(red: 1.0000, green: 1.0000, blue: 1.0000, alpha: 1.0000) })
    static let divider = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1.0000, green: 1.0000, blue: 1.0000, alpha: 0.1098) : UIColor(red: 0.0000, green: 0.0000, blue: 0.0000, alpha: 0.0902) })
    static let fallbackBackground = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.1608, green: 0.1608, blue: 0.2314, alpha: 1.0000) : UIColor(red: 0.9412, green: 0.9294, blue: 0.9882, alpha: 1.0000) })
    static let solidSurface = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.2784, green: 0.2314, blue: 0.3216, alpha: 1.0000) : UIColor(red: 0.9686, green: 0.9686, blue: 0.9882, alpha: 1.0000) })
    static let roseGlow = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.7020, green: 0.3882, blue: 0.5882, alpha: 0.1020) : UIColor(red: 0.7020, green: 0.3882, blue: 0.5882, alpha: 0.1020) })
  }

  /// 玻璃面板与布局圆角/边距常量。
  enum Metrics {
    static let panelCornerRadius: CGFloat = 24
    static let panelDefaultPadding: CGFloat = 18
    static let panelBorderWidth: CGFloat = 0.7
    static let marginCompact: CGFloat = 20
    static let marginWide: CGFloat = 24
    static let marginExpanded: CGFloat = 28
    static let ambientFps: Double = 15
  }

  /// 跨端语义图标映射（SF Symbols）。
  static let sfSymbols: [String: String] = [
    "tab_discover": "sparkles",
    "tab_explore": "safari",
    "tab_dashboard": "person.crop.circle",
    "tab_settings": "gearshape",
    "action_search": "magnifyingglass",
    "action_add": "plus",
    "action_refresh": "arrow.clockwise",
    "action_edit": "slider.horizontal.3",
    "action_filter": "line.3.horizontal.decrease.circle",
    "menu_subscriptions": "heart.text.square",
    "menu_calendar": "calendar",
    "menu_resources": "tray.full",
    "menu_downloads": "arrow.down.circle",
    "menu_files": "folder",
    "menu_history": "clock.arrow.circlepath",
    "menu_workflows": "point.3.connected.trianglepath.dotted",
    "menu_plugins": "puzzlepiece.extension",
    "feature_sites": "globe",
    "feature_messages": "bell",
    "feature_shortcuts": "bolt.circle",
    "feature_agent": "sparkles.rectangle.stack",
    "feature_music": "music.note",
    "feature_users": "person.2",
    "feature_appearance": "paintpalette",
    "feature_system": "cpu",
    "feature_medals": "medal",
    "player_play": "play.fill",
    "player_pause": "pause.fill",
    "player_pip": "pip.enter",
    "player_lock": "lock.fill",
    "player_unlock": "lock.open.fill",
    "player_subtitles": "captions.bubble",
    "player_audio_track": "waveform",
    "player_aspect": "aspectratio",
    "player_speed": "gauge.with.needle",
    "mode_dark": "moon.stars.fill",
    "mode_light": "sun.max.fill",
    "mode_system": "circle.lefthalf.filled",
  ]
}
