import Foundation

/// 媒体服务器浏览支持的标准排序方式（与后端 `/api/v1/mediaserver/browse` 协议一致）。
public enum MediaServerBrowseSort: String, CaseIterable, Identifiable, Hashable, Sendable {
  case dateCreated = "date_created"
  case premiereDate = "premiere_date"
  case rating = "rating"
  case name = "name"
  case random = "random"

  public var id: String { rawValue }

  /// 排序菜单展示文案。
  public var title: String {
    switch self {
    case .dateCreated: "最近添加"
    case .premiereDate: "发行日期"
    case .rating: "评分最高"
    case .name: "名称排序"
    case .random: "随机探索"
    }
  }

  /// 各排序方式的默认方向。
  public var defaultOrder: String {
    self == .name ? "asc" : "desc"
  }
}

/// 媒体服务器浏览的观看状态筛选条件。
public enum MediaServerPlayedFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
  case all = ""
  case unplayed = "unplayed"
  case played = "played"

  public var id: String { rawValue }

  /// 筛选条展示文案。
  public var title: String {
    switch self {
    case .all: "全部"
    case .unplayed: "未看"
    case .played: "已看"
    }
  }
}

/// 媒体服务器条目的结构维度，区分电影、剧集、季、集、音乐与目录。
public enum MediaServerItemKind: Hashable, Sendable {
  case movie
  case series
  case season
  case episode
  case musicAlbum
  case audio
  case boxSet
  case folder
  case other(String)

  /// 从后端 `item_type` 字段归一化维度枚举。
  public init(rawItemType: String?) {
    switch (rawItemType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "movie", "电影": self = .movie
    case "series", "show", "tv", "电视剧": self = .series
    case "season": self = .season
    case "episode": self = .episode
    case "musicalbum", "album": self = .musicAlbum
    case "audio", "track", "song", "music", "音乐": self = .audio
    case "boxset", "boxsets", "collection", "collections", "合集", "系列": self = .boxSet
    case "folder", "directory": self = .folder
    default: self = .other(rawItemType ?? "")
    }
  }

  /// 该维度是否可直接发起播放（而非仅作为目录或合集容器）。
  public var isDirectlyPlayable: Bool {
    switch self {
    case .movie, .episode, .audio: true
    default: false
    }
  }

  /// 该维度是否属于剧集三层体系（剧 / 季 / 集）。
  public var isTelevisionHierarchy: Bool {
    switch self {
    case .series, .season, .episode: true
    default: false
    }
  }
}

/// 兼容字符串或整数年份的受限 JSON 标量解码器。
public struct MediaServerFlexibleScalar: Decodable, Hashable, Sendable {
  public let value: String

  public init(_ value: String) {
    self.value = value
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let text = try? container.decode(String.self) {
      value = text
    } else if let number = try? container.decode(Int64.self) {
      value = String(number)
    } else if let double = try? container.decode(Double.self) {
      value = String(Int64(double))
    } else {
      value = ""
    }
  }
}

/// 媒体服务器单个媒体源中的视频、音频或字幕轨道信息。
public struct MediaServerStreamDTO: Decodable, Identifiable, Hashable, Sendable {
  public let index: Int?
  public let type: String
  public let codec: String?
  public let language: String?
  public let title: String?
  public let displayTitle: String?
  public let isDefault: Bool
  public let isForced: Bool
  public let isExternal: Bool
  public let subtitleId: String?
  public let channels: Int?
  public let channelLayout: String?
  public let bitrate: Int?
  public let width: Int?
  public let height: Int?
  public let videoRange: String?

  public var id: String {
    "\(type):\(index ?? -1):\(subtitleId ?? displayTitle ?? title ?? codec ?? "")"
  }

  private enum CodingKeys: String, CodingKey {
    case index, type, codec, language, title, channels, bitrate, width, height
    case displayTitle = "display_title"
    case isDefault = "is_default"
    case isForced = "is_forced"
    case isExternal = "is_external"
    case subtitleId = "subtitle_id"
    case channelLayout = "channel_layout"
    case videoRange = "video_range"
  }

