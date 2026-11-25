import Foundation
import MoviePilotAPI
import MoviePilotCore

// MARK: - Backend DTOs

struct DanmakuStatusDTO: Decodable, Sendable {
  let enabled: Bool
}

struct DanmakuCacheStatsDTO: Decodable, Sendable, Equatable {
  let fileCount: Int
  let totalBytes: Int
  let maxMb: Int
}

struct DanmakuConfigDTO: Decodable, Sendable, Equatable {
  let enabled: Bool
  let apiBaseUrl: String
  let authMode: String
  let appId: String
  let hasAppSecret: Bool
  let tokenHeader: String
  let tokenPrefix: String
  let hasToken: Bool
  let withRelated: Bool
  let chConvert: Int
  let cacheTtlHours: Int
  let cacheMaxMb: Int
  let timeoutSeconds: Int
  let useProxy: Bool
  let verifyTls: Bool
  let cacheStats: DanmakuCacheStatsDTO
}

struct DanmakuConfigUpdatePayload: Encodable, Sendable {
  let enabled: Bool
  let apiBaseUrl: String
  let authMode: String
  let appId: String
  let appSecret: String?
  let clearAppSecret: Bool
  let tokenHeader: String
  let tokenPrefix: String
  let token: String?
  let clearToken: Bool
  let withRelated: Bool
  let chConvert: Int
  let cacheTtlHours: Int
  let cacheMaxMb: Int
  let timeoutSeconds: Int
  let useProxy: Bool
  let verifyTls: Bool
}

struct DanmakuConfigTestPayload: Encodable, Sendable {
  let apiBaseUrl: String?
  let authMode: String?
  let appId: String?
  let appSecret: String?
  let tokenHeader: String?
  let tokenPrefix: String?
  let token: String?
  let timeoutSeconds: Int?
  let useProxy: Bool?
  let verifyTls: Bool?
}

struct DanmakuConfigTestResultDTO: Decodable, Sendable {
  let ok: Bool
  let latencyMs: Int
  let statusCode: Int?
  let message: String
}

struct DanmakuCacheClearResultDTO: Decodable, Sendable {
  let removedFiles: Int
  let freedBytes: Int
}

struct DanmakuEpisodeCandidateDTO: Decodable, Sendable, Identifiable, Equatable {
  let episodeId: Int
  let animeId: Int?
  let animeTitle: String
  let episodeTitle: String
  let episodeNumber: String?
  let animeType: String?
  let shiftMs: Int

  var id: Int { episodeId }
}

struct DanmakuMatchRequestPayload: Encodable, Sendable {
  let itemId: String?
  let server: String?
  let title: String?
  let seriesName: String?
  let seasonNumber: Int?
  let episodeNumber: Int?
  let year: Int?
  let tmdbId: String?
  let fileName: String?
  let fileSize: Int?
  let durationMs: Int?
}

struct DanmakuMatchResponseDTO: Decodable, Sendable {
  let matched: Bool
  let fromBinding: Bool
  let shiftMs: Int
  let episode: DanmakuEpisodeCandidateDTO?
  let candidates: [DanmakuEpisodeCandidateDTO]
}

struct DanmakuAnimeSearchItemDTO: Decodable, Sendable, Identifiable, Equatable {
  let animeId: Int
  let animeTitle: String
  let animeType: String?
  let episodeCount: Int?
  let episodes: [DanmakuEpisodeCandidateDTO]

  var id: Int { animeId }
}

struct DanmakuBangumiDTO: Decodable, Sendable {
  let animeId: Int
  let animeTitle: String
  let animeType: String?
  let episodes: [DanmakuEpisodeCandidateDTO]
}

struct DanmakuBindingRequestPayload: Encodable, Sendable {
  let server: String?
  let itemId: String?
  let tmdbId: String?
  let seasonNumber: Int?
  let episodeNumber: Int?
  let episodeId: Int
  let animeId: Int?
  let animeTitle: String
  let episodeTitle: String
  let shiftMs: Int
}

struct DanmakuCommentsRawResponse: Sendable {
  let rawJSON: String
  let etag: String?
  let fromCache: Bool
}

enum DanmakuRepositoryError: LocalizedError {
  case unauthorized
  case message(String)

  var errorDescription: String? {
    switch self {
    case .unauthorized: return L10n.text("登录已过期，请重新登录。")
    case .message(let text): return text
    }
  }
}

