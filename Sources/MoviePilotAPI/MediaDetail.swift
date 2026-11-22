import Foundation

/// 跨媒体源兼容的人物图片集合，既支持单个字符串 URL，也支持后端 `MediaImageSet` 多尺寸字典。
public struct MediaImageSet: Decodable, Equatable, Sendable {
  public let large: String?
  public let common: String?
  public let medium: String?
  public let normal: String?
  public let small: String?
  public let grid: String?

  public init(
    large: String? = nil,
    common: String? = nil,
    medium: String? = nil,
    normal: String? = nil,
    small: String? = nil,
    grid: String? = nil
  ) {
    self.large = large
    self.common = common
    self.medium = medium
    self.normal = normal
    self.small = small
    self.grid = grid
  }

  /// 兼容豆瓣/TMDB 字符串头像与豆瓣/Bangumi/AniList 多尺寸对象。
  public init(from decoder: Decoder) throws {
    if let single = try? decoder.singleValueContainer(),
      let raw = try? single.decode(String.self)
    {
      let trimmed = Self.trimmedNonEmpty(raw)
      self.large = nil
      self.common = nil
      self.medium = nil
      self.normal = trimmed
      self.small = nil
      self.grid = nil
      return
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.large = Self.decodeURL(container, forKey: .large)
    self.common = Self.decodeURL(container, forKey: .common)
    self.medium = Self.decodeURL(container, forKey: .medium)
    self.normal = Self.decodeURL(container, forKey: .normal)
    self.small = Self.decodeURL(container, forKey: .small)
    self.grid = Self.decodeURL(container, forKey: .grid)
  }

  /// 按来源习惯挑选首选头像地址（豆瓣优先 `normal`，Bangumi 优先 `medium`，其余优先 `large`）。
  public func preferredURL(forSource source: String? = nil) -> String? {
    let candidates: [String?]
    switch source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "douban":
      candidates = [normal, large, medium, common, small, grid]
    case "bangumi":
      candidates = [medium, large, common, normal, small, grid]
    default:
      candidates = [large, medium, normal, common, small, grid]
    }
    for candidate in candidates {
      if let value = Self.trimmedNonEmpty(candidate) {
        return value
      }
    }
    return nil
  }

  private static func decodeURL(
    _ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys
  ) -> String? {
    if let direct = try? container.decodeIfPresent(String.self, forKey: key) {
      return trimmedNonEmpty(direct)
    }
    if let nested = try? container.decodeIfPresent(NestedURL.self, forKey: key) {
      return trimmedNonEmpty(nested.url)
    }
    return nil
  }

  private static func trimmedNonEmpty(_ raw: String?) -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
    else { return nil }
    return trimmed
  }

  private struct NestedURL: Decodable {
    let url: String?
  }

  private enum CodingKeys: String, CodingKey {
    case large
    case common
    case medium
    case normal
    case small
    case grid
  }
}

/// 后端影视风格或制作国家标签，同时兼容 `{"name": "..."}` 对象与纯字符串元素。
public struct MediaNamedTag: Decodable, Equatable, Sendable {
  public let name: String?

  public init(name: String?) {
    self.name = name
  }

  public init(from decoder: Decoder) throws {
    if let single = try? decoder.singleValueContainer(),
      let text = try? single.decode(String.self)
    {
      self.name = text
      return
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.name = try container.decodeIfPresent(String.self, forKey: .name)
  }

  private enum CodingKeys: String, CodingKey {
    case name
  }
}

/// 剧集单季信息投影，兼容 `season_info` 中可选 `season_number` 与标量字符串数字。
public struct MediaSeasonSummary: Decodable, Equatable, Sendable, Identifiable {
  public let seasonNumber: Int
  public let name: String?
  public let airDate: String?
  public let episodeCount: Int?
  public let overview: String?
  public let posterPath: String?