  public init(
    index: Int? = nil,
    type: String,
    codec: String? = nil,
    language: String? = nil,
    title: String? = nil,
    displayTitle: String? = nil,
    isDefault: Bool = false,
    isForced: Bool = false,
    isExternal: Bool = false,
    subtitleId: String? = nil,
    channels: Int? = nil,
    channelLayout: String? = nil,
    bitrate: Int? = nil,
    width: Int? = nil,
    height: Int? = nil,
    videoRange: String? = nil
  ) {
    self.index = index
    self.type = type
    self.codec = codec
    self.language = language
    self.title = title
    self.displayTitle = displayTitle
    self.isDefault = isDefault
    self.isForced = isForced
    self.isExternal = isExternal
    self.subtitleId = subtitleId
    self.channels = channels
    self.channelLayout = channelLayout
    self.bitrate = bitrate
    self.width = width
    self.height = height
    self.videoRange = videoRange
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    index = try container.decodeIfPresent(Int.self, forKey: .index)
    type = try container.decodeIfPresent(String.self, forKey: .type) ?? "unknown"
    codec = try container.decodeIfPresent(String.self, forKey: .codec)
    language = try container.decodeIfPresent(String.self, forKey: .language)
    title = try container.decodeIfPresent(String.self, forKey: .title)
    displayTitle = try container.decodeIfPresent(String.self, forKey: .displayTitle)
    isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
    isForced = try container.decodeIfPresent(Bool.self, forKey: .isForced) ?? false
    isExternal = try container.decodeIfPresent(Bool.self, forKey: .isExternal) ?? false
    subtitleId = try container.decodeIfPresent(String.self, forKey: .subtitleId)
    channels = try container.decodeIfPresent(Int.self, forKey: .channels)
    channelLayout = try container.decodeIfPresent(String.self, forKey: .channelLayout)
    bitrate = try container.decodeIfPresent(Int.self, forKey: .bitrate)
    width = try container.decodeIfPresent(Int.self, forKey: .width)
    height = try container.decodeIfPresent(Int.self, forKey: .height)
    videoRange = try container.decodeIfPresent(String.self, forKey: .videoRange)
  }

  /// 供播前选择器和规格区展示的简洁轨道名称。
  public var resolvedLabel: String {
    if let displayTitle, !displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return displayTitle
    }
    var parts: [String] = []
    if let title, !title.isEmpty { parts.append(title) }
    if let language, !language.isEmpty, !parts.contains(language) {
      parts.append(language.uppercased())
    }
    if let codec, !codec.isEmpty { parts.append(codec.uppercased()) }
    if let channelLayout, !channelLayout.isEmpty { parts.append(channelLayout) }
    if parts.isEmpty {
      return type == "audio" ? "默认音轨" : (type == "subtitle" ? "字幕" : "轨道")
    }
    return parts.joined(separator: " · ")
  }

  /// 视频分辨率标签（如 4K / 1080P / 720P）。
  public var resolutionLabel: String? {
    guard type == "video" else { return nil }
    let w = width ?? 0
    let h = height ?? 0
    if w >= 3800 || h >= 2100 { return "4K" }
    if w >= 1900 || h >= 1000 { return "1080P" }
    if w >= 1200 || h >= 700 { return "720P" }
    if h > 0 { return "\(h)P" }
    return nil
  }

  /// 判断该字幕轨道是否为中文（简体/繁体/zh/chi/cmn）。
  public var isChineseTrack: Bool {
    let haystack = [language, title, displayTitle]
      .compactMap { $0?.lowercased() }
      .joined(separator: " ")
    let keywords = [
      "zh", "chi", "zho", "cmn", "chs", "cht", "中文", "简体", "繁体", "国语", "中字", "chinese",
    ]
    return keywords.contains { haystack.contains($0) }
  }
}

/// 媒体服务器条目的单个文件版本（多版本支持）。
public struct MediaServerSourceDTO: Decodable, Identifiable, Hashable, Sendable {
  public let id: String
  public let name: String?
  public let container: String?
  public let size: Int64?
  public let bitrate: Int?
  public let durationMs: Int?
  public let streams: [MediaServerStreamDTO]

