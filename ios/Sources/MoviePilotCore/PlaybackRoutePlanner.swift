import Foundation

/// 媒体流播放路由类型（与 Rust `mp_core_model::PlaybackRouteKind` 保持 1:1 语义一致）。
public enum PlaybackRouteKind: String, Codable, Sendable, Equatable, Hashable {
  case strmDirect = "strm_direct"
  case serverLan = "server_lan"
  case serverWan = "server_wan"
  case mpProxy = "mp_proxy"

  /// 面向用户展示的默认简体中文路由标签键（对应 `shared/l10n/app.strings.json`）。
  public var labelKey: String {
    switch self {
    case .strmDirect: return "STRM 直链"
    case .serverLan: return "局域网直连"
    case .serverWan: return "外网直连"
    case .mpProxy: return "后台中转"
    }
  }
}

/// 后端协商下发的单条候选播放路由。
public struct PlaybackRouteCandidate: Codable, Sendable, Equatable {
  public let kind: PlaybackRouteKind
  public let url: String
  public let probeUrl: String?
  public let headers: [String: String]
  public let priority: Int
  public let requiresSameOriginAuth: Bool

  public init(
    kind: PlaybackRouteKind,
    url: String,
    probeUrl: String? = nil,
    headers: [String: String] = [:],
    priority: Int = 100,
    requiresSameOriginAuth: Bool = false
  ) {
    self.kind = kind
    self.url = url
    self.probeUrl = probeUrl
    self.headers = headers
    self.priority = priority
    self.requiresSameOriginAuth = requiresSameOriginAuth
  }

  private enum CodingKeys: String, CodingKey {
    case kind
    case url
    case probeUrl
    case headers
    case priority
    case requiresSameOriginAuth
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    kind = try container.decode(PlaybackRouteKind.self, forKey: .kind)
    url = try container.decode(String.self, forKey: .url)
    probeUrl = try container.decodeIfPresent(String.self, forKey: .probeUrl)
    headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
    priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 100
    requiresSameOriginAuth =
      try container.decodeIfPresent(Bool.self, forKey: .requiresSameOriginAuth) ?? false
  }
}

/// 客户端播放路由偏好。
public struct PlaybackRoutePreference: Codable, Sendable, Equatable {
  public let preferStrmDirect: Bool
  public let preferServerDirect: Bool
  public let lanPreferredMaxLatencyMs: Int

  public init(
    preferStrmDirect: Bool = true,
    preferServerDirect: Bool = true,
    lanPreferredMaxLatencyMs: Int = 350
  ) {
    self.preferStrmDirect = preferStrmDirect
    self.preferServerDirect = preferServerDirect
    self.lanPreferredMaxLatencyMs = lanPreferredMaxLatencyMs
  }
}

/// 单条直连候选的轻量探测结果。
public struct RouteProbeOutcome: Codable, Sendable, Equatable {
  public let url: String
  public let reachable: Bool
  public let latencyMs: Int?

  public init(url: String, reachable: Bool, latencyMs: Int? = nil) {
    self.url = url
    self.reachable = reachable
    self.latencyMs = latencyMs
  }
}

/// 路由规划结果：主路由 + 有序降级队列。
public struct PlaybackRoutePlan: Codable, Sendable, Equatable {
  public let active: PlaybackRouteCandidate
  public let fallbacks: [PlaybackRouteCandidate]
  public let routeLabelKey: String

  public init(
    active: PlaybackRouteCandidate,
    fallbacks: [PlaybackRouteCandidate],
    routeLabelKey: String? = nil
  ) {
    self.active = active
    self.fallbacks = fallbacks
    self.routeLabelKey = routeLabelKey ?? active.kind.labelKey
  }
}

/// 跨端同构无状态播放路由规划器（与 Rust `PlaybackRoutePlanner` 完全对齐）。
public enum PlaybackRoutePlanner {
  /// 严格校验两条 HTTP(S) URL 的 scheme、host（大小写无关）与默认/显式端口是否一致。
  public static func isSameHttpOrigin(_ urlA: String, _ urlB: String) -> Bool {
    guard
      let a = URLComponents(string: urlA.trimmingCharacters(in: .whitespacesAndNewlines)),
      let b = URLComponents(string: urlB.trimmingCharacters(in: .whitespacesAndNewlines)),
      let schemeA = a.scheme?.lowercased(),
      let schemeB = b.scheme?.lowercased(),
      schemeA == "http" || schemeA == "https",
      schemeA == schemeB,
      let hostA = a.host?.lowercased(),
      let hostB = b.host?.lowercased(),
      !hostA.isEmpty,
      hostA == hostB
    else {
      return false
    }
    let portA = a.port ?? (schemeA == "https" ? 443 : 80)
    let portB = b.port ?? (schemeB == "https" ? 443 : 80)
    return portA == portB
  }

  /// 校验单条直连 URL 是否为不含内嵌凭据与片段的安全 HTTP(S) 地址。
  public static func isSafeHttpURL(_ raw: String) -> Bool {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      let comps = URLComponents(string: trimmed),
      let scheme = comps.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      let host = comps.host, !host.isEmpty,
      comps.user == nil, comps.password == nil, comps.fragment == nil
    else {
      return false
    }
    return true
  }