  public init(
    seasonNumber: Int,
    name: String? = nil,
    airDate: String? = nil,
    episodeCount: Int? = nil,
    overview: String? = nil,
    posterPath: String? = nil
  ) {
    self.seasonNumber = seasonNumber
    self.name = name
    self.airDate = airDate
    self.episodeCount = episodeCount
    self.overview = overview
    self.posterPath = posterPath
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard let parsedSeason = MediaDetailDecoding.flexibleInt(container, forKey: .seasonNumber)
    else {
      throw DecodingError.valueNotFound(
        Int.self,
        DecodingError.Context(
          codingPath: container.codingPath + [CodingKeys.seasonNumber],
          debugDescription: "Missing season_number"))
    }
    self.seasonNumber = parsedSeason
    self.name = try? container.decodeIfPresent(String.self, forKey: .name)
    self.airDate = try? container.decodeIfPresent(String.self, forKey: .airDate)
    self.episodeCount = MediaDetailDecoding.flexibleInt(container, forKey: .episodeCount)
    self.overview = try? container.decodeIfPresent(String.self, forKey: .overview)
    self.posterPath = try? container.decodeIfPresent(String.self, forKey: .posterPath)
  }

  /// 季号作为单季列表稳定标识。
  public var id: Int { seasonNumber }

  /// 后端缺省季名时使用本地第 N 季 / 特别篇标题。
  public var displayTitle: String {
    if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
      return name
    }
    return seasonNumber == 0 ? "特别篇" : "第 \(seasonNumber) 季"
  }

  private enum CodingKeys: String, CodingKey {
    case seasonNumber = "season_number"
    case name
    case airDate = "air_date"
    case episodeCount = "episode_count"
    case overview
    case posterPath = "poster_path"
  }
}

/// 演职员与人物详情共享投影，兼容 TMDB / 豆瓣 / Bangumi / AniList 对象与纯字符串姓名。
public struct MediaPersonSummary: Decodable, Equatable, Sendable, Identifiable {
  public let source: String?
  public let numericID: Int?
  public let uri: String?
  public let name: String?
  public let originalName: String?
  public let latinName: String?
  public let character: String?
  public let knownForDepartment: String?
  public let roles: [String]
  public let career: [String]
  public let relation: String?
  public let profilePath: String?
  public let avatar: MediaImageSet?
  public let images: MediaImageSet?
  public let birthday: String?
  public let placeOfBirth: String?
  public let biography: String?
  public let alsoKnownAs: [String]

  /// 结合解析后的人物 ID 与姓名保证列表键唯一。
  public var id: String {
    if let resolved = resolvedPersonID { return "p:\(resolved)" }
    return "n:\(displayName):\(subtitle ?? "")"
  }

  /// 解析人物详情接口所需的数值 ID；豆瓣内嵌演职员优先从 `uri` 提取 `subject_id`。
  public var resolvedPersonID: Int? {
    if let uri, let subjectID = Self.extractDoubanSubjectID(from: uri) {
      return subjectID
    }
    return numericID
  }

  /// 优先展示本地化姓名，缺省回落原名或拉丁名。
  public var displayName: String {
    for candidate in [name, originalName, latinName] {
      if let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
      {
        return trimmed
      }
    }
    return "演职员"
  }

  /// 角色或职业副标（兼容 TMDB `character`、豆瓣 `roles` 与 Bangumi `career`）。
  public var subtitle: String? {
    if source?.lowercased() == "bangumi", !career.isEmpty {
      return career.joined(separator: "、")
    }
    if let character = character?.trimmingCharacters(in: .whitespacesAndNewlines),
      !character.isEmpty
    {
      return character
    }
    if !roles.isEmpty {
      return roles.joined(separator: " / ")
    }
    if let dept = knownForDepartment?.trimmingCharacters(in: .whitespacesAndNewlines), !dept.isEmpty
    {
      return dept
    }
    if let relation = relation?.trimmingCharacters(in: .whitespacesAndNewlines), !relation.isEmpty {
      return relation
    }
    if !career.isEmpty {
      return career.joined(separator: "、")
    }
    return nil
  }

  /// 按指定来源提取人物头像引用，兼容 `profile_path`、`avatar`（字符串或字典）与 `images`。
  public func artworkPath(forSource fallbackSource: String? = nil) -> String? {
    let effectiveSource = source ?? fallbackSource
    if let profile = profilePath?.trimmingCharacters(in: .whitespacesAndNewlines), !profile.isEmpty
    {
      return profile
    }
    if let resolved = avatar?.preferredURL(forSource: effectiveSource) {
      return resolved
    }
    if let resolved = images?.preferredURL(forSource: effectiveSource) {
      return resolved
    }
    return nil
  }