  private enum CodingKeys: String, CodingKey {
    case id, name, container, size, bitrate, streams
    case durationMs = "duration_ms"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id =
      (try? container.decodeIfPresent(MediaServerFlexibleScalar.self, forKey: .id))?.value ?? ""
    name = try container.decodeIfPresent(String.self, forKey: .name)
    self.container = try container.decodeIfPresent(String.self, forKey: .container)
    size = try container.decodeIfPresent(Int64.self, forKey: .size)
    bitrate = try container.decodeIfPresent(Int.self, forKey: .bitrate)
    durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs)
    streams = (try? container.decodeIfPresent([MediaServerStreamDTO].self, forKey: .streams)) ?? []
  }

  public init(
    id: String,
    name: String? = nil,
    container: String? = nil,
    size: Int64? = nil,
    bitrate: Int? = nil,
    durationMs: Int? = nil,
    streams: [MediaServerStreamDTO] = []
  ) {
    self.id = id
    self.name = name
    self.container = container
    self.size = size
    self.bitrate = bitrate
    self.durationMs = durationMs
    self.streams = streams
  }

  public var videoStreams: [MediaServerStreamDTO] { streams.filter { $0.type == "video" } }
  public var audioStreams: [MediaServerStreamDTO] { streams.filter { $0.type == "audio" } }
  public var subtitleStreams: [MediaServerStreamDTO] { streams.filter { $0.type == "subtitle" } }

  /// 简洁的媒体规格摘要（分辨率 / HDR / 编码 / 容器 / 文件大小）。
  public var specSummary: String {
    var parts: [String] = []
    if let video = videoStreams.first {
      if let res = video.resolutionLabel { parts.append(res) }
      if let range = video.videoRange, !range.isEmpty, range.uppercased() != "SDR" {
        parts.append(range)
      }
      if let codec = video.codec, !codec.isEmpty { parts.append(codec.uppercased()) }
    }
    if let container, !container.isEmpty { parts.append(container.uppercased()) }
    if let size, size > 0 {
      parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
    }
    return parts.isEmpty ? (name ?? id) : parts.joined(separator: " · ")
  }
}

/// 媒体服务器演职员 DTO。
public struct MediaServerPersonDTO: Decodable, Identifiable, Hashable, Sendable {
  public let id: String?
  public let name: String
  public let role: String?
  public let type: String?
  public let image: String?

  public var stableID: String { id ?? "\(name):\(role ?? type ?? "")" }
}

/// 媒体服务器浏览、季列表与分集列表共用的轻量卡片 DTO。
public struct MediaServerBrowseItemDTO: Decodable, Identifiable, Hashable, Sendable {
  public let itemId: String
  public let server: String?
  public let serverType: String?
  public let itemType: String
  public let mediaType: String?
  public let title: String
  public let originalTitle: String?
  public let subtitle: String?
  public let overview: String?
  public let yearScalar: MediaServerFlexibleScalar?
  public let premiereDate: String?
  public let rating: Double?
  public let durationMs: Int?
  public let poster: String?
  public let backdrop: String?
  public let thumb: String?
  public let seriesId: String?
  public let seriesName: String?
  public let seasonId: String?
  public let seasonNumber: Int?
  public let episodeNumber: Int?
  public let childCount: Int?
  public let played: Bool?
  public let playedPercentage: Double?
  public let resumePositionMs: Int?
  public let useCookies: Bool?

  public var id: String { "\(server ?? "srv"):\(itemId)" }
  public var kind: MediaServerItemKind { MediaServerItemKind(rawItemType: itemType) }

  /// 年份展示文本（自动回退 premiereDate 前四位）。
  public var yearText: String? {
    if let val = yearScalar?.value.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty {
      return val
    }
    if let premiereDate, premiereDate.count >= 4 {
      return String(premiereDate.prefix(4))
    }
    return nil
  }

  /// 分集标准编号（例如 `S01E05` 或 `第 5 集`）。
  public var episodeCode: String? {
    guard kind == .episode else { return nil }
    if let s = seasonNumber, let e = episodeNumber {
      return String(format: "S%02dE%02d", s, e)
    }
    if let e = episodeNumber {
      return "第 \(e) 集"
    }
    return nil
  }

  /// 观看进度归一化比例（0...1），无有效进度时为 nil。
  public var progressFraction: Double? {
    if let playedPercentage, playedPercentage > 0 {
      return min(max(playedPercentage / 100.0, 0), 1)
    }
    if let resumePositionMs, let durationMs, resumePositionMs > 0, durationMs > 0 {
      return min(max(Double(resumePositionMs) / Double(durationMs), 0), 1)
    }
    return nil
  }

