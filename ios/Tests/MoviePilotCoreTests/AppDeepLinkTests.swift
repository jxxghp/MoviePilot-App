import Foundation
import MoviePilotCore
import Testing

/// 验证 `moviepilot://` 深度链接、本地音视频文件解析与安全白名单边界。
struct AppDeepLinkTests {

  @Test func playableMediaFormatDistinguishesAudioVideoAndUnsupported() {
    #expect(PlayableMediaFormat.kind(forExtension: "mkv") == .video)
    #expect(PlayableMediaFormat.kind(forExtension: ".MP4") == .video)
    #expect(PlayableMediaFormat.kind(forExtension: "m2ts") == .video)
    #expect(PlayableMediaFormat.kind(forExtension: "rmvb") == .video)
    #expect(PlayableMediaFormat.kind(forExtension: "flac") == .audio)
    #expect(PlayableMediaFormat.kind(forExtension: ".OPUS") == .audio)
    #expect(PlayableMediaFormat.kind(forExtension: "mka") == .audio)
    #expect(PlayableMediaFormat.kind(forExtension: "m3u8") == nil)
    #expect(PlayableMediaFormat.kind(forExtension: "m3u8", includeStreaming: true) == .video)
    #expect(PlayableMediaFormat.kind(forExtension: "pdf") == nil)
    #expect(PlayableMediaFormat.kind(forExtension: "") == nil)
    #expect(PlayableMediaFormat.isPlayableExtension("mkv"))
    #expect(PlayableMediaFormat.isAudioExtension("mp3"))
    #expect(!PlayableMediaFormat.isAudioExtension("mp4"))
    #expect(PlayableMediaFormat.isVideoExtension("webm"))
  }