  /// 兼容默认来源提取人物头像引用。
  public var artworkPath: String? {
    artworkPath(forSource: nil)
  }

  /// 兼容纯字符串姓名、`id` 整型/字符串、`avatar` 字符串/字典以及 `images` 对象。
  public init(from decoder: Decoder) throws {
    if let single = try? decoder.singleValueContainer(),
      let plainName = try? single.decode(String.self)
    {
      let trimmed = plainName.trimmingCharacters(in: .whitespacesAndNewlines)
      self.source = nil
      self.numericID = nil
      self.uri = nil
      self.name = trimmed.isEmpty ? nil : trimmed
      self.originalName = nil
      self.latinName = nil
      self.character = nil
      self.knownForDepartment = nil
      self.roles = []
      self.career = []
      self.relation = nil
      self.profilePath = nil
      self.avatar = nil
      self.images = nil
      self.birthday = nil
      self.placeOfBirth = nil
      self.biography = nil
      self.alsoKnownAs = []
      return
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.source = try? container.decodeIfPresent(String.self, forKey: .source)
    self.numericID = MediaDetailDecoding.flexibleInt(container, forKey: .id)
    self.uri = try? container.decodeIfPresent(String.self, forKey: .uri)
    self.name = try? container.decodeIfPresent(String.self, forKey: .name)
    self.originalName = try? container.decodeIfPresent(String.self, forKey: .originalName)
    self.latinName = try? container.decodeIfPresent(String.self, forKey: .latinName)
    self.character = try? container.decodeIfPresent(String.self, forKey: .character)
    self.knownForDepartment = try? container.decodeIfPresent(
      String.self, forKey: .knownForDepartment)
    self.roles =
      (try? container.decodeIfPresent([String].self, forKey: .roles))?
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty } ?? []
    self.career =
      (try? container.decodeIfPresent([String].self, forKey: .career))?
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty } ?? []
    self.relation = try? container.decodeIfPresent(String.self, forKey: .relation)
    self.profilePath = try? container.decodeIfPresent(String.self, forKey: .profilePath)
    self.avatar = try? container.decodeIfPresent(MediaImageSet.self, forKey: .avatar)
    self.images = try? container.decodeIfPresent(MediaImageSet.self, forKey: .images)
    self.birthday = try? container.decodeIfPresent(String.self, forKey: .birthday)
    self.placeOfBirth = try? container.decodeIfPresent(String.self, forKey: .placeOfBirth)
    self.biography = try? container.decodeIfPresent(String.self, forKey: .biography)
    self.alsoKnownAs =
      (try? container.decodeIfPresent([String].self, forKey: .alsoKnownAs))?
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty } ?? []
  }

  private static func extractDoubanSubjectID(from uri: String) -> Int? {
    guard let components = URLComponents(string: uri),
      let queryValue = components.queryItems?.first(where: { $0.name == "subject_id" })?.value
    else { return nil }
    return Int(queryValue.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  private enum CodingKeys: String, CodingKey {
    case source
    case id
    case uri
    case name
    case originalName = "original_name"
    case latinName = "latin_name"
    case character
    case knownForDepartment = "known_for_department"
    case roles
    case career
    case relation
    case profilePath = "profile_path"
    case avatar
    case images
    case birthday
    case placeOfBirth = "place_of_birth"
    case biography
    case alsoKnownAs = "also_known_as"
  }
}

/// 完整影视详情响应投影，兼容 TMDB / 豆瓣 / Bangumi / AniList 的字段差异与演职员混合结构。
public struct MediaDetailPayload: Decodable, Equatable, Sendable {
  public let mediaSource: String?
  public let mediaID: String?
  public let tmdbID: Int?
  public let doubanID: String?
  public let bangumiID: Int?
  public let anilistID: Int?
  public let imdbID: String?
  public let type: String?
  public let title: String?
  public let originalTitle: String?
  public let year: String?
  public let releaseDate: String?
  public let runtime: Int?
  public let status: String?
  public let tagline: String?
  public let contentRating: String?
  public let numberOfSeasons: Int?
  public let numberOfEpisodes: Int?
  public let posterPath: String?
  public let backdropPath: String?
  public let logoPath: String?
  public let overview: String?
  public let voteAverage: Double?
  public let genres: [MediaNamedTag]?
  public let productionCountries: [MediaNamedTag]?
  public let seasonInfo: [MediaSeasonSummary]?
  public let seasons: [Int: [Int]]
  public let seasonYears: [Int: String]
  public let actors: [MediaPersonSummary]?
  public let directors: [MediaPersonSummary]?

  /// 提取清洗后的风格名称列表。
  public var genreNames: [String] {
    (genres ?? []).compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  /// 优先展示 `season_info`，当豆瓣剧集仅提供 `seasons` / `season_years` 时自动拼装单季卡片。
  public var resolvedSeasons: [MediaSeasonSummary] {
    let explicit = seasonInfo ?? []
    if !explicit.isEmpty {
      let regular = explicit.filter { $0.seasonNumber > 0 }
        .sorted { $0.seasonNumber < $1.seasonNumber }
      let specials = explicit.filter { $0.seasonNumber == 0 }
      return regular + specials
    }
    guard !seasons.isEmpty else { return [] }
    let synthesized = seasons.map { seasonNumber, episodes in
      MediaSeasonSummary(
        seasonNumber: seasonNumber,
        name: nil,
        airDate: seasonYears[seasonNumber],
        episodeCount: episodes.isEmpty ? nil : episodes.count,
        overview: nil,
        posterPath: nil
      )
    }
    let regular = synthesized.filter { $0.seasonNumber > 0 }
      .sorted { $0.seasonNumber < $1.seasonNumber }
    let specials = synthesized.filter { $0.seasonNumber == 0 }
    return regular + specials
  }

  /// 宽容解码跨媒体源详情，单个嵌套异常元素不会导致整页详情加载失败。
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.mediaSource = try? container.decodeIfPresent(String.self, forKey: .mediaSource)
    self.mediaID = MediaDetailDecoding.flexibleScalarString(container, forKey: .mediaID)
    self.tmdbID = MediaDetailDecoding.flexibleInt(container, forKey: .tmdbID)
    self.doubanID = MediaDetailDecoding.flexibleScalarString(container, forKey: .doubanID)
    self.bangumiID = MediaDetailDecoding.flexibleInt(container, forKey: .bangumiID)
    self.anilistID = MediaDetailDecoding.flexibleInt(container, forKey: .anilistID)
    self.imdbID = try? container.decodeIfPresent(String.self, forKey: .imdbID)
    self.type = try? container.decodeIfPresent(String.self, forKey: .type)
    self.title = try? container.decodeIfPresent(String.self, forKey: .title)

    let rawOriginalTitle = try? container.decodeIfPresent(String.self, forKey: .originalTitle)
    let rawOriginalName = try? container.decodeIfPresent(String.self, forKey: .originalName)
    self.originalTitle = Self.firstNonEmpty(rawOriginalTitle, rawOriginalName)

    self.year = MediaDetailDecoding.flexibleScalarString(container, forKey: .year)

    let rawReleaseDate = try? container.decodeIfPresent(String.self, forKey: .releaseDate)
    let rawFirstAirDate = try? container.decodeIfPresent(String.self, forKey: .firstAirDate)
    self.releaseDate = Self.firstNonEmpty(rawReleaseDate, rawFirstAirDate)

    let parsedRuntime = MediaDetailDecoding.flexibleInt(container, forKey: .runtime)
    if let parsedRuntime, parsedRuntime > 0 {
      self.runtime = parsedRuntime
    } else if let runTimes = try? container.decodeIfPresent([Int].self, forKey: .episodeRunTime),
      let firstPositive = runTimes.first(where: { $0 > 0 })
    {
      self.runtime = firstPositive
    } else {
      self.runtime = parsedRuntime
    }

    self.status = try? container.decodeIfPresent(String.self, forKey: .status)
    self.tagline = try? container.decodeIfPresent(String.self, forKey: .tagline)
    self.contentRating = try? container.decodeIfPresent(String.self, forKey: .contentRating)
    self.numberOfSeasons = MediaDetailDecoding.flexibleInt(container, forKey: .numberOfSeasons)
    self.numberOfEpisodes = MediaDetailDecoding.flexibleInt(container, forKey: .numberOfEpisodes)
    self.posterPath = try? container.decodeIfPresent(String.self, forKey: .posterPath)
    self.backdropPath = try? container.decodeIfPresent(String.self, forKey: .backdropPath)
    self.logoPath = try? container.decodeIfPresent(String.self, forKey: .logoPath)
    self.overview = try? container.decodeIfPresent(String.self, forKey: .overview)
    self.voteAverage = MediaDetailDecoding.flexibleDouble(container, forKey: .voteAverage)
    self.genres = MediaDetailDecoding.lossyArray(
      container, forKey: .genres, as: MediaNamedTag.self)
    self.productionCountries = MediaDetailDecoding.lossyArray(
      container, forKey: .productionCountries, as: MediaNamedTag.self)
    self.seasonInfo = MediaDetailDecoding.lossyArray(
      container, forKey: .seasonInfo, as: MediaSeasonSummary.self)

    if let rawSeasons = try? container.decodeIfPresent([String: [Int]].self, forKey: .seasons) {
      var parsed: [Int: [Int]] = [:]
      for (key, episodes) in rawSeasons {
        if let seasonNumber = Int(key) { parsed[seasonNumber] = episodes }
      }
      self.seasons = parsed
    } else {
      self.seasons = [:]
    }

    if let rawYears = try? container.decodeIfPresent(
      [String: MediaFlexibleScalar].self, forKey: .seasonYears)
    {
      var parsed: [Int: String] = [:]
      for (key, value) in rawYears {
        if let seasonNumber = Int(key), !value.value.isEmpty {
          parsed[seasonNumber] = value.value
        }
      }
      self.seasonYears = parsed
    } else {
      self.seasonYears = [:]
    }

    self.actors = MediaDetailDecoding.lossyArray(
      container, forKey: .actors, as: MediaPersonSummary.self)
    self.directors = MediaDetailDecoding.lossyArray(
      container, forKey: .directors, as: MediaPersonSummary.self)
  }

  private static func firstNonEmpty(_ values: String?...) -> String? {
    for value in values {
      if let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
        return trimmed
      }
    }
    return nil
  }

  private enum CodingKeys: String, CodingKey {
    case mediaSource = "media_source"
    case mediaID = "media_id"
    case tmdbID = "tmdb_id"
    case doubanID = "douban_id"
    case bangumiID = "bangumi_id"
    case anilistID = "anilist_id"
    case imdbID = "imdb_id"
    case type
    case title
    case originalTitle = "original_title"
    case originalName = "original_name"
    case year
    case releaseDate = "release_date"
    case firstAirDate = "first_air_date"
    case runtime
    case episodeRunTime = "episode_run_time"
    case status
    case tagline
    case contentRating = "content_rating"
    case numberOfSeasons = "number_of_seasons"
    case numberOfEpisodes = "number_of_episodes"
    case posterPath = "poster_path"
    case backdropPath = "backdrop_path"
    case logoPath = "logo_path"
    case overview
    case voteAverage = "vote_average"
    case genres
    case productionCountries = "production_countries"
    case seasonInfo = "season_info"
    case seasons
    case seasonYears = "season_years"
    case actors
    case directors
  }
}