  /// 人类可读的时长展示（例如 `1 小时 42 分` 或 `46 分钟`）。
  public var formattedDuration: String? {
    guard let durationMs, durationMs > 0 else { return nil }
    let totalMinutes = max(1, durationMs / 60_000)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours > 0 {
      return minutes > 0 ? "\(hours) 小时 \(minutes) 分" : "\(hours) 小时"
    }
    return "\(minutes) 分钟"
  }

  private enum CodingKeys: String, CodingKey {
    case server, title, subtitle, overview, rating, poster, backdrop, thumb, played
    case itemId = "item_id"
    case serverType = "server_type"
    case itemType = "item_type"
    case mediaType = "media_type"
    case originalTitle = "original_title"
    case yearScalar = "year"
    case premiereDate = "premiere_date"
    case durationMs = "duration_ms"
    case seriesId = "series_id"
    case seriesName = "series_name"
    case seasonId = "season_id"
    case seasonNumber = "season_number"
    case episodeNumber = "episode_number"
    case childCount = "child_count"
    case playedPercentage = "played_percentage"
    case resumePositionMs = "resume_position_ms"
    case useCookies = "use_cookies"
  }

  public init(
    itemId: String,
    server: String? = nil,
    serverType: String? = nil,
    itemType: String = "Movie",
    mediaType: String? = nil,
    title: String,
    originalTitle: String? = nil,
    subtitle: String? = nil,
    overview: String? = nil,
    year: String? = nil,
    premiereDate: String? = nil,
    rating: Double? = nil,
    durationMs: Int? = nil,
    poster: String? = nil,
    backdrop: String? = nil,
    thumb: String? = nil,
    seriesId: String? = nil,
    seriesName: String? = nil,
    seasonId: String? = nil,
    seasonNumber: Int? = nil,
    episodeNumber: Int? = nil,
    childCount: Int? = nil,
    played: Bool? = nil,
    playedPercentage: Double? = nil,
    resumePositionMs: Int? = nil,
    useCookies: Bool? = nil
  ) {
    self.itemId = itemId
    self.server = server
    self.serverType = serverType
    self.itemType = itemType
    self.mediaType = mediaType
    self.title = title
    self.originalTitle = originalTitle
    self.subtitle = subtitle
    self.overview = overview
    self.yearScalar = year.map(MediaServerFlexibleScalar.init)
    self.premiereDate = premiereDate
    self.rating = rating
    self.durationMs = durationMs
    self.poster = poster
    self.backdrop = backdrop
    self.thumb = thumb
    self.seriesId = seriesId
    self.seriesName = seriesName
    self.seasonId = seasonId
    self.seasonNumber = seasonNumber
    self.episodeNumber = episodeNumber
    self.childCount = childCount
    self.played = played
    self.playedPercentage = playedPercentage
    self.resumePositionMs = resumePositionMs
    self.useCookies = useCookies
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    itemId = try container.decode(MediaServerFlexibleScalar.self, forKey: .itemId).value
    server = try container.decodeIfPresent(String.self, forKey: .server)
    serverType = try container.decodeIfPresent(String.self, forKey: .serverType)
    itemType = try container.decodeIfPresent(String.self, forKey: .itemType) ?? "Movie"
    mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType)
    title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
    originalTitle = try container.decodeIfPresent(String.self, forKey: .originalTitle)
    subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
    overview = try container.decodeIfPresent(String.self, forKey: .overview)
    yearScalar = try container.decodeIfPresent(MediaServerFlexibleScalar.self, forKey: .yearScalar)
    premiereDate = try container.decodeIfPresent(String.self, forKey: .premiereDate)
    rating = try container.decodeIfPresent(Double.self, forKey: .rating)
    durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs)
    poster = try container.decodeIfPresent(String.self, forKey: .poster)
    backdrop = try container.decodeIfPresent(String.self, forKey: .backdrop)
    thumb = try container.decodeIfPresent(String.self, forKey: .thumb)
    seriesId = try container.decodeIfPresent(MediaServerFlexibleScalar.self, forKey: .seriesId)?
      .value
    seriesName = try container.decodeIfPresent(String.self, forKey: .seriesName)
    seasonId = try container.decodeIfPresent(MediaServerFlexibleScalar.self, forKey: .seasonId)?
      .value
    seasonNumber = try container.decodeIfPresent(Int.self, forKey: .seasonNumber)
    episodeNumber = try container.decodeIfPresent(Int.self, forKey: .episodeNumber)
    childCount = try container.decodeIfPresent(Int.self, forKey: .childCount)
    played = try container.decodeIfPresent(Bool.self, forKey: .played)
    playedPercentage = try container.decodeIfPresent(Double.self, forKey: .playedPercentage)
    resumePositionMs = try container.decodeIfPresent(Int.self, forKey: .resumePositionMs)
    useCookies = try container.decodeIfPresent(Bool.self, forKey: .useCookies)
  }
}