/// 同源 MoviePilot `/api/v1/danmaku/*` 客户端，内置内存 ETag 缓存与 `If-None-Match` 304 协商。
@MainActor
final class DanmakuRepository {
  private struct Envelope<Value: Decodable & Sendable>: Decodable, Sendable {
    let success: Bool
    let message: String?
    let data: Value?
  }

  private struct DetailError: Decodable, Sendable {
    let detail: String?
    let message: String?
  }

  private struct CachedCommentsEntry {
    let etag: String
    let rawJSON: String
  }

  private let address: ServerAddress
  private let accessToken: String
  private let session: URLSession
  private var commentsMemoryCache: [Int: CachedCommentsEntry] = [:]

  init(address: ServerAddress, accessToken: String) {
    self.address = address
    self.accessToken = accessToken
    let cfg = URLSessionConfiguration.ephemeral
    cfg.httpCookieStorage = nil
    cfg.httpShouldSetCookies = false
    cfg.urlCache = nil
    cfg.timeoutIntervalForRequest = 18
    cfg.timeoutIntervalForResource = 30
    self.session = URLSession(configuration: cfg)
  }

  private func buildURL(_ segments: [String], queryItems: [URLQueryItem] = []) throws -> URL {
    var url = address.url
    for seg in segments {
      url.appendPathComponent(seg, isDirectory: false)
    }
    if !queryItems.isEmpty, var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
      comps.queryItems = queryItems
      if let composed = comps.url { url = composed }
    }
    guard address.contains(url) else {
      throw DanmakuRepositoryError.message("请求地址超出当前实例范围")
    }
    return url
  }

  private func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return encoder
  }

  private func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }

  private func parseError(_ data: Data, fallback: String) -> String {
    if let parsed = try? JSONDecoder().decode(DetailError.self, from: data) {
      if let d = parsed.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
        return d
      }
      if let m = parsed.message?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty {
        return m
      }
    }
    return fallback
  }

  private func performEnvelope<T: Decodable & Sendable>(
    method: String,
    segments: [String],
    queryItems: [URLQueryItem] = [],
    body: Data? = nil,
    fallbackError: String
  ) async throws -> T {
    let url = try buildURL(segments, queryItems: queryItems)
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body {
      request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
      request.httpBody = body
    }
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw DanmakuRepositoryError.message(fallbackError)
    }
    if http.statusCode == 401
      || (http.statusCode == 403 && APIClient.isTokenInvalidForbiddenBody(data))
    {
      throw DanmakuRepositoryError.unauthorized
    }
    guard (200..<300).contains(http.statusCode) else {
      throw DanmakuRepositoryError.message(parseError(data, fallback: fallbackError))
    }
    let envelope = try makeDecoder().decode(Envelope<T>.self, from: data)
    guard envelope.success, let value = envelope.data else {
      throw DanmakuRepositoryError.message(envelope.message ?? fallbackError)
    }
    return value
  }

  func fetchStatus() async throws -> DanmakuStatusDTO {
    try await performEnvelope(
      method: "GET",
      segments: ["api", "v1", "danmaku", "status"],
      fallbackError: "查询弹幕状态失败"
    )
  }

  func match(_ payload: DanmakuMatchRequestPayload) async throws -> DanmakuMatchResponseDTO {
    let body = try makeEncoder().encode(payload)
    return try await performEnvelope(
      method: "POST",
      segments: ["api", "v1", "danmaku", "match"],
      body: body,
      fallbackError: "匹配弹幕失败"
    )
  }

  func search(keyword: String, episode: String? = nil) async throws -> [DanmakuAnimeSearchItemDTO] {
    var query = [URLQueryItem(name: "keyword", value: keyword)]
    if let episode, !episode.isEmpty {
      query.append(URLQueryItem(name: "episode", value: episode))
    }
    return try await performEnvelope(
      method: "GET",
      segments: ["api", "v1", "danmaku", "search"],
      queryItems: query,
      fallbackError: "搜索弹幕剧集失败"
    )
  }

  func fetchBangumi(animeId: Int) async throws -> DanmakuBangumiDTO {
    try await performEnvelope(
      method: "GET",
      segments: ["api", "v1", "danmaku", "bangumi", "\(animeId)"],
      fallbackError: "获取弹幕分集目录失败"
    )
  }

  /// 拉取单集弹幕载荷（自动启用 gzip 与 `If-None-Match` 304 协商）。
  func fetchComments(episodeId: Int, forceRefresh: Bool = false) async throws
    -> DanmakuCommentsRawResponse
  {
    var query: [URLQueryItem] = []
    if forceRefresh {
      query.append(URLQueryItem(name: "force_refresh", value: "true"))
    }
    let url = try buildURL(["api", "v1", "danmaku", "comments", "\(episodeId)"], queryItems: query)
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
    if !forceRefresh, let cached = commentsMemoryCache[episodeId] {
      request.setValue(cached.etag, forHTTPHeaderField: "If-None-Match")
    }
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw DanmakuRepositoryError.message("拉取弹幕失败")
    }
    if http.statusCode == 304, let cached = commentsMemoryCache[episodeId] {
      return DanmakuCommentsRawResponse(
        rawJSON: cached.rawJSON,
        etag: cached.etag,
        fromCache: true
      )
    }
    if http.statusCode == 401
      || (http.statusCode == 403 && APIClient.isTokenInvalidForbiddenBody(data))
    {
      throw DanmakuRepositoryError.unauthorized
    }
    guard (200..<300).contains(http.statusCode),
      let text = String(data: data, encoding: .utf8)
    else {
      throw DanmakuRepositoryError.message(parseError(data, fallback: "拉取弹幕失败"))
    }
    let etag = http.value(forHTTPHeaderField: "ETag")
    if let etag, !etag.isEmpty {
      commentsMemoryCache[episodeId] = CachedCommentsEntry(etag: etag, rawJSON: text)
      if commentsMemoryCache.count > 12 {
        commentsMemoryCache.removeAll(keepingCapacity: true)
        commentsMemoryCache[episodeId] = CachedCommentsEntry(etag: etag, rawJSON: text)
      }
    }
    return DanmakuCommentsRawResponse(rawJSON: text, etag: etag, fromCache: false)
  }

  func saveBinding(_ payload: DanmakuBindingRequestPayload) async throws -> DanmakuEpisodeCandidateDTO
  {
    let body = try makeEncoder().encode(payload)
    return try await performEnvelope(
      method: "PUT",
      segments: ["api", "v1", "danmaku", "bindings"],
      body: body,
      fallbackError: "保存弹幕绑定失败"
    )
  }

  func deleteBinding(
    server: String?,
    itemId: String?,
    tmdbId: String?,
    seasonNumber: Int?,
    episodeNumber: Int?
  ) async throws -> Bool {
    var query: [URLQueryItem] = []
    if let server, !server.isEmpty { query.append(URLQueryItem(name: "server", value: server)) }
    if let itemId, !itemId.isEmpty { query.append(URLQueryItem(name: "item_id", value: itemId)) }
    if let tmdbId, !tmdbId.isEmpty { query.append(URLQueryItem(name: "tmdb_id", value: tmdbId)) }
    if let seasonNumber { query.append(URLQueryItem(name: "season_number", value: "\(seasonNumber)")) }
    if let episodeNumber { query.append(URLQueryItem(name: "episode_number", value: "\(episodeNumber)")) }
    return try await performEnvelope(
      method: "DELETE",
      segments: ["api", "v1", "danmaku", "bindings"],
      queryItems: query,
      fallbackError: "解除弹幕绑定失败"
    )
  }

  // MARK: - Admin Config APIs

  func fetchAdminConfig() async throws -> DanmakuConfigDTO {
    try await performEnvelope(
      method: "GET",
      segments: ["api", "v1", "danmaku", "config"],
      fallbackError: "读取弹幕服务配置失败"
    )
  }

  func updateAdminConfig(_ payload: DanmakuConfigUpdatePayload) async throws -> DanmakuConfigDTO {
    let body = try makeEncoder().encode(payload)
    return try await performEnvelope(
      method: "PUT",
      segments: ["api", "v1", "danmaku", "config"],
      body: body,
      fallbackError: "保存弹幕服务配置失败"
    )
  }

  func testAdminConfig(_ payload: DanmakuConfigTestPayload) async throws
    -> DanmakuConfigTestResultDTO
  {
    let body = try makeEncoder().encode(payload)
    return try await performEnvelope(
      method: "POST",
      segments: ["api", "v1", "danmaku", "config", "test"],
      body: body,
      fallbackError: "测试弹幕服务连接失败"
    )
  }

  func clearServerCache() async throws -> DanmakuCacheClearResultDTO {
    try await performEnvelope(
      method: "DELETE",
      segments: ["api", "v1", "danmaku", "cache"],
      fallbackError: "清空服务端弹幕缓存失败"
    )
  }
}