/// 推荐作品与人物参演作品使用的轻量摘要模型，兼容 TMDB / 豆瓣 / Bangumi / AniList 身份字段。
public struct MediaSummaryItem: Decodable, Equatable, Sendable, Identifiable {
  public let mediaSource: String?
  public let mediaID: String?
  public let tmdbID: Int?
  public let doubanID: String?
  public let bangumiID: Int?
  public let anilistID: Int?
  public let type: String?
  public let title: String?
  public let year: String?
  public let posterPath: String?

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.mediaSource = try? container.decodeIfPresent(String.self, forKey: .mediaSource)
    self.mediaID = MediaDetailDecoding.flexibleScalarString(container, forKey: .mediaID)
    self.tmdbID = MediaDetailDecoding.flexibleInt(container, forKey: .tmdbID)
    self.doubanID = MediaDetailDecoding.flexibleScalarString(container, forKey: .doubanID)
    self.bangumiID = MediaDetailDecoding.flexibleInt(container, forKey: .bangumiID)
    self.anilistID = MediaDetailDecoding.flexibleInt(container, forKey: .anilistID)
    self.type = try? container.decodeIfPresent(String.self, forKey: .type)
    self.title = try? container.decodeIfPresent(String.self, forKey: .title)
    self.year = MediaDetailDecoding.flexibleScalarString(container, forKey: .year)
    self.posterPath = try? container.decodeIfPresent(String.self, forKey: .posterPath)
  }

  /// 优先使用规范媒体身份作为唯一键。
  public var id: String {
    if let resolved = resolvedIdentity() {
      return [resolved.source, resolved.mediaID, resolved.type].joined(separator: "|")
    }
    return "\(title ?? "item")|\(year ?? "")|\(posterPath ?? "")"
  }

  /// 构造可推入详情页的规范媒体身份（按显式 `media_source`/`media_id` 与各源专用 ID 回退）。
  public func resolvedIdentity(fallbackSource: String = "themoviedb") -> (
    source: String, mediaID: String, type: String
  )? {
    let resolvedSource: String
    let resolvedID: String?
    if let explicitSource = Self.nonEmpty(mediaSource),
      let explicitID = Self.nonEmpty(mediaID), explicitID != "0"
    {
      resolvedSource = explicitSource
      resolvedID = explicitID
    } else if let tmdbID, tmdbID > 0 {
      resolvedSource = "themoviedb"
      resolvedID = String(tmdbID)
    } else if let doubanID = Self.nonEmpty(doubanID), doubanID != "0" {
      resolvedSource = "douban"
      resolvedID = doubanID
    } else if let bangumiID, bangumiID > 0 {
      resolvedSource = "bangumi"
      resolvedID = String(bangumiID)
    } else if let anilistID, anilistID > 0 {
      resolvedSource = "anilist"
      resolvedID = String(anilistID)
    } else if let explicitID = Self.nonEmpty(mediaID), explicitID != "0" {
      resolvedSource = fallbackSource
      resolvedID = explicitID
    } else {
      return nil
    }
    guard let idValue = resolvedID else { return nil }
    let resolvedType = Self.normalizeMediaType(type) ?? "电影"
    return (source: resolvedSource, mediaID: idValue, type: resolvedType)
  }

  /// 将后端或别名影视类型规范为 `电影` 或 `电视剧`，非法/未知类型返回 `nil` 供调用方回退。
  public static func normalizeMediaType(_ raw: String?) -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
    else { return nil }
    switch trimmed.lowercased() {
    case "电影", "movie":
      return "电影"
    case "电视剧", "剧集", "tv":
      return "电视剧"
    default:
      return nil
    }
  }

  private static func nonEmpty(_ raw: String?) -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
    else { return nil }
    return trimmed
  }

  private enum CodingKeys: String, CodingKey {
    case mediaSource = "media_source"
    case mediaID = "media_id"
    case tmdbID = "tmdb_id"
    case doubanID = "douban_id"
    case bangumiID = "bangumi_id"
    case anilistID = "anilist_id"
    case type
    case title
    case year
    case posterPath = "poster_path"
  }
}