/// 媒体服务器分页浏览响应模型。
public struct MediaServerBrowsePageDTO: Decodable, Sendable {
  public let items: [MediaServerBrowseItemDTO]
  public let totalCount: Int
  public let startIndex: Int
  public let limit: Int
  public let hasMore: Bool

  private enum CodingKeys: String, CodingKey {
    case items, limit
    case totalCount = "total_count"
    case startIndex = "start_index"
    case hasMore = "has_more"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    items = (try? container.decodeIfPresent([MediaServerBrowseItemDTO].self, forKey: .items)) ?? []
    totalCount = (try? container.decodeIfPresent(Int.self, forKey: .totalCount)) ?? items.count
    startIndex = (try? container.decodeIfPresent(Int.self, forKey: .startIndex)) ?? 0
    limit = (try? container.decodeIfPresent(Int.self, forKey: .limit)) ?? 30
    hasMore = (try? container.decodeIfPresent(Bool.self, forKey: .hasMore)) ?? false
  }
}

/// 媒体库可用筛选项与排序键。
public struct MediaServerFilterOptionsDTO: Decodable, Sendable {
  public let genres: [String]
  public let years: [Int]
  public let itemTypes: [String]
  public let sortOptions: [String]

  private enum CodingKeys: String, CodingKey {
    case genres, years
    case itemTypes = "item_types"
    case sortOptions = "sort_options"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    genres = (try? container.decodeIfPresent([String].self, forKey: .genres)) ?? []
    years = (try? container.decodeIfPresent([Int].self, forKey: .years)) ?? []
    itemTypes = (try? container.decodeIfPresent([String].self, forKey: .itemTypes)) ?? []
    sortOptions =
      (try? container.decodeIfPresent([String].self, forKey: .sortOptions))
      ?? MediaServerBrowseSort.allCases.map(\.rawValue)
  }

  public init(
    genres: [String] = [],
    years: [Int] = [],
    itemTypes: [String] = [],
    sortOptions: [String] = MediaServerBrowseSort.allCases.map(\.rawValue)
  ) {
    self.genres = genres
    self.years = years
    self.itemTypes = itemTypes
    self.sortOptions = sortOptions
  }
}

/// 媒体服务器单个条目的完整详情 DTO（覆盖 Movie / Series / Season / Episode / Music）。
public struct MediaServerItemDetailDTO: Decodable, Identifiable, Hashable, Sendable {
  public let itemId: String
  public let server: String?
  public let serverType: String?
  public let itemType: String
  public let mediaType: String?
  public let title: String
  public let originalTitle: String?
  public let subtitle: String?
  public let overview: String?
  public let tagline: String?
  public let yearScalar: MediaServerFlexibleScalar?
  public let premiereDate: String?
  public let officialRating: String?
  public let rating: Double?
  public let durationMs: Int?
  public let poster: String?
  public let backdrop: String?
  public let thumb: String?
  public let logo: String?
  public let genres: [String]
  public let studios: [String]
  public let people: [MediaServerPersonDTO]
  public let mediaSource: String?
  public let mediaId: String?
  public let imdbId: String?
  public let tmdbId: String?
  public let tvdbId: String?
  public let doubanId: String?
  public let parentId: String?
  public let seriesId: String?
  public let seriesName: String?
  public let seasonId: String?
  public let seasonName: String?
  public let seasonNumber: Int?
  public let episodeNumber: Int?
  public let seasonCount: Int?
  public let episodeCount: Int?
  public let childCount: Int?
  public let played: Bool?
  public let playedPercentage: Double?
  public let resumePositionMs: Int?
  public let useCookies: Bool?
  public let mediaSources: [MediaServerSourceDTO]
  public let playUrl: String?
  public let canPlay: Bool

  public var id: String { "\(server ?? "srv"):\(itemId)" }
  public var kind: MediaServerItemKind { MediaServerItemKind(rawItemType: itemType) }

