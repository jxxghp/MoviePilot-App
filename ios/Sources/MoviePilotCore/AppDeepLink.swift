import Foundation

/// 原生播放器可识别的媒体播放模式。
public enum PlayableMediaKind: String, Equatable, Hashable, Sendable {
  case video
  case audio
}

/// 统一维护 MoviePilot 原生播放器支持的音视频文件扩展名与类型判别逻辑。
public enum PlayableMediaFormat {
  /// 原生视频播放器（VLCKit / AVKit / PiP）支持的常见封装格式扩展名。
  public static let videoExtensions: Set<String> = [
    "mp4", "mkv", "mk3d", "mov", "m4v", "avi", "ts", "m2ts", "mts",
    "webm", "flv", "f4v", "wmv", "asf", "rmvb", "rm", "mpg", "mpeg",
    "vob", "3gp", "3g2", "ogv",
  ]

  /// 仅用于网络流地址推断的视频流播放列表扩展名。
  public static let streamingVideoExtensions: Set<String> = [
    "m3u8", "mpd",
  ]

  /// 原生音频播放器支持的常见无损与有损音频扩展名。
  public static let audioExtensions: Set<String> = [
    "mp3", "flac", "m4a", "aac", "wav", "ogg", "oga", "opus",
    "alac", "ape", "aiff", "aif", "wma", "mka", "caf", "dsf",
    "dff", "amr",
  ]

  /// 按扩展名推断播放模式；`includeStreaming` 为真时额外识别 m3u8/mpd 流播放列表。
  public static func kind(
    forExtension rawExt: String?,
    includeStreaming: Bool = false
  ) -> PlayableMediaKind? {
    guard let ext = normalized(rawExt) else { return nil }
    if audioExtensions.contains(ext) { return .audio }
    if videoExtensions.contains(ext) { return .video }
    if includeStreaming && streamingVideoExtensions.contains(ext) { return .video }
    return nil
  }

  /// 判断扩展名是否属于原生播放器支持直接播放的本地或存储音视频文件。
  public static func isPlayableExtension(_ rawExt: String?) -> Bool {
    kind(forExtension: rawExt, includeStreaming: false) != nil
  }

  /// 判断扩展名是否为原生音频格式。
  public static func isAudioExtension(_ rawExt: String?) -> Bool {
    kind(forExtension: rawExt, includeStreaming: false) == .audio
  }

  /// 判断扩展名是否为原生视频格式。
  public static func isVideoExtension(_ rawExt: String?) -> Bool {
    kind(forExtension: rawExt, includeStreaming: false) == .video
  }

  /// 规范化扩展名：去除首尾空白与前导点并转为小写。
  private static func normalized(_ rawExt: String?) -> String? {
    guard
      let ext = rawExt?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        .lowercased(),
      !ext.isEmpty
    else { return nil }
    return ext
  }
}

/// 经过严格白名单解析的 MoviePilot 深度链接与系统音视频文件打开意图。
public enum AppDeepLink: Equatable, Hashable, Sendable {
  /// 发现首页。
  case discover
  /// 探索标签页，可选指定来源（如 `tmdb_movies`、`douban_tvs`、`bangumi`、`music`）。
  case explore(source: String?)
  /// 我的 / 仪表盘标签页。
  case dashboard
  /// 设置中心标签页。
  case settings
  /// 全局搜索标签页，可选预填关键字与检索类型（`media`/`library`/`person`/`music`/`collection`）。
  case search(query: String?, kind: String?)

  /// 影视详情页（`source`: `themoviedb`/`douban`/`bangumi`，`mediaType`: `电影`/`电视剧`）。
  case mediaDetail(source: String, mediaID: String, mediaType: String)

  /// 订阅中心，可选初始分类筛选（`movie`/`tv`/`music`）。
  case subscriptions(category: String?)
  /// 热门订阅 / 订阅分享。
  case subscribeCommunity
  /// 订阅日历。
  case calendar
  /// 站点资源搜索，可选预填关键字或直接浏览站点首页。
  case resources(keyword: String?, browseHome: Bool)
  /// 正在下载。
  case downloads
  /// 文件管理，可选指定初始存储与目录路径。
  case files(storage: String?, path: String?)
  /// 整理历史，可选预填过滤关键字。
  case history(search: String?)
  /// 工作流。
  case workflows
  /// 站点管理。
  case sites
  /// 消息 / 通知中心。
  case messages
  /// 插件中心；`installedOnly` 为真时打开已安装插件视图，否则打开插件市场。
  case plugins(installedOnly: Bool)
  /// 智能助手，可选预填输入草稿（绝不自动发送）。
  case agent(prompt: String?)
  /// 音乐中心。
  case music
  /// 捷径面板。
  case shortcuts

