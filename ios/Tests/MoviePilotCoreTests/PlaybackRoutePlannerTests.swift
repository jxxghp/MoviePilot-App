import Foundation
import Testing

@testable import MoviePilotCore

struct PlaybackRoutePlannerTests {
  private func sampleRoutes() -> [PlaybackRouteCandidate] {
    [
      PlaybackRouteCandidate(
        kind: .strmDirect,
        url: "https://cdn.example.com/movie.mkv",
        priority: 10
      ),
      PlaybackRouteCandidate(
        kind: .serverLan,
        url: "http://192.168.1.10:8096/emby/Videos/1/stream?Static=true",
        probeUrl: "http://192.168.1.10:8096/emby/System/Ping",
        headers: ["X-Emby-Token": "tok-1"],
        priority: 20
      ),
      PlaybackRouteCandidate(
        kind: .serverWan,
        url: "https://emby.example.com/emby/Videos/1/stream?Static=true",
        probeUrl: "https://emby.example.com/emby/System/Ping",
        headers: ["X-Emby-Token": "tok-1"],
        priority: 30
      ),
      PlaybackRouteCandidate(
        kind: .mpProxy,
        url: "https://mp.example.com/api/v1/mediaserver/stream?itemid=1",
        priority: 100,
        requiresSameOriginAuth: true
      ),
    ]
  }

  @Test func strmPriorityAndOrderedFallbackChain() {
    let probes = [
      RouteProbeOutcome(
        url: "http://192.168.1.10:8096/emby/System/Ping", reachable: true, latencyMs: 18),
      RouteProbeOutcome(
        url: "https://emby.example.com/emby/System/Ping", reachable: true, latencyMs: 65),
    ]
    let plan = PlaybackRoutePlanner.plan(routes: sampleRoutes(), probes: probes)
    #expect(plan?.active.kind == .strmDirect)
    #expect(plan?.routeLabelKey == "STRM 直链")
    #expect(plan?.fallbacks.map(\.kind) == [.serverLan, .serverWan, .mpProxy])
  }

  @Test func lanPreferredWithinLatencyThreshold() {
    let routes = sampleRoutes().filter { $0.kind != .strmDirect }
    let probes = [
      RouteProbeOutcome(
        url: "http://192.168.1.10:8096/emby/System/Ping", reachable: true, latencyMs: 140),
      RouteProbeOutcome(
        url: "https://emby.example.com/emby/System/Ping", reachable: true, latencyMs: 40),
    ]
    let plan = PlaybackRoutePlanner.plan(routes: routes, probes: probes)
    #expect(plan?.active.kind == .serverLan)
    #expect(plan?.routeLabelKey == "局域网直连")
    #expect(plan?.fallbacks.map(\.kind) == [.serverWan, .mpProxy])
  }

  @Test func wanWinsWhenLanExceedsThresholdOrUnreachable() {
    let routes = sampleRoutes().filter { $0.kind != .strmDirect }
    let probes = [
      RouteProbeOutcome(
        url: "http://192.168.1.10:8096/emby/System/Ping", reachable: true, latencyMs: 520),
      RouteProbeOutcome(
        url: "https://emby.example.com/emby/System/Ping", reachable: true, latencyMs: 60),
    ]
    let plan = PlaybackRoutePlanner.plan(routes: routes, probes: probes)
    #expect(plan?.active.kind == .serverWan)
    #expect(plan?.routeLabelKey == "外网直连")
    #expect(plan?.fallbacks.map(\.kind) == [.serverLan, .mpProxy])
  }

  @Test func fallsBackToProxyWhenDirectDisabledOrUnreachable() {
    let routes = sampleRoutes()
    let disabled = PlaybackRoutePreference(preferStrmDirect: false, preferServerDirect: false)
    let probes = [
      RouteProbeOutcome(
        url: "http://192.168.1.10:8096/emby/System/Ping", reachable: true, latencyMs: 10)
    ]
    let plan = PlaybackRoutePlanner.plan(routes: routes, preferences: disabled, probes: probes)
    #expect(plan?.active.kind == .mpProxy)
    #expect(plan?.routeLabelKey == "后台中转")
    #expect(plan?.fallbacks.isEmpty == true)
  }

  @Test func sameOriginAndEphemeralVlcDirectURL() {
    #expect(
      PlaybackRoutePlanner.isSameHttpOrigin(
        "https://EMBY.example.com:443/emby/Videos/1/stream",
        "https://emby.example.com/emby/System/Ping"
      ))
    #expect(
      !PlaybackRoutePlanner.isSameHttpOrigin(
        "https://emby.example.com/emby/Videos/1/stream",
        "https://cdn.115.com/video.mkv"
      ))
    let embyURL = URL(string: "http://192.168.1.10:8096/emby/Videos/1/stream?Static=true")!
    let authedEmby = PlaybackRoutePlanner.buildVlcDirectURL(
      url: embyURL, headers: ["X-Emby-Token": "user-tok-1"])
    #expect(authedEmby.absoluteString.contains("api_key=user-tok-1"))

    let plexURL = URL(string: "http://192.168.1.20:32400/library/parts/1/file.mkv")!
    let authedPlex = PlaybackRoutePlanner.buildVlcDirectURL(
      url: plexURL, headers: ["X-Plex-Token": "plex-tok-2"])
    #expect(authedPlex.absoluteString.contains("X-Plex-Token=plex-tok-2"))
  }
}