  /// 年份展示文本。
  public var yearText: String? {
    if let val = yearScalar?.value.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty {
      return val
    }
    if let premiereDate, premiereDate.count >= 4 {
      return String(premiereDate.prefix(4))
    }
    return nil
  }

  /// 时长展示文本。
  public var formattedDuration: String? {
    guard let durationMs, durationMs > 0 else { return nil }
    let totalMinutes = max(1, durationMs / 60_000)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours > 0 {
      return minutes > 0 ? "\(hours) 小时 \(minutes) 分" : "\(hours) 小时"
    }
    return "\(minutes) 分钟"
  }

  /// 解析用于订阅或跳转 MoviePilot 外部元数据详情页的身份（优先 TMDB / 豆瓣）；合集、目录与音频无对应的影视媒体源编号，统一返回 nil。
  public var resolvedExternalIdentity: (source: String, mediaID: String, type: String)? {
    guard kind == .movie || kind.isTelevisionHierarchy else { return nil }
    let businessType = (mediaType == "电视剧" || kind.isTelevisionHierarchy) ? "电视剧" : "电影"
    if let mediaSource, !mediaSource.isEmpty, let mediaId, !mediaId.isEmpty, mediaId != "0" {
      return (mediaSource.lowercased(), mediaId, businessType)
    }
    if let tmdbId, !tmdbId.isEmpty, tmdbId != "0" {
      return ("themoviedb", tmdbId, businessType)
    }
    if let doubanId, !doubanId.isEmpty, doubanId != "0" {
      return ("douban", doubanId, businessType)
    }
    return nil
  }