/// 跨媒体源（TMDB / 豆瓣 / Bangumi / AniList）演职员、推荐与人物详情接口路由构造器。
public enum MediaSourceEndpoint {
  /// 返回支持原生人物详情页的媒体来源集合。
  public static func supportsPersonDetail(source: String?) -> Bool {
    apiPrefix(for: source) != nil
  }

  /// 构造作品详情页的演职员表接口。
  public static func creditsEndpoint(
    for detail: MediaDetailPayload,
    fallbackSource: String,
    fallbackMediaID: String,
    type: String
  ) -> APIEndpoint? {
    let normalizedType = MediaSummaryItem.normalizeMediaType(type) ?? "电影"
    let source = (detail.mediaSource ?? fallbackSource).trimmingCharacters(
      in: .whitespacesAndNewlines
    ).lowercased()

    switch source {
    case "douban":
      if let doubanID = nonEmptyID(detail.doubanID ?? detail.mediaID ?? fallbackMediaID) {
        return try? APIEndpoint(path: ["douban", "credits", doubanID, normalizedType])
      }
    case "bangumi":
      if let bangumiID = detail.bangumiID ?? Int(detail.mediaID ?? fallbackMediaID), bangumiID > 0 {
        return try? APIEndpoint(path: ["bangumi", "credits", String(bangumiID)])
      }
    case "anilist":
      if let anilistID = detail.anilistID ?? Int(detail.mediaID ?? fallbackMediaID), anilistID > 0 {
        return try? APIEndpoint(path: ["anilist", "credits", String(anilistID)])
      }
    case "themoviedb", "tmdb":
      if let tmdbID = detail.tmdbID ?? Int(detail.mediaID ?? fallbackMediaID), tmdbID > 0 {
        return try? APIEndpoint(
          path: ["tmdb", "credits", String(tmdbID), normalizedType],
          query: [URLQueryItem(name: "page", value: "1")])
      }
    default:
      break
    }

    if let tmdbID = detail.tmdbID, tmdbID > 0 {
      return try? APIEndpoint(
        path: ["tmdb", "credits", String(tmdbID), normalizedType],
        query: [URLQueryItem(name: "page", value: "1")])
    }
    if let doubanID = nonEmptyID(detail.doubanID) {
      return try? APIEndpoint(path: ["douban", "credits", doubanID, normalizedType])
    }
    if let bangumiID = detail.bangumiID, bangumiID > 0 {
      return try? APIEndpoint(path: ["bangumi", "credits", String(bangumiID)])
    }
    if let anilistID = detail.anilistID, anilistID > 0 {
      return try? APIEndpoint(path: ["anilist", "credits", String(anilistID)])
    }
    return nil
  }