  @Test func parsesHostStyleAndTripleSlashRoutes() {
    #expect(AppDeepLink(url: URL(string: "moviepilot://")!) == .discover)
    #expect(AppDeepLink(url: URL(string: "moviepilot:///")!) == .discover)
    #expect(AppDeepLink(url: URL(string: "moviepilot://discover")!) == .discover)
    #expect(AppDeepLink(url: URL(string: "moviepilot:///recommend")!) == .discover)
    #expect(AppDeepLink(url: URL(string: "moviepilot://explore")!) == .explore(source: nil))
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://explore/douban_movies")!)
        == .explore(source: "douban_movies"))
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://explore/douban/tv")!)
        == .explore(source: "douban_tvs"))
    #expect(
      AppDeepLink(url: URL(string: "moviepilot:///explore?source=bangumi")!)
        == .explore(source: "bangumi"))
    #expect(AppDeepLink(url: URL(string: "moviepilot://dashboard")!) == .dashboard)
    #expect(AppDeepLink(url: URL(string: "moviepilot://mine")!) == .dashboard)
    #expect(AppDeepLink(url: URL(string: "moviepilot://settings")!) == .settings)
    #expect(AppDeepLink(url: URL(string: "moviepilot:///setting")!) == .settings)
    #expect(AppDeepLink(url: URL(string: "moviepilot://calendar")!) == .calendar)
    #expect(AppDeepLink(url: URL(string: "moviepilot://downloading")!) == .downloads)
    #expect(AppDeepLink(url: URL(string: "moviepilot:///downloads")!) == .downloads)
    #expect(AppDeepLink(url: URL(string: "moviepilot://workflow")!) == .workflows)
    #expect(AppDeepLink(url: URL(string: "moviepilot://sites")!) == .sites)
    #expect(AppDeepLink(url: URL(string: "moviepilot://messages")!) == .messages)
    #expect(AppDeepLink(url: URL(string: "moviepilot://music")!) == .music)
    #expect(AppDeepLink(url: URL(string: "moviepilot://shortcuts")!) == .shortcuts)
    #expect(AppDeepLink(url: URL(string: "moviepilot://users")!) == .users)
    #expect(AppDeepLink(url: URL(string: "moviepilot://appearance")!) == .appearance)
  }

  @Test func parsesSearchSubscriptionsResourcesAndWorkspaceParameters() {
    let encodedSearch =
      "moviepilot://search?q=\("阿凡达".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)&type=library"
    #expect(
      AppDeepLink(url: URL(string: encodedSearch)!) == .search(query: "阿凡达", kind: "library"))
    #expect(
      AppDeepLink(url: URL(string: "moviepilot:///media-library/search?keyword=Dune")!)
        == .search(query: "Dune", kind: "library"))
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://search/Inception")!)
        == .search(query: "Inception", kind: nil))

    #expect(
      AppDeepLink(url: URL(string: "moviepilot://subscribe")!) == .subscriptions(category: nil))
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://subscribe?type=all")!)
        == .subscriptions(category: nil))
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://subscribe/movie")!)
        == .subscriptions(category: "movie"))
    #expect(
      AppDeepLink(url: URL(string: "moviepilot:///subscribe/tv")!)
        == .subscriptions(category: "tv"))
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://subscribe/music")!)
        == .subscriptions(category: "music"))
    #expect(AppDeepLink(url: URL(string: "moviepilot://subscribe/popular")!) == .subscribeCommunity)
    #expect(AppDeepLink(url: URL(string: "moviepilot:///subscribe-share")!) == .subscribeCommunity)

    #expect(
      AppDeepLink(url: URL(string: "moviepilot://resource")!)
        == .resources(keyword: nil, browseHome: false))
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://resource/browse")!)
        == .resources(keyword: nil, browseHome: true))
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://resource?keyword=Oppenheimer")!)
        == .resources(keyword: "Oppenheimer", browseHome: false))

    #expect(
      AppDeepLink(url: URL(string: "moviepilot://files?storage=local&path=/media/movies")!)
        == .files(storage: "local", path: "/media/movies"))
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://history?search=Dune")!)
        == .history(search: "Dune"))
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://plugins")!) == .plugins(installedOnly: false))
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://plugins/installed")!)
        == .plugins(installedOnly: true))
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://agent?prompt=hello")!) == .agent(prompt: "hello"))
  }

  @Test func parsesMediaDetailSettingsAndDiagnosticsRoutes() {
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://media/tmdb/550?type=movie")!)
        == .mediaDetail(source: "themoviedb", mediaID: "550", mediaType: "电影"))
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://media/douban/1292052/tv")!)
        == .mediaDetail(source: "douban", mediaID: "1292052", mediaType: "电视剧"))
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://media/bangumi/400602")!)
        == .mediaDetail(source: "bangumi", mediaID: "400602", mediaType: "电视剧"))
    #expect(
      AppDeepLink(route: "/media?mediaid=tmdb:550&type=电影")
        == .mediaDetail(source: "themoviedb", mediaID: "550", mediaType: "电影"))
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://media/tmdb:1399?type=tv")!)
        == .mediaDetail(source: "themoviedb", mediaID: "1399", mediaType: "电视剧"))

    #expect(AppDeepLink(url: URL(string: "moviepilot://settings/system")!) == .systemSettings)
    #expect(AppDeepLink(url: URL(string: "moviepilot://settings/playback")!) == .playbackSettings)
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://settings/downloaders")!) == .downloadersManage)
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://settings/mediaservers")!) == .mediaServersManage)
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://settings/directories")!)
        == .systemModule("directories"))
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://settings/notifications")!)
        == .systemModule("notifications"))
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://diagnostics/words")!) == .diagnostics("words"))
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://diagnostics/logs")!) == .diagnostics("live_log"))
    #expect(AppDeepLink(url: URL(string: "moviepilot://words")!) == .diagnostics("words"))
    #expect(AppDeepLink(url: URL(string: "moviepilot://logs")!) == .diagnostics("live_log"))
  }

  @Test func parsesOpenPathWrapperIncludingUnicodeQueries() {
    let inner = "/search?q=阿凡达&type=media"
    let encodedInner = inner.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://open?path=\(encodedInner)")!)
        == .search(query: "阿凡达", kind: "media"))

    #expect(
      AppDeepLink(url: URL(string: "moviepilot://open?path=/subscribe/tv")!)
        == .subscriptions(category: "tv"))
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://route?route=downloading")!) == .downloads)
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://open?path=/resource&keyword=Dune")!)
        == .resources(keyword: "Dune", browseHome: false))
  }

  @Test func parsesPlayLinksAndLocalMediaFiles() {
    let streamURL = URL(string: "https://media.example.com/movie.mkv")!
    let encodedStream =
      streamURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
    let externalLink = AppDeepLink(
      url: URL(string: "moviepilot://play?url=\(encodedStream)&title=Sample")!)
    #expect(externalLink == .playExternalURL(url: streamURL, title: "Sample", kind: .video))
    #expect(externalLink?.requiresSession == false)

    let audioStream = URL(string: "https://media.example.com/track.flac")!
    let encodedAudio =
      audioStream.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://play?url=\(encodedAudio)")!)
        == .playExternalURL(url: audioStream, title: nil, kind: .audio))

    let forcedAudio = URL(string: "https://media.example.com/live/stream")!
    let encodedLive =
      forcedAudio.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://play?url=\(encodedLive)&type=audio")!)
        == .playExternalURL(url: forcedAudio, title: nil, kind: .audio))

    let serverPlay = AppDeepLink(
      url: URL(string: "moviepilot://play?itemid=emby_1001&server=Emby&title=Movie")!)
    #expect(serverPlay == .playMediaServerItem(itemID: "emby_1001", server: "Emby", title: "Movie"))
    #expect(serverPlay?.requiresSession == true)

    let storagePlay = AppDeepLink(
      url: URL(string: "moviepilot://play?storage=local&path=/media/demo.mp4")!)
    #expect(
      storagePlay
        == .playStorageFile(storage: "local", path: "/media/demo.mp4", fileName: "demo.mp4"))
    #expect(storagePlay?.requiresSession == true)

    let localVideo = URL(fileURLWithPath: "/Users/demo/Movies/BladeRunner.mkv")
    #expect(
      AppDeepLink(url: localVideo)
        == .playLocalFile(url: localVideo, title: "BladeRunner", kind: .video))

    let localAudio = URL(fileURLWithPath: "/Users/demo/Music/Track01.flac")
    #expect(
      AppDeepLink(url: localAudio)
        == .playLocalFile(url: localAudio, title: "Track01", kind: .audio))

    let unknownExt = URL(fileURLWithPath: "/Users/demo/Files/stream_blob")
    #expect(AppDeepLink(url: unknownExt) == nil)
    #expect(
      AppDeepLink(url: unknownExt, fallbackLocalMediaKind: .video)
        == .playLocalFile(url: unknownExt, title: "stream_blob", kind: .video))
  }

  @Test func rejectsReservedSchemesUnsafePayloadsAndNotificationPlayback() {
    // 保留的小组件与 Passkey 链接不能被通用深链误消费。
    let widgetURL = URL(
      string: "moviepilot://widget?profile=11111111-2222-3333-4444-555555555555&content=downloads")!
    #expect(AppDeepLink(url: widgetURL) == nil)
    #expect(AppDeepLink(url: URL(string: "moviepilot://passkey/callback#result=abc")!) == nil)
    #expect(
      AppDeepLink(
        url: URL(string: "moviepilot-app://notification?origin=https://a&route=/a&owner=1")!) == nil
    )
    #expect(AppDeepLink(url: URL(string: "https://example.com/subscribe")!) == nil)

    // 拒绝非 http(s) 的播放直链（防止本地文件探测或脚本注入）与重复参数。
    #expect(AppDeepLink(url: URL(string: "moviepilot://play?url=file:///etc/passwd")!) == nil)
    #expect(AppDeepLink(url: URL(string: "moviepilot://play?url=javascript:alert(1)")!) == nil)
    #expect(
      AppDeepLink(
        url: URL(
          string: "moviepilot://play?url=https://a.example/1.mp4&url=https://b.example/2.mp4")!)
        == nil)
    #expect(AppDeepLink(url: URL(string: "moviepilot://play")!) == nil)

    // 拒绝凭据、端口、片段、目录穿越与不支持文件格式。
    #expect(AppDeepLink(url: URL(string: "moviepilot://user@subscribe")!) == nil)
    #expect(AppDeepLink(url: URL(string: "moviepilot://subscribe:8080")!) == nil)
    #expect(AppDeepLink(url: URL(string: "moviepilot://subscribe#section")!) == nil)
    #expect(AppDeepLink(url: URL(string: "moviepilot://files?path=/media/../etc/passwd")!) == nil)
    #expect(AppDeepLink(url: URL(string: "moviepilot://open?path=//evil.example/x")!) == nil)
    #expect(AppDeepLink(url: URL(string: "moviepilot://open?path=https://evil.example/x")!) == nil)
    #expect(AppDeepLink(url: URL(string: "moviepilot://unknown/feature")!) == nil)
    #expect(AppDeepLink(url: URL(fileURLWithPath: "/Users/demo/Documents/notes.pdf")) == nil)

    // 通知内部路由兼容 APNs `/?shotcut=message` 与 Vue Hash 写法，且严禁解析出任何播放指令。
    #expect(AppDeepLink(route: "/?shotcut=message") == .messages)
    #expect(AppDeepLink(route: "/?shortcut=messages") == .messages)
    #expect(AppDeepLink(route: "/#/?shotcut=message") == .messages)
    #expect(AppDeepLink(route: "/#/history?search=S01") == .history(search: "S01"))
    #expect(AppDeepLink(route: "/#/site") == .sites)
    #expect(
      AppDeepLink(url: URL(string: "moviepilot://open?path=%2F%3Fshotcut%3Dmessage")!) == .messages)
    #expect(AppDeepLink(route: "/?shotcut=recognition") == .diagnostics("rule_test"))
    #expect(AppDeepLink(route: "/?shotcut=unknown") == nil)
    #expect(AppDeepLink(route: "/subscribe/movie") == .subscriptions(category: "movie"))
    #expect(AppDeepLink(route: "/play?url=https://media.example.com/a.mp4") == nil)
    #expect(AppDeepLink(route: "/play?itemid=123") == nil)
    #expect(AppDeepLink(route: "//evil.example/subscribe") == nil)
  }

  @Test func pendingDeepLinkHonorsTTLAndInstanceIsolation() {
    var pending = PendingAppDeepLink()
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    pending.receive(.subscriptions(category: "tv"), instanceID: "inst-a", now: now)
    #expect(
      pending.resolve(for: "inst-a", now: now.addingTimeInterval(60))
        == .subscriptions(category: "tv"))

    // 切换至其他实例时立即作废，防止跨实例迟到重放。
    #expect(pending.resolve(for: "inst-b", now: now.addingTimeInterval(61)) == nil)
    #expect(pending.resolve(for: "inst-a", now: now.addingTimeInterval(62)) == nil)

    // 超过 5 分钟自动过期。
    pending.receive(.downloads, instanceID: nil, now: now)
    #expect(pending.resolve(for: "inst-a", now: now.addingTimeInterval(301)) == nil)
  }

  @Test func strmExtensionAndDirectLinkParserHandlesCloudAndLocalStrm() {
    #expect(PlayableMediaFormat.isPlayableExtension("strm"))
    #expect(PlayableMediaFormat.isStrmExtension(".STRM"))
    #expect(PlayableMediaFormat.kind(forPath: "/media/Movies/Avatar.strm") == .video)
    #expect(PlayableMediaFormat.kind(forPath: "/media/Music/晴天.flac.strm") == .audio)

    let localStrmURL = URL(fileURLWithPath: "/Users/test/Downloads/阿凡达.strm")
    #expect(
      AppDeepLink(url: localStrmURL)
        == .playLocalFile(url: localStrmURL, title: "阿凡达", kind: .video))

    let rawStrm = """
      \u{feff}#EXTM3U
      #EXTVLCOPT:http-user-agent=Mozilla/5.0 (115Browser)
      #EXTVLCOPT:http-referrer=https://115.com/
      https://openlist.example.test:5244/d/电影/阿凡达 [4K]/Avatar 100% Pure.mkv?sign=abc%2B1
      """
    let spec = PlayableMediaFormat.parseStrmContent(rawStrm, fallbackFileName: "Avatar.strm")
    #expect(spec != nil)
    #expect(
      spec?.url.absoluteString
        == "https://openlist.example.test:5244/d/%E7%94%B5%E5%BD%B1/%E9%98%BF%E5%87%A1%E8%BE%BE%20%5B4K%5D/Avatar%20100%25%20Pure.mkv?sign=abc%2B1"
    )
    #expect(spec?.kind == .video)
    #expect(spec?.headers["User-Agent"] == "Mozilla/5.0 (115Browser)")
    #expect(spec?.headers["Referer"] == "https://115.com/")

    let pipeAudio =
      "http://192.168.1.20:5244/d/Music/Track 01.flac|User-Agent=Kodi%2F21.0&Cookie=sid%3Dxyz"
    let audioSpec = PlayableMediaFormat.parseStrmContent(pipeAudio, fallbackFileName: "Track.strm")
    #expect(audioSpec?.url.absoluteString == "http://192.168.1.20:5244/d/Music/Track%2001.flac")
    #expect(audioSpec?.kind == .audio)
    #expect(audioSpec?.headers["User-Agent"] == "Kodi/21.0")
    #expect(audioSpec?.headers["Cookie"] == "sid=xyz")

    #expect(PlayableMediaFormat.parseStrmContent("file:///etc/passwd") == nil)
    #expect(PlayableMediaFormat.parseStrmContent("http://user:pass@192.168.1.1/a.mp4") == nil)
  }
}