  private enum CodingKeys: String, CodingKey {
    case server, title, subtitle, overview, tagline, rating, poster, backdrop, thumb, logo
    case logoPath = "logo_path"
    case genres, studios, people, played
    case itemId = "item_id"
    case serverType = "server_type"
    case itemType = "item_type"
    case mediaType = "media_type"
    case originalTitle = "original_title"
    case yearScalar = "year"
    case premiereDate = "premiere_date"
    case officialRating = "official_rating"
    case durationMs = "duration_ms"
    case mediaSource = "media_source"
    case mediaId = "media_id"
    case imdbId = "imdb_id"
    case tmdbId = "tmdb_id"
    case tvdbId = "tvdb_id"
    case doubanId = "douban_id"
    case parentId = "parent_id"
    case seriesId = "series_id"
    case seriesName = "series_name"
    case seasonId = "season_id"
    case seasonName = "season_name"
    case seasonNumber = "season_number"
    case episodeNumber = "episode_number"
    case seasonCount = "season_count"
    case episodeCount = "episode_count"
    case childCount = "child_count"
    case playedPercentage = "played_percentage"
    case resumePositionMs = "resume_position_ms"
    case useCookies = "use_cookies"
    case mediaSources = "media_sources"
    case playUrl = "play_url"
    case canPlay = "can_play"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    itemId =
      (try? container.decodeIfPresent(MediaServerFlexibleScalar.self, forKey: .itemId))?.value ?? ""
    server = try container.decodeIfPresent(String.self, forKey: .server)
    serverType = try container.decodeIfPresent(String.self, forKey: .serverType)
    itemType = (try? container.decodeIfPresent(String.self, forKey: .itemType)) ?? "Movie"
    mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType)
    title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? ""
    originalTitle = try container.decodeIfPresent(String.self, forKey: .originalTitle)
    subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
    overview = try container.decodeIfPresent(String.self, forKey: .overview)
    tagline = try container.decodeIfPresent(String.self, forKey: .tagline)
    yearScalar = try? container.decodeIfPresent(MediaServerFlexibleScalar.self, forKey: .yearScalar)
    premiereDate = try container.decodeIfPresent(String.self, forKey: .premiereDate)
    officialRating = try container.decodeIfPresent(String.self, forKey: .officialRating)
    rating = try container.decodeIfPresent(Double.self, forKey: .rating)
    durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs)
    poster = try container.decodeIfPresent(String.self, forKey: .poster)
    backdrop = try container.decodeIfPresent(String.self, forKey: .backdrop)
    thumb = try container.decodeIfPresent(String.self, forKey: .thumb)
    let rawLogo = try? container.decodeIfPresent(String.self, forKey: .logo)
    let rawLogoPath = try? container.decodeIfPresent(String.self, forKey: .logoPath)
    logo =
      (rawLogo?.isEmpty == false ? rawLogo : nil)
      ?? (rawLogoPath?.isEmpty == false ? rawLogoPath : nil)
    genres = (try? container.decodeIfPresent([String].self, forKey: .genres)) ?? []
    studios = (try? container.decodeIfPresent([String].self, forKey: .studios)) ?? []
    people = (try? container.decodeIfPresent([MediaServerPersonDTO].self, forKey: .people)) ?? []
    mediaSource = try container.decodeIfPresent(String.self, forKey: .mediaSource)
    mediaId =
      (try? container.decodeIfPresent(MediaServerFlexibleScalar.self, forKey: .mediaId))?.value
    imdbId =
      (try? container.decodeIfPresent(MediaServerFlexibleScalar.self, forKey: .imdbId))?.value
    tmdbId =
      (try? container.decodeIfPresent(MediaServerFlexibleScalar.self, forKey: .tmdbId))?.value
    tvdbId =
      (try? container.decodeIfPresent(MediaServerFlexibleScalar.self, forKey: .tvdbId))?.value
    doubanId =
      (try? container.decodeIfPresent(MediaServerFlexibleScalar.self, forKey: .doubanId))?.value
    parentId =
      (try? container.decodeIfPresent(MediaServerFlexibleScalar.self, forKey: .parentId))?.value
    seriesId =
      (try? container.decodeIfPresent(MediaServerFlexibleScalar.self, forKey: .seriesId))?.value
    seriesName = try container.decodeIfPresent(String.self, forKey: .seriesName)
    seasonId =
      (try? container.decodeIfPresent(MediaServerFlexibleScalar.self, forKey: .seasonId))?.value
    seasonName = try container.decodeIfPresent(String.self, forKey: .seasonName)
    seasonNumber = try container.decodeIfPresent(Int.self, forKey: .seasonNumber)
    episodeNumber = try container.decodeIfPresent(Int.self, forKey: .episodeNumber)
    seasonCount = try container.decodeIfPresent(Int.self, forKey: .seasonCount)
    episodeCount = try container.decodeIfPresent(Int.self, forKey: .episodeCount)
    childCount = try container.decodeIfPresent(Int.self, forKey: .childCount)
    played = try container.decodeIfPresent(Bool.self, forKey: .played)
    playedPercentage = try container.decodeIfPresent(Double.self, forKey: .playedPercentage)
    resumePositionMs = try container.decodeIfPresent(Int.self, forKey: .resumePositionMs)
    useCookies = try container.decodeIfPresent(Bool.self, forKey: .useCookies)
    mediaSources =
      (try? container.decodeIfPresent([MediaServerSourceDTO].self, forKey: .mediaSources)) ?? []
    playUrl = try container.decodeIfPresent(String.self, forKey: .playUrl)
    canPlay = (try? container.decodeIfPresent(Bool.self, forKey: .canPlay)) ?? true
  }
}

/// 播前用户选择的版本、音轨与字幕配置，由详情页透传至本地播放器自动生效。
public struct MediaPlaybackTrackSelection: Hashable, Sendable {
  public var mediaSourceID: String?
  public var audioOrdinal: Int?
  public var audioLanguage: String?
  public var audioDisplayTitle: String?
  public var subtitleDisabled: Bool
  public var subtitleOrdinal: Int?
  public var subtitleExternalID: String?
  public var subtitleLanguage: String?
  public var subtitleDisplayTitle: String?

  public init(
    mediaSourceID: String? = nil,
    audioOrdinal: Int? = nil,
    audioLanguage: String? = nil,
    audioDisplayTitle: String? = nil,
    subtitleDisabled: Bool = false,
    subtitleOrdinal: Int? = nil,
    subtitleExternalID: String? = nil,
    subtitleLanguage: String? = nil,
    subtitleDisplayTitle: String? = nil
  ) {
    self.mediaSourceID = mediaSourceID
    self.audioOrdinal = audioOrdinal
    self.audioLanguage = audioLanguage
    self.audioDisplayTitle = audioDisplayTitle
    self.subtitleDisabled = subtitleDisabled
    self.subtitleOrdinal = subtitleOrdinal
    self.subtitleExternalID = subtitleExternalID
    self.subtitleLanguage = subtitleLanguage
    self.subtitleDisplayTitle = subtitleDisplayTitle
  }