  /// 构造作品详情页的推荐/相似作品接口候选顺序。
  public static func recommendationEndpoints(
    for detail: MediaDetailPayload,
    fallbackSource: String,
    fallbackMediaID: String,
    type: String
  ) -> [APIEndpoint] {
    let normalizedType = MediaSummaryItem.normalizeMediaType(type) ?? "电影"
    let source = (detail.mediaSource ?? fallbackSource).trimmingCharacters(
      in: .whitespacesAndNewlines
    ).lowercased()

    switch source {
    case "douban":
      if let doubanID = nonEmptyID(detail.doubanID ?? detail.mediaID ?? fallbackMediaID),
        let endpoint = try? APIEndpoint(
          path: ["douban", "recommend", doubanID, normalizedType],
          query: [URLQueryItem(name: "page", value: "1")])
      {
        return [endpoint]
      }
    case "bangumi":
      if let bangumiID = detail.bangumiID ?? Int(detail.mediaID ?? fallbackMediaID), bangumiID > 0,
        let endpoint = try? APIEndpoint(
          path: ["bangumi", "recommend", String(bangumiID)],
          query: [URLQueryItem(name: "page", value: "1")])
      {
        return [endpoint]
      }
    case "anilist":
      if let anilistID = detail.anilistID ?? Int(detail.mediaID ?? fallbackMediaID), anilistID > 0,
        let endpoint = try? APIEndpoint(
          path: ["anilist", "recommend", String(anilistID)],
          query: [URLQueryItem(name: "page", value: "1")])
      {
        return [endpoint]
      }
    case "themoviedb", "tmdb":
      if let tmdbID = detail.tmdbID ?? Int(detail.mediaID ?? fallbackMediaID), tmdbID > 0 {
        return tmdbRecommendationEndpoints(tmdbID: tmdbID, type: normalizedType)
      }
    default:
      break
    }

    if let tmdbID = detail.tmdbID, tmdbID > 0 {
      return tmdbRecommendationEndpoints(tmdbID: tmdbID, type: normalizedType)
    }
    if let doubanID = nonEmptyID(detail.doubanID),
      let endpoint = try? APIEndpoint(
        path: ["douban", "recommend", doubanID, normalizedType],
        query: [URLQueryItem(name: "page", value: "1")])
    {
      return [endpoint]
    }
    if let bangumiID = detail.bangumiID, bangumiID > 0,
      let endpoint = try? APIEndpoint(
        path: ["bangumi", "recommend", String(bangumiID)],
        query: [URLQueryItem(name: "page", value: "1")])
    {
      return [endpoint]
    }
    if let anilistID = detail.anilistID, anilistID > 0,
      let endpoint = try? APIEndpoint(
        path: ["anilist", "recommend", String(anilistID)],
        query: [URLQueryItem(name: "page", value: "1")])
    {
      return [endpoint]
    }
    return []
  }