  /// 用户管理。
  case users
  /// 外观设置。
  case appearance
  /// 系统参数设置。
  case systemSettings
  /// 系统模块配置（`site_scope`/`directories`/`services`/`notifications`/`rules`/`scraping`/`nettest`）。
  case systemModule(String)
  /// 诊断与运维工具（`health`/`nettest`/`rule_test`/`words`/`live_log`/`scheduler`）。
  case diagnostics(String)
  /// 频道与消息授权绑定。
  case channelAuth
  /// 订阅与搜索规则设置。
  case subscribeSearchSettings
  /// 媒体数据源设置。
  case mediaSourceSettings
  /// 下载器管理。
  case downloadersManage
  /// 媒体服务器管理。
  case mediaServersManage
  /// 播放偏好设置。
  case playbackSettings

  /// 外部直链流播放（仅接受 `http`/`https`，绝不附带任何 MoviePilot 认证凭据或 Cookie）。
  case playExternalURL(url: URL, title: String?, kind: PlayableMediaKind)
  /// 播放当前已登录 MoviePilot 实例的媒体服务器入库条目。
  case playMediaServerItem(itemID: String, server: String?, title: String?)
  /// 播放当前已登录 MoviePilot 实例存储中的音视频文件。
  case playStorageFile(storage: String, path: String, fileName: String?)
  /// 从系统文件菜单 / 共享面板打开的本机音视频文件（`file://`）。
  case playLocalFile(url: URL, title: String, kind: PlayableMediaKind)

  /// 是否依赖已登录的 MoviePilot 实例会话；本地文件与外部直链播放可在未登录状态下直接拉起。
  public var requiresSession: Bool {
    switch self {
    case .playLocalFile, .playExternalURL:
      false
    default:
      true
    }
  }

  /// 是否允许作为远程推送通知载荷中的内部导航路由（严禁触发任何外部或本地播放动作）。
  public var isAllowedForNotificationRoute: Bool {
    switch self {
    case .playLocalFile, .playExternalURL, .playMediaServerItem, .playStorageFile:
      false
    default:
      true
    }
  }

  /// 解析外部传入的 `moviepilot://` 响应链接或系统打开的 `file://` 音视频文件链接。
  ///
  /// - Parameters:
  ///   - url: 系统移交的原始 URL。
  ///   - fallbackLocalMediaKind: 当本地文件缺少扩展名时，由调用方依据系统 `UTType` 补充推断的媒体类型。
  public init?(url: URL, fallbackLocalMediaKind: PlayableMediaKind? = nil) {
    guard url.absoluteString.utf8.count <= 4096 else { return nil }
    if url.isFileURL {
      guard let parsed = Self.parseLocalFile(url, fallbackKind: fallbackLocalMediaKind) else {
        return nil
      }
      self = parsed
      return
    }
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      components.scheme?.lowercased() == "moviepilot",
      components.user == nil,
      components.password == nil,
      components.port == nil
    else { return nil }

    let host = components.host ?? ""
    let lowerHost = host.lowercased()
    // 保留既有的小组件与 Passkey 系统协议主机，交由各自专用校验器处理，避免路由冲突。
    if lowerHost == "widget" || lowerHost == "passkey" {
      return nil
    }
    // 非空 fragment 仅保留给既有协议，普通深链忽略空 fragment 并拒绝携带未预期片段载荷。
    if let fragment = components.fragment, !fragment.isEmpty {
      return nil
    }

    guard Self.isSafeText(host, maxUTF8: 256),
      Self.isSafeText(components.path, maxUTF8: 1024),
      !components.path.contains("\\")
    else { return nil }

    let queryItems = components.queryItems ?? []
    for item in queryItems {
      guard Self.isSafeText(item.name, maxUTF8: 128),
        Self.isSafeText(item.value ?? "", maxUTF8: 2048)
      else { return nil }
    }

    // 支持 `moviepilot://open?path=/subscribe/movie` 与 `moviepilot://route?route=/resource?keyword=...` 联动写法。
    if lowerHost == "open" || lowerHost == "route" {
      guard components.path.isEmpty || components.path == "/" else { return nil }
      guard
        let rawPath = Self.singleQueryValue(in: queryItems, keys: ["path", "route"])?
          .trimmingCharacters(in: .whitespacesAndNewlines),
        !rawPath.isEmpty
      else { return nil }
      guard let parsed = Self.parseOpenPath(rawPath, outerQueryItems: queryItems) else {
        return nil
      }
      self = parsed
      return
    }

    guard let pathSegments = Self.splitPathSegments(components.path) else { return nil }
    var segments: [String] = []
    if !host.isEmpty {
      segments.append(host)
    }
    segments.append(contentsOf: pathSegments)
    guard let parsed = Self.resolve(segments: segments, queryItems: queryItems) else {
      return nil
    }
    self = parsed
  }