  /// 基于当前媒体源轨道与用户「优先中文字幕」偏好生成合理的默认播前选择。
  public static func defaultSelection(
    for source: MediaServerSourceDTO?,
    preferChineseSub: Bool = true
  ) -> MediaPlaybackTrackSelection {
    guard let source else { return MediaPlaybackTrackSelection() }

    let audioStreams = source.audioStreams
    let audioIndex =
      audioStreams.firstIndex(where: \.isDefault)
      ?? (audioStreams.isEmpty ? nil : 0)
    let chosenAudio = audioIndex.map { audioStreams[$0] }

    let subtitleStreams = source.subtitleStreams
    let embeddedSubs = subtitleStreams.filter { !$0.isExternal && $0.subtitleId == nil }
    var subDisabled = subtitleStreams.isEmpty
    var chosenSubOrdinal: Int?
    var chosenExternalID: String?
    var chosenSubLang: String?
    var chosenSubTitle: String?

    if !subtitleStreams.isEmpty {
      let chosenSub: MediaServerStreamDTO?
      if preferChineseSub, let zh = subtitleStreams.first(where: \.isChineseTrack) {
        chosenSub = zh
      } else {
        chosenSub = subtitleStreams.first(where: \.isDefault) ?? subtitleStreams.first
      }
      if let chosenSub {
        subDisabled = false
        chosenSubLang = chosenSub.language
        chosenSubTitle = chosenSub.resolvedLabel
        if let extID = chosenSub.subtitleId, !extID.isEmpty {
          chosenExternalID = extID
        } else if let ordinal = embeddedSubs.firstIndex(where: { $0.id == chosenSub.id }) {
          chosenSubOrdinal = ordinal
        }
      }
    }

    return MediaPlaybackTrackSelection(
      mediaSourceID: source.id,
      audioOrdinal: audioIndex,
      audioLanguage: chosenAudio?.language,
      audioDisplayTitle: chosenAudio?.resolvedLabel,
      subtitleDisabled: subDisabled,
      subtitleOrdinal: chosenSubOrdinal,
      subtitleExternalID: chosenExternalID,
      subtitleLanguage: chosenSubLang,
      subtitleDisplayTitle: chosenSubTitle
    )
  }

  /// 构造选择特定字幕轨道后的新选择状态（自动区分外挂字幕与内嵌字幕序号）。
  public func selectingSubtitle(
    _ stream: MediaServerStreamDTO?,
    in source: MediaServerSourceDTO?
  ) -> MediaPlaybackTrackSelection {
    var copy = self
    guard let stream else {
      copy.subtitleDisabled = true
      copy.subtitleOrdinal = nil
      copy.subtitleExternalID = nil
      copy.subtitleLanguage = nil
      copy.subtitleDisplayTitle = "关闭字幕"
      return copy
    }
    copy.subtitleDisabled = false
    copy.subtitleLanguage = stream.language
    copy.subtitleDisplayTitle = stream.resolvedLabel
    if let extID = stream.subtitleId, !extID.isEmpty {
      copy.subtitleExternalID = extID
      copy.subtitleOrdinal = nil
    } else {
      let embedded = (source?.subtitleStreams ?? []).filter {
        !$0.isExternal && $0.subtitleId == nil
      }
      copy.subtitleExternalID = nil
      copy.subtitleOrdinal = embedded.firstIndex(where: { $0.id == stream.id })
    }
    return copy
  }

  /// 构造选择特定音轨后的新选择状态。
  public func selectingAudio(
    _ stream: MediaServerStreamDTO,
    in source: MediaServerSourceDTO?
  ) -> MediaPlaybackTrackSelection {
    var copy = self
    let audios = source?.audioStreams ?? []
    copy.audioOrdinal = audios.firstIndex(where: { $0.id == stream.id })
    copy.audioLanguage = stream.language
    copy.audioDisplayTitle = stream.resolvedLabel
    return copy
  }
}

/// 媒体服务器模块内部统一导航目标（支持从发现、搜索、浏览与三层详情间任意下钻）。
public enum MediaServerNavigationTarget: Hashable, Sendable {
  case library(
    server: String,
    serverType: String?,
    libraryID: String?,
    libraryName: String,
    libraryType: String?,
    externalLink: String?,
    serverID: String?
  )
  case detail(
    server: String?,
    itemID: String,
    fallbackTitle: String?,
    fallbackItemType: String?,
    fallbackPoster: String?
  )
}
