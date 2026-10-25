import MoviePilotCore
import UIKit

/// 导航图标使用公开 SF Symbols 映射，未知插件图标保留可访问文本并使用通用符号。
@MainActor
enum NavigationSymbols {
  /// 操作菜单只保留已有语义色，标题与背景继续由 UIKit 按主题绘制。
  static func operationTint(_ color: OperationMenuColor?, accent: UIColor) -> UIColor {
    switch color {
    case .primary: accent
    case .secondary: .secondaryLabel
    case .success: .systemGreen
    case .info: .systemBlue
    case .warning: .systemOrange
    case .error: .systemRed
    case nil: .label
    }
  }
  /// 底栏左右共用同一符号尺寸，动态动作保留大触点而不放大图标。
  static let bottomConfiguration = UIImage.SymbolConfiguration(
    pointSize: 22, weight: .regular, scale: .medium)

  /// 已知导航与注册动作的符号表只建立一次，通知列表复用时不反复构造整份映射。
  private static let names = [
    "mdi-cloud": "cloud", "mdi-cellphone-key": "lock.iphone",
    "material-symbols:passkey": "person.badge.key",
    // 卡片菜单与独立菜单共享原图标语义，含移动行、插件高级操作和历史记录。
    "mdi-pencil": "pencil", "mdi-rename": "pencil", "mdi-redo": "arrow.uturn.right",
    "mdi-sync": "arrow.triangle.2.circlepath", "mdi-reload": "arrow.clockwise",
    "mdi-restart-alert": "arrow.clockwise.circle", "mdi-cancel": "xmark.circle",
    "mdi-arrow-up-circle-outline": "arrow.up.circle", "mdi-database-eye-outline": "eye",
    "mdi-database-clock-outline": "clock.arrow.circlepath",
    "mdi-database-plus-outline": "plus.circle",
    "mdi-database-off-outline": "externaldrive.badge.xmark",
    "mdi-database-off": "externaldrive.badge.xmark",
    "mdi-delete-sweep-outline": "trash", "mdi-delete-variant": "trash",
    "mdi-download-off-outline": "arrow.down.circle",
    "mdi-download-box-outline": "arrow.down.to.line",
    "mdi-download-network-outline": "network", "mdi-movie-open": "film",
    "mdi-movie-outline": "film",
    "mdi-movie-search-outline": "film", "mdi-television-play": "play.tv",
    "mdi-play-box-outline": "play.rectangle",
    "mdi-drag-vertical": "line.3.horizontal",
    "mdi-filter-plus-outline": "line.3.horizontal.decrease.circle",
    "mdi-lock-outline": "lock", "mdi-github": "chevron.left.forwardslash.chevron.right",
    "mdi-new-box": "sparkles", "mdi-puzzle-check-outline": "puzzlepiece.extension",
    "mdi-shield-alert-outline": "exclamationmark.shield", "mdi-shield-lock-outline": "lock.shield",
    "mdi-speedometer-slow": "speedometer", "mdi-speedometer": "speedometer",
    "mdi-calendar-check-outline": "calendar.badge.checkmark",
    "mdi-hand-pointing-up": "hand.point.up",
    "mdi-pause-circle-outline": "pause.circle", "mdi-progress-check": "checkmark.circle",
    "mdi-progress-clock": "clock", "mdi-pulse": "waveform.path.ecg",
    "mdi-chart-bell-curve": "chart.bar.xaxis",
    "mdi-filter-cog-outline": "line.3.horizontal.decrease",
    "mdi-network-outline": "network", "mdi-calendar-clock-outline": "calendar.badge.clock",
    "mdi-clock": "clock", "mdi-filter-search-outline": "line.3.horizontal.decrease",
    "mdi-package-variant-closed": "shippingbox",
    "mdi-progress-download": "arrow.down.circle.dotted",
    "mdi-shimmer": "sparkles", "mdi-skip-next-circle-outline": "forward.end.circle",
    "mdi-timer-sand": "hourglass", "mdi-timer-sync-outline": "timer",
    "mdi-file-search-outline": "doc.text.magnifyingglass", "mdi-folder-outline": "folder",
    "mdi-folder-arrow-right": "folder", "mdi-folder-open-outline": "folder",
    "mdi-file-tree-outline": "list.bullet.indent", "mdi-format-letter-case": "textformat",
    "mdi-harddisk": "internaldrive", "mdi-select": "checkmark.circle",
    "mdi-selection-remove": "minus.circle",
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
    "mdi-account-convert-outline": "person.crop.circle",
    "mdi-message-plus-outline": "square.and.pencil",
    "mdi-medal-outline": "medal", "mdi-information-outline": "info.circle",
    "mdi-help-circle-outline": "questionmark.circle", "mdi-translate": "globe",
    "mdi-restart": "arrow.clockwise.circle", "mdi-logout": "rectangle.portrait.and.arrow.right",
    "mdi-trash-can-outline": "trash", "mdi-history": "clock.arrow.circlepath",
    "mdi-text-recognition": "text.viewfinder", "mdi-filter-cog": "line.3.horizontal.decrease",
    "mdi-file-document": "doc.text", "mdi-network": "network", "mdi-database": "externaldrive",
    "mdi-file-word-box": "textformat.abc", "mdi-list-box": "list.bullet.rectangle",
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
    "mdi-folder-multiple-outline": "folder",
    "mdi-web": "globe", "mdi-account-group-outline": "person.2", "mdi-cog-outline": "gearshape",
    "mdi-plus": "plus", "tabler-plus": "plus", "tabler-check": "checkmark",
    "mdi-check": "checkmark", "mdi-restore": "arrow.counterclockwise",
    "mdi-view-dashboard-edit": "rectangle.3.group", "mdi-tune": "slider.horizontal.3",
    "mdi-checkbox-multiple-marked-outline": "checkmark.circle",
    "tabler-dots-vertical": "ellipsis", "mdi-dots-vertical": "ellipsis",
    // 维护、筛选和媒体详情继续使用网页声明的图标语义，不能退化为“应用网格”。
    "mdi-tools": "wrench.and.screwdriver", "mdi-auto-fix": "wand.and.stars",
    "mdi-database-refresh-outline": "arrow.triangle.2.circlepath",
    "mdi-database-search-outline": "magnifyingglass",
    "mdi-database-cog-outline": "gearshape.2",
    "mdi-database-outline": "externaldrive",
    "mdi-magnify-scan": "magnifyingglass", "mdi-magnify-close": "xmark.circle",
    "mdi-clipboard-edit-outline": "list.clipboard", "mdi-tune-variant": "slider.horizontal.3",
    "mdi-chart-line": "chart.xyaxis.line", "mdi-store-cog": "storefront",
    "mdi-check-circle": "checkmark.circle", "mdi-check-circle-outline": "checkmark.circle",
    "mdi-stop-circle": "stop.circle", "mdi-wifi": "wifi",
    "mdi-wifi-strength-2": "wifi.exclamationmark", "mdi-wifi-off": "wifi.slash",
    "mdi-help-circle": "questionmark.circle", "mdi-filter": "line.3.horizontal.decrease",
    "mdi-filter-off-outline": "line.3.horizontal.decrease.circle",
    "mdi-heart": "heart.fill", "mdi-heart-outline": "heart",
    "mdi-subtitles-outline": "captions.bubble", "mdi-play": "play",
    "mdi-play-circle": "play.circle", "mdi-pause": "pause",
    "mdi-pause-circle": "pause.circle", "mdi-timer-sand-paused": "hourglass",
    "mdi-rss": "dot.radiowaves.left.and.right", "mdi-movie": "film",
    "mdi-television-classic": "tv", "mdi-album": "opticaldisc",
    "mdi-music": "music.note", "mdi-music-note-search-outline": "magnifyingglass",
    "mdi-account-music": "music.mic", "mdi-account-music-outline": "music.mic",
    "mdi-account-plus": "person.badge.plus", "mdi-robot-outline": "cpu",
    "mdi-web-plus": "plus.circle", "mdi-server-network-outline": "server.rack",
    "mdi-cloud-outline": "cloud", "mdi-folder-network-outline": "network",
    "mdi-bell-outline": "bell", "mdi-bell-sleep-outline": "bell.slash",
    "mdi-email-check-outline": "envelope.badge", "mdi-delete": "trash",
    "mdi-alert-circle": "exclamationmark.circle",
    "mdi-alert-circle-outline": "exclamationmark.circle",
    "mdi-alert-outline": "exclamationmark.triangle", "mdi-clock-outline": "clock",
    "mdi-checkbox-blank-outline": "square", "mdi-checkbox-multiple-marked": "checkmark.square",
    "mdi-dots-horizontal": "ellipsis", "mdi-close": "xmark",
    "mdi-arrow-left": "arrow.left", "mdi-arrow-right-circle-outline": "arrow.right.circle",
    "mdi-arrow-up-circle": "arrow.up.circle", "mdi-chevron-left": "chevron.left",
    "mdi-chevron-right": "chevron.right", "mdi-chevron-up": "chevron.up",
    "mdi-chevron-down": "chevron.down", "mdi-circle-medium": "circle.fill",
    "mdi-compass-outline": "safari", "mdi-menu": "line.3.horizontal",
    "mdi-redo-variant": "arrow.uturn.forward", "mdi-update": "arrow.triangle.2.circlepath",
    "mdi-download": "arrow.down.to.line", "mdi-download-multiple": "arrow.down.document",
    "mdi-import": "square.and.arrow.down", "mdi-export": "square.and.arrow.up",
    "mdi-link": "link", "mdi-open-in-new": "arrow.up.right.square",
    "mdi-page-next-outline": "doc.text.magnifyingglass", "mdi-layers-outline": "square.3.layers.3d",
    "mdi-sort-ascending": "arrow.up", "mdi-sort-descending": "arrow.down",
    "mdi-sort-calendar-ascending": "calendar.badge.clock",
    "mdi-sort-calendar-descending": "calendar.badge.clock",
    "mdi-format-list-bulleted": "list.bullet", "mdi-format-list-group": "list.bullet.indent",
    "mdi-view-list-outline": "list.bullet", "mdi-view-grid-outline": "square.grid.2x2",
    "mdi-drag": "line.3.horizontal", "mdi-format-font": "textformat",
    "mdi-star": "star.fill", "mdi-weather-sunny": "sun.max",
    "mdi-weather-night": "moon", "mdi-laptop": "laptopcomputer",
    "mdi-devices": "laptopcomputer.and.iphone", "mdi-dock-bottom": "dock.rectangle",
    "mdi-dock-left": "sidebar.left", "mdi-loading": "arrow.triangle.2.circlepath",
    // 文件管理的类型与动作共用此映射；类型图标保持文件语义，不推断任何文件操作。
    "mdi-folder": "folder", "mdi-folder-plus": "folder.badge.plus",
    "mdi-folder-plus-outline": "folder.badge.plus", "mdi-folder-check-outline": "checkmark.seal",
    "mdi-folder-music-outline": "music.note.list", "mdi-folder-zip-outline": "archivebox",
    "mdi-file-cog-outline": "doc.badge.gearshape", "mdi-file-outline": "doc",
    "mdi-file-document-outline": "doc.text", "mdi-file-delimited": "tablecells",
    "mdi-file-excel": "tablecells", "mdi-file-powerpoint": "rectangle.on.rectangle",
    "mdi-file-word": "doc.text", "mdi-file-pdf": "doc.richtext",
    "mdi-file-gif-box": "photo", "mdi-file-image-box": "photo",
    "mdi-file-jpg-box": "photo", "mdi-file-png-box": "photo", "mdi-image-outline": "photo",
    "mdi-file-video-outline": "film", "mdi-language-markdown-outline": "doc.text",
    "mdi-language-bash": "terminal", "mdi-language-powershell": "terminal",
    "mdi-language-c": "curlybraces", "mdi-language-cpp": "curlybraces",
    "mdi-language-csharp": "curlybraces", "mdi-language-go": "curlybraces",
    "mdi-language-css3": "chevron.left.forwardslash.chevron.right",
    "mdi-language-html5": "chevron.left.forwardslash.chevron.right",
    "mdi-language-java": "curlybraces", "mdi-language-php": "curlybraces",
    "mdi-language-python": "curlybraces", "mdi-language-typescript": "curlybraces",
    "mdi-nodejs": "curlybraces", "mdi-vuejs": "chevron.left.forwardslash.chevron.right",
    // 卡片操作沿用原网页图标语义，不将未登记的操作映射成应用网格。
    "mdi-file-edit-outline": "square.and.pencil", "mdi-note-edit": "square.and.pencil",
    "mdi-vector-polyline": "point.3.connected.trianglepath.dotted", "mdi-play-speed": "play",
    "mdi-replay": "arrow.counterclockwise", "mdi-run": "play", "mdi-share": "square.and.arrow.up",
    "mdi-restore-alert": "arrow.counterclockwise", "mdi-delete-outline": "trash",
    "mdi-folder-move-outline": "folder", "mdi-arrow-up": "arrow.up", "mdi-arrow-down": "arrow.down",
    "mdi-content-copy": "doc.on.doc", "mdi-shield-check-outline": "checkmark.shield",
    "mdi-text-box-search-outline": "doc.text.magnifyingglass",
  ]

  /// 操作菜单未识别的图标保留文字，不显示与功能无关的占位图形。
  static func operationImage(_ key: String?) -> UIImage? {
    guard let key else { return nil }
    if key.hasPrefix("emoji:") {
      let flag = String(key.dropFirst(6))
      guard flag.unicodeScalars.count == 2,
        flag.unicodeScalars.allSatisfy({ (0x1F1E6...0x1F1FF).contains($0.value) })
      else { return nil }
      let font = UIFont.systemFont(ofSize: 22)
      return UIGraphicsImageRenderer(size: CGSize(width: 28, height: 28)).image { _ in
        (flag as NSString).draw(at: CGPoint(x: 0, y: 0), withAttributes: [.font: font])
      }.withRenderingMode(.alwaysOriginal)
    }
    guard let name = names[key] else { return nil }
    return UIImage(systemName: name)
  }

  /// 只转换显示标识，不依据图标推断或执行业务行为。
  static func image(_ key: String, configuration: UIImage.SymbolConfiguration? = nil) -> UIImage? {
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