  /// 构造人物详情接口（支持 `themoviedb` / `douban` / `bangumi` / `anilist`）。
  public static func personDetailEndpoint(source: String, personID: Int) -> APIEndpoint? {
    guard let prefix = apiPrefix(for: source) else { return nil }
    return try? APIEndpoint(path: [prefix, "person", String(personID)])
  }

  /// 构造人物参演作品接口（支持 `themoviedb` / `douban` / `bangumi` / `anilist`）。
  public static func personCreditsEndpoint(
    source: String, personID: Int, page: Int = 1
  ) -> APIEndpoint? {
    guard let prefix = apiPrefix(for: source) else { return nil }
    return try? APIEndpoint(
      path: [prefix, "person", "credits", String(personID)],
      query: [URLQueryItem(name: "page", value: String(max(page, 1)))])
  }

  private static func apiPrefix(for source: String?) -> String? {
    switch source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "themoviedb", "tmdb": "tmdb"
    case "douban": "douban"
    case "bangumi": "bangumi"
    case "anilist": "anilist"
    default: nil
    }
  }

  private static func tmdbRecommendationEndpoints(tmdbID: Int, type: String) -> [APIEndpoint] {
    var result: [APIEndpoint] = []
    if let rec = try? APIEndpoint(
      path: ["tmdb", "recommend", String(tmdbID), type],
      query: [URLQueryItem(name: "page", value: "1")])
    {
      result.append(rec)
    }
    if let sim = try? APIEndpoint(
      path: ["tmdb", "similar", String(tmdbID), type],
      query: [URLQueryItem(name: "page", value: "1")])
    {
      result.append(sim)
    }
    return result
  }

  private static func nonEmptyID(_ raw: String?) -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty, trimmed != "0"
    else { return nil }
    return trimmed
  }
}