  /// 解析形如 `/subscribe/movie` 或 `/media?mediaid=tmdb:550&type=电影` 的站内相对路径（仅供已校验的内部/通知路由使用）。
  public init?(route rawRoute: String) {
    let trimmed = rawRoute.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("/"), !trimmed.hasPrefix("//"), !trimmed.contains("\\"),
      trimmed.utf8.count <= 2048,
      Self.isSafeText(trimmed, maxUTF8: 2048),
      let (segments, queryItems) = Self.parseRelativePath(trimmed),
      let parsed = Self.resolve(segments: segments, queryItems: queryItems),
      parsed.isAllowedForNotificationRoute
    else { return nil }
    self = parsed
  }

  /// 解析本地 `file://` 音视频文件链接，拒绝路径穿越与非音视频格式。
  private static func parseLocalFile(
    _ url: URL,
    fallbackKind: PlayableMediaKind?
  ) -> AppDeepLink? {
    let path = url.path
    guard !path.isEmpty, path.utf8.count <= 4096,
      !path.contains("\0"),
      Self.isSafeText(path, maxUTF8: 4096),
      !url.pathComponents.contains("..")
    else { return nil }
    guard
      let kind = PlayableMediaFormat.kind(forExtension: url.pathExtension, includeStreaming: false)
        ?? fallbackKind
    else { return nil }
    let stripped = url.deletingPathExtension().lastPathComponent
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let fallbackName = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = stripped.isEmpty ? (fallbackName.isEmpty ? "本地媒体" : fallbackName) : stripped
    return .playLocalFile(url: url, title: title, kind: kind)
  }

  /// 规范化站内相对路径前缀：剥离 Vue Hash 路由前缀（`/#/...`、`/#?...`），拒绝跨站 `//`、反斜杠与危险协议。
  private static func normalizeRelativeRoute(_ rawRoute: String) -> String? {
    let trimmed = rawRoute.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
      trimmed.utf8.count <= 2048,
      !trimmed.hasPrefix("//"),
      !trimmed.contains("\\"),
      !trimmed.lowercased().hasPrefix("javascript:"),
      Self.isSafeText(trimmed, maxUTF8: 2048)
    else { return nil }
    let withLeadingSlash = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
    let normalized: String
    if withLeadingSlash.hasPrefix("/#/") {
      normalized = "/" + withLeadingSlash.dropFirst(3)
    } else if withLeadingSlash.hasPrefix("/#?") {
      normalized = "/?" + withLeadingSlash.dropFirst(3)
    } else if withLeadingSlash == "/#" {
      normalized = "/"
    } else {
      normalized = withLeadingSlash
    }
    let pathPrefix =
      normalized.split(separator: "?", maxSplits: 1).first.map(String.init) ?? normalized
    guard !pathPrefix.hasPrefix("//"), !pathPrefix.contains("://"), !normalized.contains("#")
    else { return nil }
    return normalized
  }

  /// 解析 `moviepilot://open?path=...` 的联动目标路径，拒绝跨协议或 `//` 重定向载荷。
  private static func parseOpenPath(
    _ rawPath: String,
    outerQueryItems: [URLQueryItem]
  ) -> AppDeepLink? {
    guard let normalizedPath = Self.normalizeRelativeRoute(rawPath),
      let (segments, innerQueryItems) = Self.parseRelativePath(normalizedPath)
    else {
      return nil
    }
    var mergedItems = innerQueryItems
    let innerNames = Set(mergedItems.map { $0.name.lowercased() })
    for item in outerQueryItems {
      let lowerName = item.name.lowercased()
      if lowerName == "path" || lowerName == "route" { continue }
      if !innerNames.contains(lowerName) {
        mergedItems.append(item)
      }
    }
    return resolve(segments: segments, queryItems: mergedItems)
  }

  /// 直接拆分相对路径与查询字符串，兼容 Vue Hash 路由、未转义中文参数与百分号编码参数。
  private static func parseRelativePath(_ rawPath: String) -> ([String], [URLQueryItem])? {
    guard let normalizedPath = Self.normalizeRelativeRoute(rawPath) else { return nil }
    let parts = normalizedPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
    let rawPathPart = String(parts[0])
    guard let rawSegments = splitPathSegments(rawPathPart) else { return nil }
    var decodedSegments: [String] = []
    for segment in rawSegments {
      let decoded = segment.removingPercentEncoding ?? segment
      guard decoded != ".", decoded != "..", !decoded.contains("\\"), !decoded.contains("/"),
        isSafeText(decoded, maxUTF8: 256)
      else { return nil }
      decodedSegments.append(decoded)
    }

    var queryItems: [URLQueryItem] = []
    if parts.count == 2, !parts[1].isEmpty {
      for pair in parts[1].split(separator: "&", omittingEmptySubsequences: true) {
        let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        let rawName = String(kv[0])
        let name = rawName.removingPercentEncoding ?? rawName
        let value: String? =
          kv.count == 2
          ? (String(kv[1]).removingPercentEncoding ?? String(kv[1]))
          : nil
        guard !name.isEmpty, isSafeText(name, maxUTF8: 128),
          isSafeText(value ?? "", maxUTF8: 2048)
        else { return nil }
        queryItems.append(URLQueryItem(name: name, value: value))
      }
    }
    return (decodedSegments, queryItems)
  }