  /// 按用户偏好和并发探测结果计算主播放路由与降级回退队列。
  public static func plan(
    routes: [PlaybackRouteCandidate],
    preferences: PlaybackRoutePreference = .init(),
    probes: [RouteProbeOutcome]
  ) -> PlaybackRoutePlan? {
    var strmRoutes: [PlaybackRouteCandidate] = []
    var lanRoutes: [(latency: Int, candidate: PlaybackRouteCandidate)] = []
    var wanRoutes: [(latency: Int, candidate: PlaybackRouteCandidate)] = []
    var proxyRoutes: [PlaybackRouteCandidate] = []
    var seenKeys: Set<String> = []

    for route in routes {
      let trimmedURL = route.url.trimmingCharacters(in: .whitespacesAndNewlines)
      guard isSafeHttpURL(trimmedURL) else { continue }
      let dedupKey = "\(route.kind.rawValue)|\(trimmedURL)"
      guard seenKeys.insert(dedupKey).inserted else { continue }

      let normalized = PlaybackRouteCandidate(
        kind: route.kind,
        url: trimmedURL,
        probeUrl: route.probeUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
        headers: route.headers,
        priority: route.priority,
        requiresSameOriginAuth: route.requiresSameOriginAuth
      )

      switch normalized.kind {
      case .strmDirect:
        if preferences.preferStrmDirect {
          strmRoutes.append(normalized)
        }
      case .serverLan:
        guard preferences.preferServerDirect,
          let latency = reachableLatency(for: normalized, probes: probes)
        else { continue }
        lanRoutes.append((latency, normalized))
      case .serverWan:
        guard preferences.preferServerDirect,
          let latency = reachableLatency(for: normalized, probes: probes)
        else { continue }
        wanRoutes.append((latency, normalized))
      case .mpProxy:
        proxyRoutes.append(normalized)
      }
    }

    strmRoutes.sort { $0.priority < $1.priority }
    lanRoutes.sort { ($0.latency, $0.candidate.priority) < ($1.latency, $1.candidate.priority) }
    wanRoutes.sort { ($0.latency, $0.candidate.priority) < ($1.latency, $1.candidate.priority) }
    proxyRoutes.sort { $0.priority < $1.priority }

    var ordered: [PlaybackRouteCandidate] = []
    ordered.append(contentsOf: strmRoutes)

    let preferWanBeforeLan: Bool
    if let bestLan = lanRoutes.first?.latency, let bestWan = wanRoutes.first?.latency {
      preferWanBeforeLan = bestLan > preferences.lanPreferredMaxLatencyMs && bestWan < bestLan
    } else {
      preferWanBeforeLan = false
    }

    if preferWanBeforeLan {
      ordered.append(contentsOf: wanRoutes.map(\.candidate))
      ordered.append(contentsOf: lanRoutes.map(\.candidate))
    } else {
      ordered.append(contentsOf: lanRoutes.map(\.candidate))
      ordered.append(contentsOf: wanRoutes.map(\.candidate))
    }

    ordered.append(contentsOf: proxyRoutes)
    guard let active = ordered.first else { return nil }
    return PlaybackRoutePlan(
      active: active,
      fallbacks: Array(ordered.dropFirst()),
      routeLabelKey: active.kind.labelKey
    )
  }

  /// 为不支持自定义 `X-Emby-Token` / `X-Plex-Token` 请求头的 libVLC 构造仅驻留内存的直连媒体流 URL。
  public static func buildVlcDirectURL(url: URL, headers: [String: String]) -> URL {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return url
    }
    var lowerMap: [String: String] = [:]
    for (key, value) in headers where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      lowerMap[key.lowercased()] = value
    }
    var items = components.queryItems ?? []
    let existingLower = Set(items.map { $0.name.lowercased() })

    if let embyToken = lowerMap["x-emby-token"] ?? lowerMap["x-mediabrowser-token"] {
      if !existingLower.contains("api_key") && !existingLower.contains("x-emby-token") {
        items.append(URLQueryItem(name: "api_key", value: embyToken))
      }
    } else if let plexToken = lowerMap["x-plex-token"] {
      if !existingLower.contains("x-plex-token") {
        items.append(URLQueryItem(name: "X-Plex-Token", value: plexToken))
      }
    }

    components.queryItems = items.isEmpty ? nil : items
    return components.url ?? url
  }

  private static func reachableLatency(
    for route: PlaybackRouteCandidate,
    probes: [RouteProbeOutcome]
  ) -> Int? {
    let probeKey = route.probeUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      let outcome = probes.first(where: { item in
        let target = item.url.trimmingCharacters(in: .whitespacesAndNewlines)
        return (probeKey != nil && !probeKey!.isEmpty && target == probeKey)
          || target == route.url
      }),
      outcome.reachable
    else {
      return nil
    }
    return outcome.latencyMs ?? (Int.max / 2)
  }
}
