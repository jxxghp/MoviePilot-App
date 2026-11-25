import Foundation
import MoviePilotCore
import Network

/// 经探测与预检（含 Emby 302 跨源剥离凭据）后的可执行播放目标。
struct PreparedPlaybackTarget: Sendable {
  let route: PlaybackRouteCandidate
  let url: URL
  let headers: [String: String]
}

/// 拦截 3xx 重定向的轻量会话代理：遇到 302 立即停止自动跟随，交由调用方校验同源边界后再决定是否剥离直连凭据。
private final class NoRedirectSessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

/// 跨播放会话的直连路由探测器与网络指纹缓存中心：
/// - 通过 `NWPathMonitor` 监听 Wi-Fi / 蜂窝 / VPN 切换，自动递增 `networkEpoch` 使旧网探测缓存立即失效；
/// - 并发探测 `server_lan` / `server_wan` 轻量无认证端点（750ms 超时），结果按 `(server, networkEpoch)` 缓存 5 分钟；
/// - 某条直连路由起播失败或鉴权失效时记入 60 秒短时负缓存，避免连续切集重复踩坑。
actor PlaybackRouteResolver {
  static let shared = PlaybackRouteResolver()

  private struct CachedProbe {
    let outcome: RouteProbeOutcome
    let expiresAt: Date
  }

  private let probeTTL: TimeInterval = 300
  private let negativeCacheTTL: TimeInterval = 60
  private let probeSession: URLSession
  private let preflightSession: URLSession
  private let noRedirectDelegate = NoRedirectSessionDelegate()
  private let pathMonitor = NWPathMonitor()
  private let monitorQueue = DispatchQueue(label: "com.moviepilot.playback.route-monitor")

  private var networkEpoch: Int = 0
  private var lastPathFingerprint: String = ""
  private var probeCache: [String: CachedProbe] = [:]
  private var failedRouteUntil: [String: Date] = [:]

  init() {
    let probeConfig = URLSessionConfiguration.ephemeral
    probeConfig.httpCookieStorage = nil
    probeConfig.httpShouldSetCookies = false
    probeConfig.urlCache = nil
    probeConfig.timeoutIntervalForRequest = 0.75
    probeConfig.timeoutIntervalForResource = 0.95
    probeConfig.waitsForConnectivity = false
    self.probeSession = URLSession(configuration: probeConfig)

    let preflightConfig = URLSessionConfiguration.ephemeral
    preflightConfig.httpCookieStorage = nil
    preflightConfig.httpShouldSetCookies = false
    preflightConfig.urlCache = nil
    preflightConfig.timeoutIntervalForRequest = 1.2
    preflightConfig.timeoutIntervalForResource = 1.6
    preflightConfig.waitsForConnectivity = false
    self.preflightSession = URLSession(
      configuration: preflightConfig,
      delegate: noRedirectDelegate,
      delegateQueue: nil
    )

    Task { await self.startMonitoringNetworkChanges() }
  }

  /// 开始监听系统网络路径变化，切网时自动失效历史探测缓存。
  private func startMonitoringNetworkChanges() {
    pathMonitor.pathUpdateHandler = { [weak self] path in
      let interfaces = path.availableInterfaces
        .map { "\($0.type):\($0.name)" }
        .sorted()
        .joined(separator: ",")
      let fingerprint = "\(path.status)|\(interfaces)|\(path.isExpensive)|\(path.isConstrained)"
      Task {
        await self?.handleNetworkFingerprintChange(fingerprint)
      }
    }
    pathMonitor.start(queue: monitorQueue)
  }

  private func handleNetworkFingerprintChange(_ fingerprint: String) {
    guard !lastPathFingerprint.isEmpty else {
      lastPathFingerprint = fingerprint
      return
    }
    guard fingerprint != lastPathFingerprint else { return }
    lastPathFingerprint = fingerprint
    networkEpoch += 1
    probeCache.removeAll()
    failedRouteUntil.removeAll()
  }

  /// 将起播失败的直连路由记入 60 秒短时负缓存。
  func markRouteFailed(server: String?, url: String) {
    let key = routeFailureKey(server: server, url: url)
    failedRouteUntil[key] = Date().addingTimeInterval(negativeCacheTTL)
  }

  /// 并发探测可用直连候选并生成主路由与有序降级队列。
  func resolve(
    server: String?,
    routes: [PlaybackRouteCandidate],
    preferStrmDirect: Bool,
    preferServerDirect: Bool
  ) async -> PlaybackRoutePlan? {
    let prefs = PlaybackRoutePreference(
      preferStrmDirect: preferStrmDirect,
      preferServerDirect: preferServerDirect
    )
    let now = Date()
    var probes: [RouteProbeOutcome] = []
    var toProbe: [(probeURL: String, routeURL: String)] = []

    if preferServerDirect {
      for route in routes where route.kind == .serverLan || route.kind == .serverWan {
        let failKey = routeFailureKey(server: server, url: route.url)
        if let blockedUntil = failedRouteUntil[failKey], blockedUntil > now {
          let targetKey = route.probeUrl ?? route.url
          probes.append(RouteProbeOutcome(url: targetKey, reachable: false, latencyMs: nil))
          continue
        }
        guard let probeURL = route.probeUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
          !probeURL.isEmpty,
          PlaybackRoutePlanner.isSafeHttpURL(probeURL)
        else { continue }
        let cKey = probeCacheKey(server: server, probeURL: probeURL)
        if let cached = probeCache[cKey], cached.expiresAt > now {
          probes.append(cached.outcome)
        } else if !toProbe.contains(where: { $0.probeURL == probeURL }) {
          toProbe.append((probeURL, route.url))
        }
      }
    }

    if !toProbe.isEmpty {
      let epochSnapshot = networkEpoch
      let freshOutcomes = await probeConcurrently(toProbe.map(\.probeURL))
      if epochSnapshot == networkEpoch {
        let expiry = Date().addingTimeInterval(probeTTL)
        for outcome in freshOutcomes {
          probeCache[probeCacheKey(server: server, probeURL: outcome.url)] = CachedProbe(
            outcome: outcome, expiresAt: expiry)
        }
      }
      probes.append(contentsOf: freshOutcomes)
    }

    return PlaybackRoutePlanner.plan(routes: routes, preferences: prefs, probes: probes)
  }

  /// 为即将送入 VLCKit 的单条路由执行安全预检：
  /// - `mp_proxy` / `strm_direct` 直接返回原始地址与安全头；
  /// - `server_lan` / `server_wan` 先携带 `route.headers` 执行无跟随 302 预检：
  ///   - 若遇到跨源 302（例如 Emby 302 跳转网盘 CDN），直接剥离全部媒体服务器凭据并返回干净直链；
  ///   - 若返回 401/403，写入负缓存并返回 `nil` 触发无缝降级；
  ///   - 若为同源直连流，再构造仅驻留内存的 libVLC 认证直连地址。
  func preparePlayableTarget(
    for route: PlaybackRouteCandidate,
    server: String?
  ) async -> PreparedPlaybackTarget? {
    guard let url = URL(string: route.url) else { return nil }
    guard route.kind == .serverLan || route.kind == .serverWan else {
      return PreparedPlaybackTarget(route: route, url: url, headers: route.headers)
    }
    if route.headers.isEmpty {
      return PreparedPlaybackTarget(route: route, url: url, headers: [:])
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
    for (name, value) in route.headers where !name.isEmpty && !value.isEmpty {
      request.setValue(value, forHTTPHeaderField: name)
    }

    do {
      let (_, response) = try await preflightSession.data(for: request)
      if let http = response as? HTTPURLResponse {
        if http.statusCode == 401 || http.statusCode == 403 {
          markRouteFailed(server: server, url: route.url)
          return nil
        }
        if (300..<400).contains(http.statusCode),
          let rawLocation = http.value(forHTTPHeaderField: "Location"),
          let resolvedLocation = URL(string: rawLocation, relativeTo: url)?.absoluteURL,
          PlaybackRoutePlanner.isSafeHttpURL(resolvedLocation.absoluteString)
        {
          if !PlaybackRoutePlanner.isSameHttpOrigin(route.url, resolvedLocation.absoluteString) {
            // 跨源 302（如网盘 CDN）：彻底剥离媒体服务器个人令牌头，直接交由 VLCKit 满速直连。
            return PreparedPlaybackTarget(route: route, url: resolvedLocation, headers: [:])
          }
          let authedRedirect = PlaybackRoutePlanner.buildVlcDirectURL(
            url: resolvedLocation, headers: route.headers)
          return PreparedPlaybackTarget(route: route, url: authedRedirect, headers: [:])
        }
      }
    } catch {
      // 网络瞬间超时或 TLS 失败：标记负缓存并立即降级，避免 VLCKit 长时间卡顿。
      markRouteFailed(server: server, url: route.url)
      return nil
    }

    let authedDirect = PlaybackRoutePlanner.buildVlcDirectURL(url: url, headers: route.headers)
    return PreparedPlaybackTarget(route: route, url: authedDirect, headers: [:])
  }

  private func probeConcurrently(_ urls: [String]) async -> [RouteProbeOutcome] {
    let session = probeSession
    return await withTaskGroup(of: RouteProbeOutcome.self) { group in
      for rawURL in urls {
        group.addTask {
          await Self.probeSingle(rawURL: rawURL, session: session)
        }
      }
      var results: [RouteProbeOutcome] = []
      for await outcome in group {
        results.append(outcome)
      }
      return results
    }
  }

  private nonisolated static func probeSingle(
    rawURL: String,
    session: URLSession
  ) async -> RouteProbeOutcome {
    guard let url = URL(string: rawURL) else {
      return RouteProbeOutcome(url: rawURL, reachable: false, latencyMs: nil)
    }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    let startedAt = ContinuousClock.now
    do {
      let (_, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse, (200..<500).contains(http.statusCode),
        http.statusCode != 404
      else {
        return RouteProbeOutcome(url: rawURL, reachable: false, latencyMs: nil)
      }
      let elapsed = startedAt.duration(to: .now)
      let ms = Int(elapsed.components.seconds * 1_000)
        + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
      return RouteProbeOutcome(url: rawURL, reachable: true, latencyMs: max(1, ms))
    } catch {
      return RouteProbeOutcome(url: rawURL, reachable: false, latencyMs: nil)
    }
  }

  private func probeCacheKey(server: String?, probeURL: String) -> String {
    "\(server ?? "")|\(networkEpoch)|\(probeURL)"
  }

  private func routeFailureKey(server: String?, url: String) -> String {
    "\(server ?? "")|\(networkEpoch)|\(url)"
  }
}