  /// 解析后端推送与 Web 前端约定的首页快捷弹窗参数（如 APNs 默认携带的 `/?shotcut=message`）。
  private static func resolveHomeShortcut(_ rawShortcut: String) -> AppDeepLink? {
    switch rawShortcut.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "message", "messages", "notification", "notifications":
      .messages
    case "recognition", "rule", "ruletest", "rule-test", "rule_test":
      .diagnostics("rule_test")
    case "log", "logs", "livelog", "live-log", "live_log":
      .diagnostics("live_log")
    case "network", "nettest":
      .diagnostics("nettest")
    case "words", "word":
      .diagnostics("words")
    case "scheduler", "schedulers", "schedule", "jobs":
      .diagnostics("scheduler")
    case "system", "health", "check":
      .diagnostics("health")
    default:
      nil
    }
  }

  /// 将路径分段与查询参数映射到严格白名单中的功能目的地。
  private static func resolve(
    segments: [String],
    queryItems: [URLQueryItem]
  ) -> AppDeepLink? {
    let lower = segments.map { $0.lowercased() }
    guard let first = lower.first else {
      if let rawShortcut = queryValue(in: queryItems, keys: ["shotcut", "shortcut"])?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !rawShortcut.isEmpty
      {
        return resolveHomeShortcut(rawShortcut)
      }
      return .discover
    }
    switch first {
    case "discover", "recommend", "home":
      guard lower.count == 1 else { return nil }
      if let rawShortcut = queryValue(in: queryItems, keys: ["shotcut", "shortcut"])?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !rawShortcut.isEmpty
      {
        return resolveHomeShortcut(rawShortcut)
      }
      return .discover

    case "explore":
      if lower.count == 1 {
        let rawSource = queryValue(in: queryItems, keys: ["source", "type"])
        if let rawSource, !rawSource.isEmpty {
          guard let normalized = normalizeExploreSource(rawSource) else { return nil }
          return .explore(source: normalized)
        }
        return .explore(source: nil)
      }
      if lower.count == 2 {
        guard let normalized = normalizeExploreSource(lower[1]) else { return nil }
        return .explore(source: normalized)
      }
      if lower.count == 3 {
        guard let normalized = normalizeExploreSource("\(lower[1])/\(lower[2])") else {
          return nil
        }
        return .explore(source: normalized)
      }
      return nil

    case "dashboard", "mine", "profile", "me":
      guard lower.count == 1 else { return nil }
      return .dashboard

    case "search":
      guard lower.count <= 2 else { return nil }
      let rawQuery =
        lower.count == 2
        ? segments[1]
        : queryValue(in: queryItems, keys: ["q", "keyword", "title", "query"])
      let query = sanitizeOptionalText(rawQuery, maxUTF8: 200)
      let rawKind = queryValue(in: queryItems, keys: ["type", "kind"])
      let kind: String?
      if let rawKind, !rawKind.isEmpty {
        guard let normalized = normalizeSearchKind(rawKind) else { return nil }
        kind = normalized
      } else {
        kind = nil
      }
      return .search(query: query, kind: kind)

    case "media-library":
      guard lower.count == 2, lower[1] == "search" else { return nil }
      let query = sanitizeOptionalText(
        queryValue(in: queryItems, keys: ["q", "keyword", "title", "query"]), maxUTF8: 200)
      return .search(query: query, kind: "library")

    case "media":
      return resolveMediaDetail(segments: segments, queryItems: queryItems)

    case "subscribe", "subscriptions":
      if lower.count == 1 {
        if let rawCategory = queryValue(in: queryItems, keys: ["type", "category"])?
          .trimmingCharacters(in: .whitespacesAndNewlines),
          !rawCategory.isEmpty
        {
          let lowerCategory = rawCategory.lowercased()
          if lowerCategory == "all" || lowerCategory == "全部" {
            return .subscriptions(category: nil)
          }
          guard let normalized = normalizeSubscriptionCategory(lowerCategory) else { return nil }
          return .subscriptions(category: normalized)
        }
        return .subscriptions(category: nil)
      }
      guard lower.count == 2 else { return nil }
      switch lower[1] {
      case "movie", "movies", "film":
        return .subscriptions(category: "movie")
      case "tv", "tvs", "series", "show":
        return .subscriptions(category: "tv")
      case "music", "audio":
        return .subscriptions(category: "music")
      case "all":
        return .subscriptions(category: nil)
      case "share", "popular", "community":
        return .subscribeCommunity
      default:
        return nil
      }

    case "subscribe-share", "community":
      guard lower.count == 1 else { return nil }
      return .subscribeCommunity

    case "calendar":
      guard lower.count == 1 else { return nil }
      return .calendar

    case "resource", "resources":
      guard lower.count <= 2 else { return nil }
      let pathBrowse = lower.count == 2 && lower[1] == "browse"
      if lower.count == 2 && !pathBrowse { return nil }
      let keyword = sanitizeOptionalText(
        queryValue(in: queryItems, keys: ["keyword", "q", "title", "query"]), maxUTF8: 200)
      let queryBrowse = parseBoolQuery(queryValue(in: queryItems, keys: ["browse"]))
      return .resources(keyword: keyword, browseHome: keyword == nil && (pathBrowse || queryBrowse))

    case "downloading", "downloads", "download":
      guard lower.count == 1 else { return nil }
      return .downloads

    case "filemanager", "files", "file":
      guard lower.count == 1 else { return nil }
      let storage: String?
      if let rawStorage = queryValue(in: queryItems, keys: ["storage"]), !rawStorage.isEmpty {
        guard isValidIdentifier(rawStorage, maxLength: 64) else { return nil }
        storage = rawStorage
      } else {
        storage = nil
      }
      let path: String?
      if let rawPath = queryValue(in: queryItems, keys: ["path"]), !rawPath.isEmpty {
        guard let normalized = normalizeStoragePath(rawPath) else { return nil }
        path = normalized
      } else {
        path = nil
      }
      return .files(storage: storage, path: path)

    case "history", "transfer":
      guard lower.count == 1 else { return nil }
      let search = sanitizeOptionalText(
        queryValue(in: queryItems, keys: ["search", "q", "keyword", "title"]), maxUTF8: 200)
      return .history(search: search)

    case "workflow", "workflows":
      guard lower.count == 1 else { return nil }
      return .workflows

    case "site", "sites":
      guard lower.count == 1 else { return nil }
      return .sites

    case "message", "messages", "notification", "notifications":
      guard lower.count == 1 else { return nil }
      return .messages

    case "plugin", "plugins", "apps":
      if lower.count == 1 {
        let tab = queryValue(in: queryItems, keys: ["tab"])?.lowercased()
        if let tab, !tab.isEmpty {
          guard tab == "installed" || tab == "market" else { return nil }
          return .plugins(installedOnly: tab == "installed")
        }
        return .plugins(installedOnly: false)
      }
      guard lower.count == 2 else { return nil }
      switch lower[1] {
      case "market":
        return .plugins(installedOnly: false)
      case "installed", "local":
        return .plugins(installedOnly: true)
      default:
        return nil
      }

    case "agent", "assistant", "ai":
      guard lower.count == 1 else { return nil }
      let prompt = sanitizeOptionalText(
        queryValue(in: queryItems, keys: ["prompt", "q", "text", "message"]), maxUTF8: 500)
      return .agent(prompt: prompt)

    case "music":
      guard lower.count == 1 else { return nil }
      return .music

    case "shortcut", "shortcuts":
      guard lower.count == 1 else { return nil }
      return .shortcuts

    case "user", "users":
      guard lower.count == 1 else { return nil }
      return .users

    case "appearance", "theme":
      guard lower.count == 1 else { return nil }
      return .appearance

    case "setting", "settings":
      return resolveSettings(lower: lower)

    case "diagnostic", "diagnostics", "tools":
      return resolveDiagnostics(lower: lower)

    case "logs", "log":
      guard lower.count == 1 else { return nil }
      return .diagnostics("live_log")

    case "words", "word":
      guard lower.count == 1 else { return nil }
      return .diagnostics("words")

    case "play", "player":
      guard lower.count == 1 else { return nil }
      return resolvePlay(queryItems: queryItems)

    default:
      return nil
    }
  }

  /// 解析影视详情链接，同时兼容 REST 路径写法（`media/tmdb/550?type=movie`）与 Web 查询写法（`media?mediaid=tmdb:550&type=电影`）。
  private static func resolveMediaDetail(
    segments: [String],
    queryItems: [URLQueryItem]
  ) -> AppDeepLink? {
    var rawSource: String?
    var rawID: String?
    var rawType = queryValue(in: queryItems, keys: ["type", "mtype", "media_type"])

    switch segments.count {
    case 1:
      if let mediaIDParam = queryValue(in: queryItems, keys: ["mediaid", "media_id"]),
        mediaIDParam.contains(":")
      {
        let parts = mediaIDParam.split(separator: ":", maxSplits: 1).map(String.init)
        rawSource = parts.first
        rawID = parts.count > 1 ? parts[1] : nil
      } else {
        rawSource = queryValue(in: queryItems, keys: ["source", "media_source"])
        rawID = queryValue(in: queryItems, keys: ["id", "mediaid", "media_id"])
      }
    case 2:
      if segments[1].contains(":") {
        let parts = segments[1].split(separator: ":", maxSplits: 1).map(String.init)
        rawSource = parts.first
        rawID = parts.count > 1 ? parts[1] : nil
      } else {
        rawSource = queryValue(in: queryItems, keys: ["source", "media_source"]) ?? "themoviedb"
        rawID = segments[1]
      }
    case 3:
      rawSource = segments[1]
      rawID = segments[2]
    case 4:
      rawSource = segments[1]
      rawID = segments[2]
      if rawType == nil { rawType = segments[3] }
    default:
      return nil
    }

    guard let rawSource, let source = normalizeMediaSource(rawSource),
      let rawID, isValidIdentifier(rawID, maxLength: 64)
    else { return nil }

    let mediaType: String
    if let rawType, !rawType.isEmpty {
      guard let normalized = normalizeMediaType(rawType) else { return nil }
      mediaType = normalized
    } else {
      mediaType = source == "bangumi" ? "电视剧" : "电影"
    }
    return .mediaDetail(source: source, mediaID: rawID, mediaType: mediaType)
  }

  /// 解析设置中心及其各子模块路径。
  private static func resolveSettings(lower: [String]) -> AppDeepLink? {
    if lower.count == 1 { return .settings }
    guard lower.count == 2 else { return nil }
    switch lower[1] {
    case "system":
      return .systemSettings
    case "appearance", "theme":
      return .appearance
    case "playback", "player":
      return .playbackSettings
    case "user", "users":
      return .users
    case "site", "sites":
      return .sites
    case "downloader", "downloaders":
      return .downloadersManage
    case "mediaserver", "mediaservers", "media-server", "media-servers":
      return .mediaServersManage
    case "media-source", "mediasource", "media_source":
      return .mediaSourceSettings
    case "subscribe-search", "subscribesearch", "subscribe_search":
      return .subscribeSearchSettings
    case "channel-auth", "channelauth", "channel_auth":
      return .channelAuth
    case "site-scope", "sitescope", "site_scope":
      return .systemModule("site_scope")
    case "directory", "directories", "storage":
      return .systemModule("directories")
    case "service", "services":
      return .systemModule("services")
    case "notification", "notifications":
      return .systemModule("notifications")
    case "rule", "rules":
      return .systemModule("rules")
    case "scraping", "scrape":
      return .systemModule("scraping")
    case "nettest", "network":
      return .systemModule("nettest")
    default:
      return nil
    }
  }

  /// 解析诊断与运维工具路径。
  private static func resolveDiagnostics(lower: [String]) -> AppDeepLink? {
    if lower.count == 1 { return .diagnostics("health") }
    guard lower.count == 2 else { return nil }
    switch lower[1] {
    case "health", "check":
      return .diagnostics("health")
    case "nettest", "network":
      return .diagnostics("nettest")
    case "ruletest", "rule-test", "rule_test", "recognize":
      return .diagnostics("rule_test")
    case "words", "word":
      return .diagnostics("words")
    case "logs", "log", "livelog", "live-log", "live_log":
      return .diagnostics("live_log")
    case "scheduler", "schedule", "jobs":
      return .diagnostics("scheduler")
    default:
      return nil
    }
  }

  /// 解析 `moviepilot://play` 播放链接，依次支持外部直链、媒体服务器条目和存储文件。
  private static func resolvePlay(queryItems: [URLQueryItem]) -> AppDeepLink? {
    let title = sanitizeOptionalText(
      queryValue(in: queryItems, keys: ["title", "name"]), maxUTF8: 200)
    let rawMediaType = queryValue(in: queryItems, keys: ["type", "media_type"])

    // 1. 外部音视频流直链（严格限制 http/https，绝不接受 file:// 等本地伪装链接）。
    if hasAnyQueryKey(in: queryItems, keys: ["url", "src"]) {
      guard
        let rawURL = singleQueryValue(in: queryItems, keys: ["url", "src"])?
          .trimmingCharacters(in: .whitespacesAndNewlines),
        rawURL.utf8.count <= 2048,
        Self.isSafeText(rawURL, maxUTF8: 2048),
        let streamURL = URL(string: rawURL),
        let scheme = streamURL.scheme?.lowercased(),
        scheme == "http" || scheme == "https",
        let host = streamURL.host, !host.isEmpty
      else { return nil }

      let kind: PlayableMediaKind
      if let rawMediaType, !rawMediaType.isEmpty {
        guard let parsed = normalizePlayKind(rawMediaType) else { return nil }
        kind = parsed
      } else {
        kind =
          PlayableMediaFormat.kind(forExtension: streamURL.pathExtension, includeStreaming: true)
          ?? .video
      }
      return .playExternalURL(url: streamURL, title: title, kind: kind)
    }

    // 2. 当前已登录 MoviePilot 媒体服务器入库条目。
    if hasAnyQueryKey(in: queryItems, keys: ["itemid", "item_id", "id"]) {
      guard
        let itemID = singleQueryValue(in: queryItems, keys: ["itemid", "item_id", "id"])?
          .trimmingCharacters(in: .whitespacesAndNewlines),
        !itemID.isEmpty, itemID.utf8.count <= 128,
        Self.isSafeText(itemID, maxUTF8: 128),
        !itemID.contains("/"), !itemID.contains("\\")
      else { return nil }
      let server = sanitizeOptionalText(queryValue(in: queryItems, keys: ["server"]), maxUTF8: 128)
      return .playMediaServerItem(itemID: itemID, server: server, title: title)
    }

    // 3. 当前已登录 MoviePilot 存储中的音视频文件。
    if hasAnyQueryKey(in: queryItems, keys: ["path"]) {
      guard let rawPath = singleQueryValue(in: queryItems, keys: ["path"]),
        let path = normalizeStoragePath(rawPath), path != "/"
      else { return nil }
      let storage: String
      if let rawStorage = singleQueryValue(in: queryItems, keys: ["storage"]),
        !rawStorage.isEmpty
      {
        guard isValidIdentifier(rawStorage, maxLength: 64) else { return nil }
        storage = rawStorage
      } else {
        storage = "local"
      }
      let derivedName = (path as NSString).lastPathComponent
      let fileName = title ?? (derivedName.isEmpty ? nil : derivedName)
      return .playStorageFile(storage: storage, path: path, fileName: fileName)
    }

    return nil
  }

  /// 拆分并校验 URL 路径段，拒绝 `..` 与 `.` 目录穿越。
  private static func splitPathSegments(_ rawPath: String) -> [String]? {
    let rawSegments = rawPath.split(separator: "/").map(String.init)
    for segment in rawSegments {
      if segment == "." || segment == ".." || segment.contains("\\") {
        return nil
      }
    }
    return rawSegments
  }

  /// 规范化探索来源别名。
  private static func normalizeExploreSource(_ raw: String) -> String? {
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "tmdb_movies", "tmdb-movies", "tmdb_movie", "tmdb-movie", "tmdb/movie", "tmdb/movies":
      "tmdb_movies"
    case "tmdb_tvs", "tmdb-tvs", "tmdb_tv", "tmdb-tv", "tmdb/tv", "tmdb/tvs":
      "tmdb_tvs"
    case "douban_movies", "douban-movies", "douban_movie", "douban-movie", "douban/movie",
      "douban/movies":
      "douban_movies"
    case "douban_tvs", "douban-tvs", "douban_tv", "douban-tv", "douban/tv", "douban/tvs":
      "douban_tvs"
    case "bangumi":
      "bangumi"
    case "music":
      "music"
    default:
      nil
    }
  }

  /// 规范化媒体搜索分类。
  private static func normalizeSearchKind(_ raw: String) -> String? {
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "media", "movie", "tv", "影视":
      "media"
    case "library", "media_library", "media-library", "媒体库":
      "library"
    case "person", "people", "actor", "人物":
      "person"
    case "music", "音乐":
      "music"
    case "collection", "collections", "合集":
      "collection"
    default:
      nil
    }
  }

  /// 规范化媒体详情来源标识。
  private static func normalizeMediaSource(_ raw: String) -> String? {
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "tmdb", "themoviedb":
      "themoviedb"
    case "douban":
      "douban"
    case "bangumi":
      "bangumi"
    default:
      nil
    }
  }

  /// 规范化媒体类型（后端约定为中文 `电影` / `电视剧`）。
  private static func normalizeMediaType(_ raw: String) -> String? {
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "movie", "movies", "film", "电影":
      "电影"
    case "tv", "tvs", "series", "show", "电视剧", "剧集":
      "电视剧"
    default:
      nil
    }
  }

  /// 规范化订阅中心分类筛选。
  private static func normalizeSubscriptionCategory(_ raw: String) -> String? {
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "all", "全部":
      nil
    case "movie", "movies", "电影":
      "movie"
    case "tv", "tvs", "series", "电视剧", "剧集":
      "tv"
    case "music", "audio", "音乐":
      "music"
    default:
      nil
    }
  }

  /// 规范化播放器显式媒体类型参数。
  private static func normalizePlayKind(_ raw: String) -> PlayableMediaKind? {
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "video", "movie", "视频":
      .video
    case "audio", "music", "音频", "音乐":
      .audio
    default:
      nil
    }
  }

  /// 规范化后端存储路径，拒绝反斜杠和 `..` 目录穿越。
  private static func normalizeStoragePath(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.utf8.count <= 1024,
      !trimmed.contains("\\"),
      Self.isSafeText(trimmed, maxUTF8: 1024)
    else { return nil }
    let normalized = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
    guard splitPathSegments(normalized) != nil else { return nil }
    return normalized
  }

  /// 校验简单标识符（仅允许 ASCII 字母、数字、短横线与下划线）。
  private static func isValidIdentifier(_ value: String, maxLength: Int) -> Bool {
    guard (1...maxLength).contains(value.utf8.count) else { return false }
    return value.utf8.allSatisfy {
      (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
        || $0 == 45 || $0 == 95
    }
  }

  /// 校验自由文本不包含控制字符、非法字符或隐藏格式字符。
  private static func isSafeText(_ value: String, maxUTF8: Int) -> Bool {
    guard value.utf8.count <= maxUTF8 else { return false }
    return !value.unicodeScalars.contains { scalar in
      CharacterSet.controlCharacters.contains(scalar)
        || CharacterSet.illegalCharacters.contains(scalar)
        || scalar.properties.generalCategory == .format
    }
  }

  /// 清理可选文本参数：去除首尾空白并校验字节预算，空字符串转为 nil。
  private static func sanitizeOptionalText(_ raw: String?, maxUTF8: Int) -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty,
      isSafeText(trimmed, maxUTF8: maxUTF8)
    else { return nil }
    return trimmed
  }

  /// 解析布尔查询值。
  private static func parseBoolQuery(_ raw: String?) -> Bool {
    guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
      return false
    }
    return value == "1" || value == "true" || value == "yes"
  }

  /// 检查查询列表中是否出现任意指定键名（不区分大小写）。
  private static func hasAnyQueryKey(in items: [URLQueryItem], keys: [String]) -> Bool {
    let keySet = Set(keys.map { $0.lowercased() })
    return items.contains { keySet.contains($0.name.lowercased()) }
  }

  /// 读取第一个非空查询参数值（不区分键名大小写）。
  private static func queryValue(in items: [URLQueryItem], keys: [String]) -> String? {
    for key in keys {
      let target = key.lowercased()
      if let found = items.first(where: { $0.name.lowercased() == target })?.value {
        return found
      }
    }
    return nil
  }

  /// 仅当指定键组在查询列表中精确出现一次时返回其值，防止重复参数混淆关键播放/跳转目标。
  private static func singleQueryValue(in items: [URLQueryItem], keys: [String]) -> String? {
    let keySet = Set(keys.map { $0.lowercased() })
    let matches = items.filter { keySet.contains($0.name.lowercased()) }
    guard matches.count == 1 else { return nil }
    return matches[0].value
  }
}

