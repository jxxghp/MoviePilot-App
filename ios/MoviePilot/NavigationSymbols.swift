import UIKit

/// 导航图标使用公开 SF Symbols 映射，未知插件图标保留可访问文本并使用通用符号。
@MainActor
enum NavigationSymbols {
  /// 底栏左右共用同一符号尺寸，动态动作保留大触点而不放大图标。
  static let bottomConfiguration = UIImage.SymbolConfiguration(
    pointSize: 22, weight: .regular, scale: .medium)

  /// 只转换显示标识，不依据图标推断或执行业务行为。
  static func image(_ key: String, configuration: UIImage.SymbolConfiguration? = nil) -> UIImage? {
    let names = [
      "dashboard": "house", "mdi-home-outline": "house", "tabler-smart-home": "house",
      "recommend": "sparkles", "mdi-star-outline": "sparkles", "tabler-device-tv": "tv",
      "discover": "safari", "mdi-apple-safari": "safari", "tabler-compass": "safari",
      "apps": "square.grid.2x2", "tabler-apps": "square.grid.2x2",
      "more": "ellipsis",
      "search": "magnifyingglass", "mdi-magnify": "magnifyingglass",
      "tabler-search": "magnifyingglass",
      "refresh": "arrow.clockwise", "mdi-refresh": "arrow.clockwise",
      "tabler-refresh": "arrow.clockwise",
      "mdi-filter-multiple-outline": "line.3.horizontal.decrease",
      "tabler-filter": "line.3.horizontal.decrease",
      "mdi-sort-variant": "arrow.up.arrow.down", "tabler-sort-descending": "arrow.up.arrow.down",
      "notifications": "bell", "profile": "person.crop.circle",
      "mdi-account-outline": "person.crop.circle", "mdi-lock-check-outline": "lock.shield",
      "mdi-medal-outline": "medal", "mdi-information-outline": "info.circle",
      "mdi-help-circle-outline": "questionmark.circle", "mdi-translate": "globe",
      "mdi-restart": "restart", "mdi-logout": "rectangle.portrait.and.arrow.right",
      "mdi-trash-can-outline": "trash", "mdi-history": "clock.arrow.circlepath",
      "mdi-text-recognition": "text.viewfinder", "mdi-filter-cog": "line.3.horizontal.decrease",
      "mdi-file-document": "doc.text", "mdi-network": "network", "mdi-database": "externaldrive",
      "mdi-file-word-box": "text.word.spacing", "mdi-list-box": "list.bullet.rectangle",
      "mdi-movie-search": "film", "mdi-movie-filter": "film.stack",
      "mdi-account-search": "person.text.rectangle",
      "mdi-blur-radial": "circle.dotted", "mdi-opacity": "circle.lefthalf.filled",
      "mdi-palette": "paintpalette", "mdi-cog": "gearshape",
      "mdi-pin-outline": "pin", "mdi-pin-off-outline": "pin.slash",
      "mdi-puzzle-outline": "puzzlepiece.extension",
      "mdi-card-multiple-outline": "square.stack", "mdi-movie-open-outline": "film",
      "mdi-television": "tv", "mdi-music-note": "music.note",
      "mdi-state-machine": "point.3.connected.trianglepath.dotted",
      "mdi-calendar": "calendar", "mdi-download-outline": "arrow.down.circle",
      "mdi-folder-play-outline": "folder.badge.gearshape",
      "mdi-folder-multiple-outline": "folder.on.folder",
      "mdi-web": "globe", "mdi-account-group-outline": "person.2", "mdi-cog-outline": "gearshape",
      "mdi-plus": "plus", "tabler-plus": "plus", "tabler-check": "checkmark",
      "mdi-check": "checkmark", "mdi-restore": "arrow.counterclockwise",
      "mdi-view-dashboard-edit": "slider.horizontal.3", "mdi-tune": "slider.horizontal.3",
      "mdi-checkbox-multiple-marked-outline": "checkmark.circle",
      "tabler-dots-vertical": "ellipsis", "mdi-dots-vertical": "ellipsis",
    ]
    return UIImage(systemName: names[key] ?? "square.grid.2x2", withConfiguration: configuration)
      ?? UIImage(systemName: "square.grid.2x2", withConfiguration: configuration)
  }

  /// 前端颜色先经协议校验，这里只转换六位 RGB 展示值。
  static func color(_ hex: String?) -> UIColor? {
    guard let hex, hex.count == 7, hex.hasPrefix("#"),
      let value = UInt32(hex.dropFirst(), radix: 16)
    else { return nil }
    return UIColor(
      red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
      blue: CGFloat(value & 255) / 255, alpha: 1)
  }
}