private struct MediaFlexibleScalar: Decodable {
  let value: String

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let text = try? container.decode(String.self) {
      value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    } else if let intVal = try? container.decode(Int64.self) {
      value = String(intVal)
    } else if let doubleVal = try? container.decode(Double.self) {
      value = String(doubleVal)
    } else {
      value = ""
    }
  }
}

private struct LossyDecodable<Element: Decodable>: Decodable {
  let value: Element?

  init(from decoder: Decoder) throws {
    value = try? Element(from: decoder)
  }
}

private enum MediaDetailDecoding {
  static func flexibleScalarString<Key: CodingKey>(
    _ container: KeyedDecodingContainer<Key>, forKey key: Key
  ) -> String? {
    if let text = try? container.decodeIfPresent(String.self, forKey: key) {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    if let number = try? container.decodeIfPresent(Int64.self, forKey: key) {
      return number == 0 ? nil : String(number)
    }
    return nil
  }

  static func flexibleInt<Key: CodingKey>(
    _ container: KeyedDecodingContainer<Key>, forKey key: Key
  ) -> Int? {
    if let number = try? container.decodeIfPresent(Int.self, forKey: key) {
      return number
    }
    if let text = try? container.decodeIfPresent(String.self, forKey: key) {
      return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    if let number = try? container.decodeIfPresent(Double.self, forKey: key), number.isFinite {
      return Int(number)
    }
    return nil
  }

  static func flexibleDouble<Key: CodingKey>(
    _ container: KeyedDecodingContainer<Key>, forKey key: Key
  ) -> Double? {
    if let number = try? container.decodeIfPresent(Double.self, forKey: key) {
      return number
    }
    if let text = try? container.decodeIfPresent(String.self, forKey: key) {
      return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return nil
  }

  static func lossyArray<Key: CodingKey, Element: Decodable>(
    _ container: KeyedDecodingContainer<Key>, forKey key: Key, as _: Element.Type
  ) -> [Element]? {
    guard let wrapped = try? container.decodeIfPresent([LossyDecodable<Element>].self, forKey: key)
    else { return nil }
    return wrapped.compactMap(\.value)
  }
}