/// 在内存中短暂保存尚未登录或冷启动期间到达的 `moviepilot://` 深度链接，遵守五分钟有效期与实例隔离。
public struct PendingAppDeepLink: Sendable {
  private var link: AppDeepLink?
  private var instanceID: String?
  private var createdAt: Date?

  /// 新窗口初始化时不从磁盘恢复任何历史链接意图。
  public init() {}

  /// 登记最新到达的深度链接，覆盖此前尚未消费的旧意图。
  public mutating func receive(
    _ value: AppDeepLink,
    instanceID: String?,
    now: Date = .now
  ) {
    link = value
    self.instanceID = instanceID
    createdAt = now
  }

  /// 当前已认证实例就绪后解析待消费链接；超过五分钟或切换至其他实例时自动作废。
  public mutating func resolve(for currentInstanceID: String, now: Date = .now) -> AppDeepLink? {
    guard let link, let createdAt else { return nil }
    let age = now.timeIntervalSince(createdAt)
    guard age >= 0, age < 300, instanceID == nil || instanceID == currentInstanceID else {
      clear()
      return nil
    }
    instanceID = currentInstanceID
    return link
  }

  /// 主动切换服务器、注销或消费完成后立即清空。
  public mutating func clear() {
    link = nil
    instanceID = nil
    createdAt = nil
  }
}
