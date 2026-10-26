import XCTest

/// 隔离网络夹具只提供测试地址，不包含真实实例账号或凭据。
private struct NetworkFixtures: Decodable {
  let servers: [String]
  let untrustedCertificate: String
  let unavailable: String
  let timedOut: String
  let unsupportedScopedIPv6: String
}

/// 使用显式配置的测试实例验收原生框架与原业务 HTML 的真实交接，不写入业务数据。
@MainActor
final class NativeFrameworkTests: XCTestCase {
  /// 新容器在实际WKWebView中复用榜单，过期失败仍可重试，恢复前台不沿用旧快照。
  func testNativeReadonlyListCache() async throws {
    guard ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_READONLY_CACHE"] == "1",
      let base = URL(string: "http://127.0.0.1:5245")
    else { throw XCTSkip("需要独立本机只读缓存夹具。") }
    continueAfterFailure = false
    try await configureReadonlyCache(base, value: ["reset": true])
    let app = launchConnection(server: base.absoluteString, captureScreens: false)
    let authenticatedOrForm = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        app.textFields["用户名"].exists || app.tabBars["native-root-navigation"].exists
      }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [authenticatedOrForm], timeout: 30), .completed)
    if app.textFields["用户名"].exists { authenticateFixture(app, remember: false) }
    XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 30))
    app.tabBars["native-root-navigation"].buttons["推荐"].tap()
    var state = try await readonlyCacheState(
      base, path: "/recommend", firstPages: 1, hasCards: true)
    let ui = try XCTUnwrap(state["ui"] as? [String: Any])
    XCTAssertEqual(ui["cacheVersion"] as? Int, 1)
    XCTAssertEqual(ui["cacheNegotiated"] as? Bool, true)
    let all = app.webViews.links["更多"].firstMatch
    XCTAssertTrue(all.waitForExistence(timeout: 10), app.debugDescription)
    all.tap()
    state = try await readonlyCacheState(
      base, path: "/browse/recommend/tmdb_trending", firstPages: 1, hasCards: true)
    try await configureReadonlyCache(
      base,
      value: [
        "mode": "offline", "navigate": "/browse/recommend/tmdb_trending?title=OfflineSnapshot",
      ])
    state = try await readonlyCacheState(
      base, path: "title=OfflineSnapshot", firstPages: 1, hasCards: true)
    try await configureReadonlyCache(
      base,
      value: [
        "clockOffset": 61000, "navigate": "/browse/recommend/tmdb_trending?title=ExpiredSnapshot",
      ])
    let retry = app.webViews.buttons["重试"].firstMatch
    XCTAssertTrue(retry.waitForExistence(timeout: 15), app.debugDescription)
    state = try await readonlyCacheState(base, path: "title=ExpiredSnapshot", firstPages: 2)
    try await configureReadonlyCache(base, value: ["mode": "healthy"])
    retry.tap()
    state = try await readonlyCacheState(
      base, path: "title=ExpiredSnapshot", firstPages: 3, hasCards: true)
    try await configureReadonlyCache(
      base, value: ["navigate": "/browse/recommend/tmdb_trending?title=RecoveredSnapshot"])
    state = try await readonlyCacheState(
      base, path: "title=RecoveredSnapshot", firstPages: 3, hasCards: true)
    XCUIDevice.shared.press(.home)
    app.activate()
    XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 10))
    try await configureReadonlyCache(
      base, value: ["navigate": "/browse/recommend/tmdb_trending?title=ForegroundSnapshot"])
    state = try await readonlyCacheState(
      base, path: "title=ForegroundSnapshot", firstPages: 4, hasCards: true)
    let requests = try XCTUnwrap(state["requests"] as? [[String: Any]])
    for request in requests where request["page"] as? Int == 1 {
      XCTAssertEqual(request["native"] as? String, "1")
      XCTAssertEqual(request["cacheControl"] as? String, "no-store")
    }
    XCTAssertEqual(state["documents"] as? Int, 1)
    app.tabBars["native-root-navigation"].buttons["更多"].tap()
    XCTAssertTrue(app.tables["more-menu"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts["暂时无法打开 MoviePilot"].exists)
    let attachment = XCTAttachment(
      data: try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]),
      uniformTypeIdentifier: "public.json")
    attachment.name = "原生只读缓存请求与生命周期"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// 故障、时钟及唯一分页路由只发往白名单本机夹具，不存在产品调试入口。
  private func configureReadonlyCache(_ base: URL, value: [String: Any]) async throws {
    var request = URLRequest(url: base.appendingPathComponent("__fixture/config"))
    request.httpMethod = "POST"
    request.httpBody = try JSONSerialization.data(withJSONObject: value)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let (_, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
  }

  /// 等待真实DOM和HTTP计数同时达到当前阶段，避免只根据导航标题判断缓存已命中。
  private func readonlyCacheState(
    _ base: URL, path: String, firstPages: Int, hasCards: Bool = false
  ) async throws -> [String: Any] {
    var last: [String: Any] = [:]
    for _ in 0..<100 {
      let (body, _) = try await URLSession.shared.data(
        from: base.appendingPathComponent("__fixture/stats"))
      if let value = try JSONSerialization.jsonObject(with: body) as? [String: Any],
        let ui = value["ui"] as? [String: Any],
        let requests = value["requests"] as? [[String: Any]]
      {
        last = value
        if (ui["path"] as? String)?.contains(path) == true,
          requests.filter({ $0["page"] as? Int == 1 }).count == firstPages,
          !hasCards || (ui["cards"] as? Int ?? 0) > 0
        {
          return value
        }
      }
      try await Task.sleep(for: .milliseconds(100))
    }
    XCTFail("只读缓存未达到\(path)，实际阶段：\(last)")
    return last
  }

  /// 延迟初始化和令牌校验期间仅显示启动屏，成功恢复直接进入首页，过期后才出现登录。
  func testNativeStartupWaitsForAuthentication() async throws {
    guard ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_STARTUP"] == "1",
      let base = URL(string: "http://127.0.0.1:5242")
    else { throw XCTSkip("需要独立本机启动及认证恢复夹具。") }
    try await configureStartupFixture(base, mode: "initial")
    let app = launchConnection(server: base.absoluteString, captureScreens: false)
    for mode in ["initial", "valid", "expired"] {
      if mode != "initial" {
        try await configureStartupFixture(base, mode: mode)
        relaunchSavedLoginInstance(app)
      }
      XCTAssertTrue(app.otherElements["native-startup-screen"].waitForExistence(timeout: 5))
      XCTAssertFalse(app.textFields["用户名"].isHittable)
      XCTAssertFalse(app.navigationBars["登录"].exists)
      if mode == "valid" {
        XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 35))
        XCTAssertFalse(app.textFields["用户名"].exists)
      } else {
        XCTAssertTrue(app.textFields["用户名"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.otherElements["native-startup-screen"].exists)
        XCTAssertTrue(app.navigationBars["登录"].exists)
        if mode == "initial" {
          authenticateFixture(app)
          XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 35))
        }
      }
    }
  }

  /// 控制端点只改变本机合成响应的延迟与401状态，不向产品注入认证状态。
  private func configureStartupFixture(_ base: URL, mode: String) async throws {
    var request = URLRequest(url: base.appendingPathComponent("__startup/config"))
    request.httpMethod = "POST"
    request.httpBody = try JSONSerialization.data(withJSONObject: ["mode": mode])
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let (_, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
  }

  /// 原助手 HTML 在系统 Sheet 中保留收件图片、音频控件、文件分享及系统选取/录音入口。
  func testNativeAgentMedia() async throws {
    guard ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_AGENT_MEDIA"] == "1",
      let base = URL(string: "http://127.0.0.1:5241")
    else { throw XCTSkip("需要独立本机助手附件夹具与专用模拟器。") }
    let app = launchConnection(server: base.absoluteString, captureScreens: false)
    // 已签名模拟器会真实恢复 Keychain，会话有效时直接使用首页，避免强求重复登录。
    let authenticatedOrForm = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        app.textFields["用户名"].exists || app.tabBars["native-root-navigation"].exists
      }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [authenticatedOrForm], timeout: 30), .completed)
    if app.textFields["用户名"].exists { authenticateFixture(app, remember: false) }
    XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 30))
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"),
      object: app.otherElements["native-startup-screen"])
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 45), .completed, app.debugDescription)
    app.tabBars["native-root-navigation"].buttons["仪表盘"].tap()
    let trigger = app.webViews.buttons.matching(
      NSPredicate(format: "label == %@ OR label == %@", "奶龙", "智能助手")
    ).firstMatch
    XCTAssertTrue(trigger.waitForExistence(timeout: 10), app.debugDescription)
    trigger.tap()
    XCTAssertTrue(app.buttons["native-sheet-close"].waitForExistence(timeout: 10))
    let image = app.webViews.images["agent-image.png"].firstMatch
    XCTAssertTrue(image.waitForExistence(timeout: 10), app.debugDescription)
    image.tap()
    let audio = app.webViews.buttons["播放"].firstMatch
    XCTAssertTrue(audio.waitForExistence(timeout: 10), app.debugDescription)
    audio.tap()
    var state = try await agentMediaState(base, waitingFor: "played")
    XCTAssertGreaterThan(state["images"] as? Int ?? 0, 0)
    XCTAssertGreaterThan(state["played"] as? Int ?? 0, 0)
    let download = try XCTUnwrap(
      app.webViews.links.matching(identifier: "下载").allElementsBoundByIndex.last)
    XCTAssertTrue(download.waitForExistence(timeout: 8), app.debugDescription)
    download.tap()
    let activity = app.otherElements["ActivityListView"]
    XCTAssertTrue(activity.waitForExistence(timeout: 15))
    state = try await agentMediaState(base)
    XCTAssertEqual(state["fileMatches"] as? Bool, true)
    activity.cells.matching(NSPredicate(format: "label == %@", "拷贝")).firstMatch.tap()
    let attach = app.webViews.buttons["选择图片或文件"].firstMatch
    XCTAssertTrue(attach.waitForExistence(timeout: 8))
    attach.tap()
    XCTAssertTrue(app.buttons["选取文件"].waitForExistence(timeout: 8), app.debugDescription)
    app.buttons["选取文件"].tap()
    let cancel = app.buttons["取消"].firstMatch
    XCTAssertTrue(cancel.waitForExistence(timeout: 8))
    cancel.tap()
    XCTAssertTrue(attach.waitForExistence(timeout: 8))
    let record = app.webViews.buttons["录制语音"].firstMatch
    XCTAssertTrue(record.waitForExistence(timeout: 8))
    record.tap()
    if app.alerts.firstMatch.waitForExistence(timeout: 3) {
      let allow = app.alerts.buttons.matching(
        NSPredicate(format: "label == %@ OR label == %@ OR label == %@", "允许", "好", "Allow")
      ).firstMatch
      XCTAssertTrue(allow.exists, app.debugDescription)
      allow.tap()
    }
    let stop = app.webViews.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "停止录音"))
      .firstMatch
    XCTAssertTrue(stop.waitForExistence(timeout: 15), app.debugDescription)
    try await Task.sleep(for: .seconds(2))
    stop.tap()
    XCTAssertTrue(app.webViews.staticTexts["合成附件已接收"].firstMatch.waitForExistence(timeout: 15))
    state = try await agentMediaState(base)
    let uploads = try XCTUnwrap(state["uploads"] as? [[String: Any]])
    let recording = try XCTUnwrap(uploads.last)
    XCTAssertTrue((recording["mime"] as? String ?? "").hasPrefix("audio/"))
    XCTAssertGreaterThan(recording["size"] as? Int ?? 0, 0)
    let messages = try XCTUnwrap(state["messages"] as? [[String: Any]])
    XCTAssertEqual((messages.last?["audio_refs"] as? [String])?.count, 1)
    app.buttons["native-sheet-close"].tap()
    app.tabBars["native-root-navigation"].buttons["更多"].tap()
    XCTAssertTrue(app.tables["more-menu"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts["暂时无法打开 MoviePilot"].exists)
  }

  /// 控制夹具只回传合成附件字节校验及原 HTML 发出的媒体事件，不读取用户会话。
  private func agentMediaState(_ base: URL, waitingFor counter: String? = nil) async throws
    -> [String: Any]
  {
    var state: [String: Any] = [:]
    for _ in 0..<20 {
      let (data, _) = try await URLSession.shared.data(
        from: base.appendingPathComponent("__agent/state"))
      state = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
      if counter == nil || (state[counter!] as? Int ?? 0) > 0 { return state }
      try await Task.sleep(for: .milliseconds(250))
    }
    return state
  }

  /// 使用实际媒体详情菜单启动独立播放器夹具，返回后主文档与导航会话必须保留。
  func testNativeExternalPlayerKeepsDocument() async throws {
    let base = try await configureSystemLinks(["page": "player", "mode": "healthy", "reset": true])
    let app = try launchLogin(server: base.absoluteString, captureScreens: false)
    authenticateFixture(app, remember: false)
    XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 30))
    XCTAssertTrue(app.staticTexts["星际漫游"].firstMatch.waitForExistence(timeout: 15))
    app.buttons["操作菜单"].tap()
    let play = app.buttons["在线播放"].firstMatch
    XCTAssertTrue(play.waitForExistence(timeout: 10))
    play.tap()
    let receiver = XCUIApplication(bundleIdentifier: "org.moviepilot.fixture.player")
    let launched = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in receiver.state == .runningForeground }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [launched], timeout: 15), .completed)
    XCTAssertTrue(receiver.staticTexts["emby://items?serverId=server-456&itemId=item-123"].exists)
    app.activate()
    XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 10))
    app.tabBars["native-root-navigation"].buttons["更多"].tap()
    XCTAssertTrue(app.tables["more-menu"].waitForExistence(timeout: 10))
    let state = try await systemLinksState(base)
    XCTAssertEqual(state["documents"] as? Int, 1)
    XCTAssertEqual(state["sessions"] as? Int, 1)
    XCTAssertFalse(app.staticTexts["暂时无法打开 MoviePilot"].exists)
  }

  /// 下载真实日志和同源/跨源种子字节，系统分享关闭后原生弹窗与主导航继续响应。
  func testNativeFileDownloadsKeepDocument() async throws {
    let base = try await configureSystemLinks(["page": "apps", "mode": "healthy", "reset": true])
    let app = try launchLogin(server: base.absoluteString, captureScreens: false)
    authenticateFixture(app, remember: false)
    XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 30))
    app.buttons["操作菜单"].tap()
    app.buttons["捷径"].firstMatch.tap()
    let panel = app.tables["native-quick-panel"]
    XCTAssertTrue(panel.waitForExistence(timeout: 8))
    panel.buttons["native-panel-item-logging"].tap()
    XCTAssertTrue(app.buttons["native-sheet-menu"].waitForExistence(timeout: 10))
    app.buttons["native-sheet-menu"].tap()
    app.buttons["下载"].firstMatch.tap()
    try await verifySystemDownload("moviepilot.log", app: app, base: base)
    XCTAssertTrue(app.buttons["native-sheet-close"].isHittable)
    app.buttons["native-sheet-close"].tap()
    openMorePage("站点管理", app: app)
    let site = app.webViews.staticTexts["演示站点"].firstMatch
    XCTAssertTrue(site.waitForExistence(timeout: 15))
    site.tap()
    if !app.navigationBars["浏览"].waitForExistence(timeout: 2) { site.tap() }
    XCTAssertTrue(app.navigationBars["浏览"].waitForExistence(timeout: 10))
    for (index, filename) in ["demo.torrent", "remote.torrent"].enumerated() {
      let menu = app.webViews.otherElements.matching(identifier: "更多操作").element(boundBy: index)
      XCTAssertTrue(menu.waitForExistence(timeout: 10), app.debugDescription)
      // 卡片内图标在 WebKit 无障碍树中是容器，按其实际可见中心发送触摸。
      menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      try await tapTorrentDownload(app: app, base: base)
      try await verifySystemDownload(filename, app: app, base: base)
      XCTAssertTrue(app.navigationBars["浏览"].exists)
    }
    app.buttons["native-sheet-close"].tap()
    for title in ["推荐", "探索", "更多"] {
      app.tabBars["native-root-navigation"].buttons[title].tap()
      XCTAssertFalse(app.staticTexts["暂时无法打开 MoviePilot"].exists)
    }
    let state = try await systemLinksState(base)
    XCTAssertEqual(state["documents"] as? Int, 1)
    XCTAssertEqual(state["sessions"] as? Int, 1)
    let downloads = try XCTUnwrap(state["downloads"] as? [[String: Any]])
    XCTAssertEqual(downloads.count, 3)
    XCTAssertEqual(downloads.first?["cookie"] as? Bool, true)
    XCTAssertEqual(downloads.last?["cookie"] as? Bool, false)
  }

  /// 真正中断通知 SSE 并返回503，服务恢复后401交回原生登录，无须重新启动 App。
  func testBackendRestartReturnsToNativeLogin() async throws {
    let base = try await configureSystemLinks(["page": "apps", "mode": "healthy", "reset": true])
    let app = try launchLogin(server: base.absoluteString, captureScreens: false)
    authenticateFixture(app, remember: false)
    XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 30))
    try await Task.sleep(for: .seconds(4))
    _ = try await configureSystemLinks(["mode": "down"])
    try await Task.sleep(for: .seconds(3))
    XCTAssertFalse(app.navigationBars["登录"].exists)
    _ = try await configureSystemLinks(["mode": "expired"])
    XCTAssertTrue(app.navigationBars["登录"].waitForExistence(timeout: 20))
    XCTAssertEqual(app.state, .runningForeground)
    XCTAssertFalse(app.webViews.firstMatch.exists)
    let state = try await systemLinksState(base)
    XCTAssertTrue((state["pings"] as? [String] ?? []).contains("down"))
    _ = try await configureSystemLinks(["mode": "healthy"])
    authenticateFixture(app, remember: false)
    XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 30))
  }

  /// 系统深色使用低曝光壁纸，浅色立即停用图片；实际 UIKit 材质保持系统行为。
  func testNativeDimmedWallpaper() async throws {
    let base = try await configureSystemLinks([
      "page": "dashboard", "mode": "healthy", "reset": true, "appearance": "dark",
    ])
    let app = try launchLogin(server: base.absoluteString, captureScreens: false)
    authenticateFixture(app, remember: false)
    XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 30))
    for mode in ["dark", "light"] {
      _ = try await configureSystemLinks(["appearance": mode])
      XCTAssertTrue(app.webViews.staticTexts["存储空间"].waitForExistence(timeout: 15))
      settlePage(app)
      var visual: [String: Any] = [:]
      for _ in 0..<20 {
        visual = (try await systemLinksState(base))["visual"] as? [String: Any] ?? [:]
        if visual["scheme"] as? String == mode { break }
        try await Task.sleep(for: .milliseconds(250))
      }
      XCTAssertEqual(visual["scheme"] as? String, mode)
      let wallpapers = visual["wallpapers"] as? Int ?? -1
      if mode == "dark" {
        XCTAssertGreaterThan(wallpapers, 0)
      } else {
        XCTAssertEqual(wallpapers, 0)
        attachScreen("修复-浅色停用全局壁纸", app: app)
      }
    }
    _ = try await configureSystemLinks(["appearance": "dark"])
  }

  /// 控制仅限显式本机夹具，产品不增加测试桥接或绕过认证的分支。
  private func configureSystemLinks(_ value: [String: Any]) async throws -> URL {
    guard ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_SYSTEM_LINKS"] == "1",
      let base = URL(string: "http://127.0.0.1:5239")
    else { throw XCTSkip("需要独立本机系统链接夹具与播放器接收 App。") }
    var request = URLRequest(url: base.appendingPathComponent("__fixture/config"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: value)
    let (_, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    return base
  }

  /// 只读取合成文件校验和与文档/会话次数，不回传 App 数据或真实认证信息。
  private func systemLinksState(_ base: URL) async throws -> [String: Any] {
    let (data, _) = try await URLSession.shared.data(
      from: base.appendingPathComponent("__fixture/config"))
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  /// WebKit 可能从模态无障碍树排除 Teleport 菜单；隔离夹具只回传真实菜单的渲染坐标。
  private func tapTorrentDownload(app: XCUIApplication, base: URL) async throws {
    let option = app.webViews.descendants(matching: .any)
      .matching(identifier: "下载种子文件").firstMatch
    if option.waitForExistence(timeout: 2) {
      option.tap()
      return
    }
    let state = try await systemLinksState(base)
    let actions = try XCTUnwrap(state["menuActions"] as? [[String: Any]])
    let action = try XCTUnwrap(actions.first { $0["title"] as? String == "下载种子文件" })
    let x = try XCTUnwrap(action["x"] as? Double)
    let y = try XCTUnwrap(action["y"] as? Double)
    let width = try XCTUnwrap(action["width"] as? Double)
    let height = try XCTUnwrap(action["height"] as? Double)
    let viewport = app.otherElements["native-web-sheet"].webViews.firstMatch
    XCTAssertGreaterThan(width, 0)
    XCTAssertGreaterThan(height, 0)
    XCTAssertGreaterThanOrEqual(x, 0)
    XCTAssertGreaterThanOrEqual(y, 0)
    XCTAssertLessThanOrEqual(x + width, viewport.frame.width)
    XCTAssertLessThanOrEqual(y + height, viewport.frame.height)
    viewport.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: x + width / 2, dy: y + height / 2)).tap()
  }

  /// 系统分享面板出现时验证实际落盘字节，关闭后不应进入导航恢复页。
  private func verifySystemDownload(_ filename: String, app: XCUIApplication, base: URL)
    async throws
  {
    let activity = app.otherElements["ActivityListView"]
    XCTAssertTrue(activity.waitForExistence(timeout: 20), app.debugDescription)
    let state = try await systemLinksState(base)
    let saved = try XCTUnwrap(state["saved"] as? [[String: Any]])
    XCTAssertTrue(
      saved.contains { $0["file"] as? String == filename && $0["matches"] as? Bool == true })
    // 完成系统提供的本机拷贝操作，不给任何联系人或外部服务发送文件。
    let copy = activity.cells.matching(NSPredicate(format: "label == %@", "拷贝")).firstMatch
    XCTAssertTrue(copy.waitForExistence(timeout: 5))
    copy.tap()
    let closed = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: activity)
    XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
    XCTAssertFalse(app.staticTexts["暂时无法打开 MoviePilot"].exists)
    XCTAssertEqual(app.state, .runningForeground)
  }

  /// 独立合成实例记录首次与缓存后冷启动、前后台和导航成本；不采集界面截图。
  func testAppCachePerformanceBaseline() async throws {
    guard let server = ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_CACHE_SERVER"],
      server == "http://127.0.0.1:5235", let base = URL(string: server)
    else { throw XCTSkip("需要独立本机缓存性能夹具。") }
    continueAfterFailure = false
    var samples: [[String: Any]] = []
    let app = XCUIApplication()
    for sample in 1...3 {
      try await resetCacheMeasurement(base, phase: "first-\(sample)")
      app.launchArguments = [
        "-moviepilot.instance.selected.v1", "", "-AppleLanguages", "(zh-Hans)",
      ]
      app.launch()
      let address = app.textFields["MoviePilot 服务地址"]
      XCTAssertTrue(address.waitForExistence(timeout: 10))
      address.tap()
      if address.buttons.firstMatch.exists { address.buttons.firstMatch.tap() }
      address.typeText("\(server)/bench-\(UUID().uuidString)/\n")
      authenticateFixture(app)
      XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 30))
      samples.append(try await cacheMeasurement(base, phase: "first-\(sample)"))
      app.terminate()
    }
    for sample in 1...3 {
      try await resetCacheMeasurement(base, phase: "cached-\(sample)")
      app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
      let started = Date()
      app.launch()
      XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 30))
      var result = try await cacheMeasurement(base, phase: "cached-\(sample)")
      result["launchToNativeMs"] = Date().timeIntervalSince(started) * 1000
      samples.append(result)
      if sample != 3 { app.terminate() }
    }
    try await resetCacheMeasurement(base, phase: "navigation-and-resume")
    for title in ["推荐", "探索", "更多", "推荐", "探索", "更多", "推荐", "探索", "更多", "推荐"] {
      let button = app.tabBars["native-root-navigation"].buttons[title]
      XCTAssertTrue(button.isHittable)
      button.tap()
      XCTAssertTrue(button.isEnabled)
    }
    for _ in 0..<3 {
      XCUIDevice.shared.press(.home)
      app.activate()
      XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 10))
    }
    let (body, _) = try await URLSession.shared.data(
      from: base.appendingPathComponent("__fixture/stats"))
    let current = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let requests = current["requests"] as? [[String: Any]] ?? []
    XCTAssertFalse(
      requests.contains {
        ($0["path"] as? String)?.range(
          of: "^/bench-[0-9A-Fa-f-]{36}/$", options: .regularExpression) != nil
      }, "切换页面和恢复前台不能重新请求顶层 HTML 文档")
    samples.append(current)
    let attachment = XCTAttachment(
      data: try JSONSerialization.data(withJSONObject: samples, options: [.sortedKeys]),
      uniformTypeIdentifier: "public.json")
    attachment.name = "App缓存性能基线"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// 每段测量只重置夹具计数，不删除 App 实例、系统缓存或认证状态。
  private func resetCacheMeasurement(_ base: URL, phase: String) async throws {
    var request = URLRequest(url: base.appendingPathComponent("__fixture/reset"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: ["phase": phase])
    let (_, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
  }

  /// 等待真实页面的双绘制帧与原生接管标记；只读取脱敏性能数字和资源路径。
  private func cacheMeasurement(_ base: URL, phase: String) async throws -> [String: Any] {
    for _ in 0..<80 {
      let (body, _) = try await URLSession.shared.data(
        from: base.appendingPathComponent("__fixture/stats"))
      if let value = try JSONSerialization.jsonObject(with: body) as? [String: Any],
        let metrics = value["metrics"] as? [[String: Any]],
        metrics.contains(where: { $0["native"] as? Bool == true })
      {
        return value
      }
      try await Task.sleep(for: .milliseconds(100))
    }
    XCTFail("\(phase)没有收到完成原生接管后的性能采样")
    return [:]
  }

  /// 无实例历史的首屏与尚未登录的新实例直接使用预设玻璃底色，无需网页回传。
  func testAccountDefaultAppearanceBeforeFirstLogin() async throws {
    guard
      ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_ACCOUNT_APPEARANCE"]
        == "http://127.0.0.1:5234"
    else { throw XCTSkip("需要独立本机账号外观夹具。") }
    for (appearance, title) in [("light", "浅色"), ("dark", "深色")] {
      try await setSystemAppearance(appearance)
      let fresh = XCUIApplication()
      // 参数域仅在此进程遮蔽历史；不提交连接，因此不会覆盖已保存的实例列表。
      fresh.launchArguments = [
        "-moviepilot.instance.selected.v1", "", "-moviepilot.instances.v1", "",
        "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
      ]
      fresh.launch()
      let address = fresh.textFields["MoviePilot 服务地址"]
      XCTAssertTrue(address.waitForExistence(timeout: 10))
      XCTAssertEqual(address.value as? String, "https://moviepilot.example.com")
      attachScreen("账号主题-首次使用\(title)连接", app: fresh)
      fresh.terminate()
      // 独立别名没有收到过网页主题，也不提交账号密码。
      let app = try launchLogin(server: "http://localhost:5234")
      XCTAssertFalse(app.webViews.firstMatch.exists)
      attachScreen("账号主题-首次使用\(title)登录", app: app)
      app.terminate()
    }
  }

  /// 网页确认的手动明暗与系统偏好跨更改地址、原生登录及冷启动保持一致。
  func testAccountThemeMatchesLastWebAppearance() async throws {
    guard let server = ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_ACCOUNT_APPEARANCE"],
      server == "http://127.0.0.1:5234", let base = URL(string: server)
    else { throw XCTSkip("需要独立本机账号外观夹具。") }
    for (theme, system, title) in [
      ("dark", "light", "手动深色"), ("light", "dark", "手动浅色"),
      ("system", "dark", "跟随系统深色"),
    ] {
      try await setSystemAppearance(system)
      var request = URLRequest(url: base.appendingPathComponent("__fixture/theme"))
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: ["theme": theme])
      let (_, response) = try await URLSession.shared.data(for: request)
      XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
      let app = try launchLogin(server: server)
      authenticateFixture(app)
      XCTAssertTrue(app.tables["more-menu"].waitForExistence(timeout: 15))
      attachScreen("账号主题-\(title)主界面", app: app)
      app.buttons["操作菜单"].tap()
      app.buttons["连接与显示"].tap()
      app.buttons["更改服务地址"].tap()
      let address = app.textFields["MoviePilot 服务地址"]
      XCTAssertTrue(address.waitForExistence(timeout: 10))
      attachScreen("账号主题-\(title)连接", app: app)
      address.tap()
      address.typeText("\n")
      XCTAssertTrue(app.textFields["用户名"].waitForExistence(timeout: 10))
      attachScreen("账号主题-\(title)登录", app: app)
      relaunchSavedLoginInstance(app)
      XCTAssertTrue(app.textFields["用户名"].waitForExistence(timeout: 15))
      XCTAssertFalse(app.webViews.firstMatch.exists)
      attachScreen("账号主题-\(title)冷启动登录", app: app)
      if theme == "system" {
        try await setSystemAppearance("light")
        settlePage(app)
        attachScreen("账号主题-跟随系统浅色登录", app: app)
        app.buttons["更改地址"].tap()
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        attachScreen("账号主题-跟随系统浅色连接", app: app)
      }
      app.terminate()
    }
  }

  /// 原生表单和连接子菜单都不提供网页退路，桥断开后只能原生重试或更改地址。
  func testNativeOnlyNavigationRecovery() async throws {
    let server = try await prepareNativeOnlyFixture(mode: "healthy")
    let app = try launchLogin(server: server)
    XCTAssertFalse(app.buttons["使用网页登录"].exists)
    attachScreen("原生专用-登录", app: app)
    authenticateFixture(app, remember: false)
    XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 30))
    app.buttons["操作菜单"].tap()
    app.buttons["连接与显示"].tap()
    XCTAssertTrue(app.buttons["重新加载"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["更改服务地址"].exists)
    XCTAssertFalse(app.buttons["使用网页导航"].exists)
    attachScreen("原生专用-连接菜单", app: app)
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.28)).tap()
    _ = try await prepareNativeOnlyFixture(mode: "bridge-failed")
    XCTAssertTrue(app.staticTexts["暂时无法打开 MoviePilot"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.webViews.firstMatch.exists)
    XCTAssertTrue(app.buttons["重新打开"].isHittable)
    XCTAssertTrue(app.buttons["更改服务地址"].isHittable)
    attachScreen("原生专用-导航恢复", app: app)
    _ = try await prepareNativeOnlyFixture(mode: "healthy")
    app.buttons["重新打开"].tap()
    XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 30))
    XCTAssertFalse(app.otherElements["native-startup-screen"].exists)
  }

  /// 实际发布前端收到运行中 HTTP401 后由登录路由交回原生，不重启 App。
  func testExpiredNativeSessionReturnsWithoutRelaunch() async throws {
    let server = try await prepareNativeOnlyFixture(mode: "healthy")
    let app = try launchLogin(server: server)
    authenticateFixture(app, remember: false)
    XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 30))
    _ = try await prepareNativeOnlyFixture(mode: "expired")
    // 在途请求可能已先收到401；只有原生表单尚未出现时才触发新的业务读取。
    let login = app.navigationBars["登录"]
    if !login.waitForExistence(timeout: 2) {
      let more = app.tabBars["native-root-navigation"].buttons["更多"]
      if more.exists && more.isHittable { more.tap() }
      let row = app.tables["more-menu"].cells.containing(.staticText, identifier: "电影订阅").firstMatch
      if row.waitForExistence(timeout: 2), row.isHittable { row.tap() }
    }
    XCTAssertTrue(app.navigationBars["登录"].waitForExistence(timeout: 20))
    XCTAssertTrue(app.textFields["用户名"].exists)
    XCTAssertTrue(app.secureTextFields["密码"].exists)
    XCTAssertFalse(app.webViews.firstMatch.exists)
    XCTAssertFalse(app.buttons["使用网页登录"].exists)
    XCTAssertEqual(app.state, .runningForeground)
    _ = try await prepareNativeOnlyFixture(mode: "healthy")
    authenticateFixture(app, remember: false)
    XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 30))
  }

  /// 历史网页偏好即便仍为真，也不能绕过原生认证恢复完整网页。
  func testLegacyWebLoginPreferenceCannotBypassNativeLogin() async throws {
    let server = try await prepareNativeOnlyFixture(mode: "healthy")
    let app = try launchLogin(server: server)
    authenticateFixture(app, remember: false)
    XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 30))
    let (data, _) = try await URLSession.shared.data(
      from: try XCTUnwrap(URL(string: server + "/__fixture/context")))
    let value = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let identifier = try XCTUnwrap(value["instanceId"] as? String)
    XCTAssertNotNil(UUID(uuidString: identifier))
    app.terminate()
    app.launchArguments = [
      "-AppleLanguages", "(zh-Hans)", "-moviepilot.web-login.\(identifier)", "YES",
    ]
    app.launch()
    XCTAssertTrue(app.navigationBars["登录"].waitForExistence(timeout: 15))
    XCTAssertFalse(app.webViews.firstMatch.exists)
    XCTAssertFalse(app.buttons["使用网页登录"].exists)
  }

  /// 无桥的旧 HTML 即使下载完成也不展示，更新后原生重新打开能够恢复。
  func testIncompatibleFrontendStaysBehindNativeRecovery() async throws {
    let server = try await prepareNativeOnlyFixture(mode: "legacy")
    let app = try launchLogin(server: server)
    authenticateFixture(app, remember: false)
    XCTAssertTrue(app.otherElements["native-startup-screen"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.webViews.firstMatch.exists)
    XCTAssertTrue(app.staticTexts["暂时无法打开 MoviePilot"].waitForExistence(timeout: 55))
    XCTAssertFalse(app.webViews.firstMatch.exists)
    _ = try await prepareNativeOnlyFixture(mode: "healthy")
    app.buttons["重新打开"].tap()
    XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 30))
  }

  /// 未初始化只给出浏览器准备说明和原生重新检查，不在 App 内打开网页初始化。
  func testUninitializedInstanceKeepsNativeForm() async throws {
    let server = try await prepareNativeOnlyFixture(mode: "uninitialized")
    let app = try launchLogin(server: server)
    XCTAssertTrue(app.buttons["重新检查"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["使用网页登录"].exists)
    XCTAssertFalse(app.buttons["在网页初始化"].exists)
    XCTAssertFalse(app.webViews.firstMatch.exists)
    _ = try await prepareNativeOnlyFixture(mode: "healthy")
    app.buttons["重新检查"].tap()
    XCTAssertTrue(app.buttons["登录"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["重新检查"].exists)
  }

  /// 合成认证走实际原生表单；默认值仅供显式私有夹具，不写入产品或业务接口。
  private func authenticateFixture(_ app: XCUIApplication, remember: Bool = true) {
    let environment = ProcessInfo.processInfo.environment
    let name = environment["MOVIEPILOT_E2E_USERNAME"] ?? "native-demo"
    let secret = environment["MOVIEPILOT_E2E_PASSWORD"] ?? "fixture-only"
    XCTAssertTrue(app.textFields["用户名"].waitForExistence(timeout: 15))
    let keep = app.switches["保持登录"]
    if (keep.value as? String == "1") != remember { keep.tap() }
    app.textFields["用户名"].tap()
    app.textFields["用户名"].typeText(name)
    app.secureTextFields["密码"].tap()
    app.secureTextFields["密码"].typeText(secret + "\n")
    let prompt = app.alerts["已登录"]
    if prompt.waitForExistence(timeout: 1) { prompt.buttons["好"].tap() }
  }

  /// 模式只传到显式本机夹具，HTTP401 和标准桥消息仍经真实产品代码处理。
  private func prepareNativeOnlyFixture(mode: String) async throws -> String {
    guard let server = ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_NATIVE_ONLY_SERVER"],
      server == "http://127.0.0.1:5236", let base = URL(string: server)
    else { throw XCTSkip("需要独立本机原生专用导航夹具。") }
    var request = URLRequest(url: base.appendingPathComponent("__fixture/state"))
    request.httpMethod = "POST"
    request.httpBody = try JSONSerialization.data(withJSONObject: ["mode": mode])
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let (_, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    return server
  }

  /// 移除测试首次连接的空选择参数，让冷启动真正读取已经保存的实例和偏好。
  private func relaunchSavedLoginInstance(_ app: XCUIApplication) {
    app.terminate()
    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    app.launch()
  }

  /// 真实共享区域与系统 Keychain 启用测试资料，普通 CI 不登记用户服务。
  func testWidgetEnableCurrentAccount() async throws {
    guard ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_WIDGETS"] == "1" else {
      throw XCTSkip("需要显式启用系统小组件验收。")
    }
    confirmNotificationAppOpening()
    let environment = ProcessInfo.processInfo.environment
    guard let server = environment["MOVIEPILOT_E2E_SERVER"],
      let username = environment["MOVIEPILOT_E2E_USERNAME"],
      let password = environment["MOVIEPILOT_E2E_PASSWORD"]
    else { throw XCTSkip("需要私有本机夹具配置。") }
    let app = launchConnection(server: server)
    if app.textFields["用户名"].waitForExistence(timeout: 5) {
      app.textFields["用户名"].tap()
      app.textFields["用户名"].typeText(username)
      app.secureTextFields["密码"].tap()
      app.secureTextFields["密码"].typeText(password + "\n")
      if app.alerts["已登录"].waitForExistence(timeout: 3) { app.alerts["已登录"].buttons["好"].tap() }
    }
    XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 35))
    settlePage(app)
    app.buttons["操作菜单"].tap()
    app.buttons["连接与显示"].tap()
    let widgets = app.buttons["小组件"].firstMatch
    XCTAssertTrue(widgets.waitForExistence(timeout: 10), app.debugDescription)
    widgets.tap()
    let enable = app.cells["widget-enable"].firstMatch
    XCTAssertTrue(enable.waitForExistence(timeout: 15), app.debugDescription)
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "enabled == true"), object: enable)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed, app.debugDescription)
    if app.staticTexts["尚未启用"].exists {
      XCTAssertFalse(app.cells["widget-refresh"].exists)
    }
    attachScreen("Widget-当前服务未启用", app: app)
    enable.tap()
    let alert = app.alerts["启用小组件"]
    XCTAssertTrue(alert.waitForExistence(timeout: 5))
    alert.buttons["确定"].tap()
    XCTAssertTrue(
      app.staticTexts["已启用，只读显示当前账号允许的内容。"].waitForExistence(timeout: 20), app.debugDescription)
    XCTAssertTrue(app.cells["widget-refresh"].exists)
    XCTAssertFalse(app.staticTexts["尚无数据"].exists, "实际共享 Keychain 读取后应保存受限快照")
    attachScreen("Widget-当前服务已启用", app: app)
    try await openWidgetFixture(content: "downloads")
    XCTAssertTrue(app.navigationBars["小组件"].exists, "已有原生设置尚未关闭时应保留待处理的跳转")
    app.navigationBars["小组件"].buttons.firstMatch.tap()
    XCTAssertTrue(
      app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS %@", "下载")).firstMatch
        .waitForExistence(timeout: 20), app.debugDescription)
    settlePage(app)
    XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
    attachScreen("Widget-热启动进入下载管理", app: app)
    try await openWidgetFixture(content: "downloads")
    settlePage(app)
    XCTAssertFalse(app.alerts.firstMatch.exists, "已在目标页时重复点击组件也应成功")
    app.terminate()
    try await openWidgetFixture(content: "downloads")
    XCTAssertTrue(
      app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS %@", "下载")).firstMatch
        .waitForExistence(timeout: 30), app.debugDescription)
    settlePage(app)
    XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
    XCTAssertTrue(app.buttons["操作菜单"].exists)
    attachScreen("Widget-冷启动恢复对应服务", app: app)
  }

  /// 仅本机显式夹具可通过系统 URL 打开已登记的合成资料；公开测试没有真实资料标识。
  private func openWidgetFixture(content: String) async throws {
    guard let server = ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_SERVER"],
      let base = URL(string: server), base.scheme == "http", base.host == "127.0.0.1",
      base.port == 5230
    else { throw XCTSkip("固定跳转验收需要独立本机 Widget 夹具。") }
    var request = URLRequest(url: base.appendingPathComponent("__fixture/widget-open"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: ["content": content])
    let (_, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    confirmNotificationAppOpening()
  }

  /// 真实 SpringBoard 组件库验证三种桌面尺寸；普通 CI 不更改模拟器桌面。
  func testWidgetSystemGallery() throws {
    try addDesktopWidget()
  }

  /// 每次重新安装后独立添加组件，不假定上次 UI 验收的桌面或今天视图状态仍存在。
  private func addDesktopWidget(onToday: Bool = false, sizeIndex: Int = 2) throws {
    guard ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_WIDGETS"] == "1" else {
      throw XCTSkip("需要显式启用系统小组件验收。")
    }
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    let app = XCUIApplication()
    app.launchArguments = ["-moviepilot.instance.selected.v1", "", "-AppleLanguages", "(zh-Hans)"]
    app.launch()
    XCUIDevice.shared.press(.home)
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    XCTAssertTrue(springboard.icons["MoviePilot"].firstMatch.waitForExistence(timeout: 15))
    let candidates =
      onToday
      ? springboard.icons.matching(
        NSPredicate(format: "value IN %@", ["小组件", "Widget"]))
      : springboard.icons.matching(identifier: "MoviePilot")
    if onToday {
      enterToday(in: springboard)
    }
    guard
      let icon = candidates.allElementsBoundByIndex.first(where: { $0.isHittable })
    else {
      XCTFail(springboard.debugDescription)
      return
    }
    icon.press(forDuration: 1.2)
    attachScreen("Widget-桌面图标菜单", app: springboard)
    let edit = springboard.buttons.matching(
      NSPredicate(format: "label IN %@", ["编辑主屏幕", "Edit Home Screen"])
    ).firstMatch
    XCTAssertTrue(edit.waitForExistence(timeout: 8), springboard.debugDescription)
    edit.tap()
    let editMenu = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["编辑", "Edit"]))
      .firstMatch
    XCTAssertTrue(editMenu.waitForExistence(timeout: 8), springboard.debugDescription)
    editMenu.tap()
    let add = springboard.buttons.matching(
      NSPredicate(format: "label IN %@", ["添加小组件", "Add Widget"])
    ).firstMatch
    XCTAssertTrue(add.waitForExistence(timeout: 8), springboard.debugDescription)
    add.tap()
    let search = springboard.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 10), springboard.debugDescription)
    search.tap()
    search.typeText("MoviePilot")
    let result = springboard.staticTexts["MoviePilot"].firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 15), springboard.debugDescription)
    result.tap()
    let addWidget = springboard.buttons.matching(
      NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "添加小组件", "Add Widget")
    ).firstMatch
    XCTAssertTrue(addWidget.waitForExistence(timeout: 15), springboard.debugDescription)
    for index in 0..<3 {
      attachScreen("Widget-系统组件库-桌面尺寸-\(index + 1)", app: springboard)
      if index < 2 {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.58))
          .press(
            forDuration: 0.05,
            thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.58)))
      }
    }
    for _ in sizeIndex..<2 {
      springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.58))
        .press(
          forDuration: 0.05,
          thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.58)))
    }
    addWidget.tap()
    let done = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["完成", "Done"]))
      .firstMatch
    if done.waitForExistence(timeout: 5) { done.tap() }
    attachScreen("Widget-桌面未配置", app: springboard)
    let hierarchy = XCTAttachment(string: springboard.debugDescription)
    hierarchy.name = "Widget-桌面结构"
    hierarchy.lifetime = .keepAlways
    self.add(hierarchy)
  }

  /// 真实桌面组件显式选择夹具服务，核验扩展读取共享快照并通过系统点击进入原页面。
  func testWidgetSystemConfiguration() throws {
    guard ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_WIDGETS"] == "1" else {
      throw XCTSkip("需要显式启用系统小组件验收。")
    }
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    try addDesktopWidget()
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let widget = try configureWidget(in: springboard)
    attachScreen("Widget-扩展读取共享下载快照", app: springboard)
    widget.tap()
    confirmNotificationAppOpening()
    let app = XCUIApplication()
    XCTAssertTrue(
      app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS %@", "下载")).firstMatch
        .waitForExistence(timeout: 35), app.debugDescription)
    settlePage(app)
    XCTAssertFalse(app.alerts.firstMatch.exists)
    attachScreen("Widget-桌面点击进入下载管理", app: app)
  }

  /// 今天视图使用相同系统组件，实际添加、配置和只读渲染均需通过系统交互验证。
  func testWidgetSystemTodayConfiguration() throws {
    try addDesktopWidget(onToday: true)
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let widget = try configureWidget(in: springboard)
    revealWidget(widget, in: springboard)
    attachScreen("Widget-今天视图下载状态", app: springboard)
  }

  /// 系统滚动容器可能只露出组件的一角，截图前必须让整个组件落在安全可见区域。
  private func revealWidget(_ widget: XCUIElement, in springboard: XCUIApplication) {
    let visible = springboard.frame.insetBy(dx: 0, dy: 44)
    for _ in 0..<10 {
      if widget.isHittable && visible.contains(widget.frame) { break }
      if widget.frame.minY < visible.minY {
        springboard.swipeDown(velocity: .slow)
      } else {
        springboard.swipeUp(velocity: .slow)
      }
    }
    XCTAssertTrue(widget.isHittable && visible.contains(widget.frame), springboard.debugDescription)
  }

  /// 系统编辑器显式选择资料及内容，不通过测试启动参数为组件自动指定账号。
  private func configureWidget(
    in springboard: XCUIApplication, expected: String = "2.4 MB/s", content: String = "下载状态",
    target: XCUIElement? = nil, hideMediaNames: Bool = true
  )
    throws -> XCUIElement
  {
    let widgets = springboard.icons.matching(
      NSPredicate(format: "label == %@ AND value IN %@", "MoviePilot", ["小组件", "Widget"])
    )
    XCTAssertTrue(widgets.firstMatch.waitForExistence(timeout: 15), springboard.debugDescription)
    let widget = try XCTUnwrap(
      target ?? widgets.allElementsBoundByIndex.first(where: { $0.isHittable }),
      springboard.debugDescription)
    let size = widget.frame.size
    widget.press(forDuration: 1.2)
    let edit = springboard.buttons.matching(
      NSPredicate(format: "label IN %@", ["编辑小组件", "Edit Widget"])
    ).firstMatch
    XCTAssertTrue(edit.waitForExistence(timeout: 8), springboard.debugDescription)
    edit.tap()
    XCTAssertTrue(
      springboard.staticTexts["服务"].waitForExistence(timeout: 10), springboard.debugDescription)
    XCTAssertTrue(springboard.staticTexts["内容"].exists)
    attachScreen("Widget-系统配置编辑器", app: springboard)
    let hierarchy = XCTAttachment(string: springboard.debugDescription)
    hierarchy.name = "Widget-配置结构"
    hierarchy.lifetime = .keepAlways
    self.add(hierarchy)
    springboard.buttons.matching(NSPredicate(format: "label IN %@", ["服务", "MoviePilot"]))
      .firstMatch.tap()
    let service = springboard.buttons["MoviePilot"].firstMatch
    XCTAssertTrue(service.waitForExistence(timeout: 15), springboard.debugDescription)
    attachScreen("Widget-选择已启用服务", app: springboard)
    service.tap()
    springboard.buttons.matching(
      NSPredicate(format: "label IN %@", ["内容", "下载状态", "订阅", "近期入库", "系统概览"])
    )
    .firstMatch.tap()
    let downloads = springboard.descendants(matching: .any).matching(identifier: content).firstMatch
    XCTAssertTrue(downloads.waitForExistence(timeout: 15), springboard.debugDescription)
    downloads.tap()
    let names = springboard.switches["显示媒体名称"]
    if hideMediaNames {
      if names.value as? String == "1" { names.tap() }
      XCTAssertEqual(names.value as? String, "0")
    } else {
      XCTAssertEqual(names.value as? String, "1", "新组件默认显示媒体名称")
    }
    attachScreen("Widget-已选择服务与下载状态", app: springboard)
    springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
    // 桌面在编辑完成后会重新排列图标，原 boundByIndex 不能继续代表刚才的组件。
    let configured = widgets.containing(NSPredicate(format: "label ENDSWITH %@", expected))
    let rendered = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        configured.allElementsBoundByIndex.contains {
          $0.isHittable && abs($0.frame.width - size.width) < 8
            && abs($0.frame.height - size.height) < 8
        }
      }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [rendered], timeout: 40), .completed)
    return try XCTUnwrap(
      configured.allElementsBoundByIndex.first {
        $0.isHittable && abs($0.frame.width - size.width) < 8
          && abs($0.frame.height - size.height) < 8
      }, springboard.debugDescription)
  }

  /// 四类内容实际配置三种桌面尺寸，核验总数/统计与大卡片名称并保留系统截图。
  func testWidgetRichContentSizes() async throws {
    guard ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_WIDGETS"] == "1" else {
      throw XCTSkip("需要显式启用系统小组件验收。")
    }
    continueAfterFailure = false
    try await setWidgetFixtureScenario("ready")
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let contents = [("下载状态", "2.4 MB/s"), ("订阅", "42"), ("近期入库", "3,428"), ("系统概览", "24.5%")]
    for size in 0..<3 {
      try addDesktopWidget(sizeIndex: size)
      let widgets = springboard.icons.matching(
        NSPredicate(format: "label == %@ AND value IN %@", "MoviePilot", ["小组件", "Widget"]))
      var widget = try XCTUnwrap(
        widgets.allElementsBoundByIndex.first { element in
          guard element.isHittable else { return false }
          if size == 0 { return element.frame.width < 240 && element.frame.height < 240 }
          if size == 1 { return element.frame.width > 240 && element.frame.height < 240 }
          return element.frame.height > 240
        }, springboard.debugDescription)
      for (content, expected) in contents {
        widget = try configureWidget(
          in: springboard, expected: expected, content: content, target: widget,
          hideMediaNames: false)
        revealWidget(widget, in: springboard)
        if content == "系统概览" {
          XCTAssertTrue(widget.staticTexts["62.8%"].exists, springboard.debugDescription)
          XCTAssertFalse(widget.staticTexts["电影"].exists)
        } else if size == 2 {
          XCTAssertTrue(
            widget.staticTexts["人生切割术"].waitForExistence(timeout: 15), springboard.debugDescription)
        } else {
          XCTAssertFalse(widget.staticTexts["人生切割术"].exists)
        }
        if size > 0 && content == "订阅" {
          XCTAssertTrue(widget.staticTexts["28"].exists)
          XCTAssertTrue(widget.staticTexts["12"].exists)
        }
        if size > 0 && content == "近期入库" {
          XCTAssertTrue(widget.staticTexts["1,280"].exists)
          XCTAssertTrue(widget.staticTexts["2,080"].exists)
          XCTAssertTrue(widget.staticTexts["68"].exists)
        }
        attachScreen("Widget-丰富内容-\(content)-尺寸\(size + 1)", app: springboard)
      }
      widget.press(forDuration: 1.2)
      let remove = springboard.buttons.matching(
        NSPredicate(format: "label IN %@", ["移除小组件", "Remove Widget"])
      ).firstMatch
      XCTAssertTrue(remove.waitForExistence(timeout: 8), springboard.debugDescription)
      remove.tap()
      let confirm = springboard.alerts.buttons.matching(
        NSPredicate(format: "label IN %@", ["移除", "Remove"])
      ).firstMatch
      XCTAssertTrue(confirm.waitForExistence(timeout: 8), springboard.debugDescription)
      confirm.tap()
    }
  }

  /// 各场景使用独立合成资料，经真实系统编辑与时间线验证空、旧及自然到期状态。
  func testWidgetSystemStates() async throws {
    guard ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_WIDGETS"] == "1" else {
      throw XCTSkip("需要显式启用系统小组件验收。")
    }
    continueAfterFailure = false
    let springboard = revealTodayDownloadWidget()
    for (scenario, expected) in [
      ("empty", "暂无内容"), ("stale", "数据待更新"),
      ("expiring", "数据已过期，请打开 App 刷新"), ("ready", "2.4 MB/s"),
    ] {
      try await setWidgetFixtureScenario(scenario)
      let widget = try configureWidget(in: springboard, expected: expected)
      if scenario == "expiring" {
        XCTAssertFalse(widget.staticTexts["2.4 MB/s"].exists)
        XCTAssertFalse(widget.staticTexts["680 KB/s"].exists)
      }
      attachScreen("Widget-系统状态-\(scenario)", app: springboard)
    }
  }

  /// 只允许显式隔离夹具切换有限合成场景，不能请求用户实例的任意写入端点。
  private func setWidgetFixtureScenario(_ scenario: String) async throws {
    guard let server = ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_SERVER"],
      let base = URL(string: server), base.scheme == "http", base.host == "127.0.0.1",
      base.port == 5230, ["empty", "stale", "expiring", "ready"].contains(scenario)
    else { throw XCTSkip("系统状态验收只允许本任务隔离夹具。") }
    var request = URLRequest(url: base.appendingPathComponent("__fixture/widget-state"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: ["scenario": scenario])
    let (_, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
  }

  /// 主屏只做有界滑动和可见性核验，已配置的组件继续由 WidgetKit 读取自己的资料。
  private func revealTodayDownloadWidget() -> XCUIApplication {
    XCUIDevice.shared.press(.home)
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    enterToday(in: springboard)
    let widgets = springboard.icons.matching(
      NSPredicate(format: "label == %@ AND value IN %@", "MoviePilot", ["小组件", "Widget"])
    )
    XCTAssertTrue(widgets.firstMatch.waitForExistence(timeout: 15))
    let widget =
      widgets.allElementsBoundByIndex.first(where: {
        $0.frame.width > 0 && $0.frame.minX >= 0 && $0.frame.minX < springboard.frame.width
      }) ?? widgets.firstMatch
    revealWidget(widget, in: springboard)
    return springboard
  }

  /// 今天视图没有可操作的主屏聚焦页码，不能仅凭默认日历或地图组件推断所在页面。
  private func enterToday(in springboard: XCUIApplication) {
    let page = springboard.descendants(matching: .any).matching(identifier: "spotlight-pill")
      .firstMatch
    for _ in 0..<8 {
      if !page.exists || !page.isHittable { break }
      springboard.swipeRight()
    }
    XCTAssertFalse(page.exists && page.isHittable, springboard.debugDescription)
  }

  /// 系统墙纸编辑器验证圆形、矩形与行内图库，组件外观不由测试自行模拟。
  func testWidgetSystemLockEditor() throws {
    guard ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_WIDGETS"] == "1" else {
      throw XCTSkip("需要显式启用系统小组件验收。")
    }
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let poster = XCUIApplication(bundleIdentifier: "com.apple.PosterBoard")
    let sheetHandle = poster.buttons["表单控制柄"]
    if sheetHandle.exists { sheetHandle.tap() }
    if !poster.buttons["editing-done"].exists {
      XCUIDevice.shared.press(.home)
      springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.005))
        .press(
          forDuration: 0.05,
          thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.88)))
      attachScreen("Widget-锁屏通知中心", app: springboard)
      springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).press(
        forDuration: 1.5)
      let customize = springboard.buttons.matching(
        NSPredicate(format: "label IN %@", ["自定", "自定义", "Customize", "Customise"])
      ).firstMatch
      XCTAssertTrue(customize.waitForExistence(timeout: 10), springboard.debugDescription)
      customize.tap()
    }
    XCTAssertTrue(poster.buttons["完成"].waitForExistence(timeout: 20), poster.debugDescription)
    attachScreen("Widget-系统墙纸编辑器", app: poster)
    let editor = XCTAttachment(string: poster.debugDescription)
    editor.name = "Widget-锁屏编辑结构"
    editor.lifetime = .keepAlways
    add(editor)
    let widgets = try XCTUnwrap(
      poster.buttons.matching(identifier: "grouped-widgets-reticle-view").allElementsBoundByIndex
        .last)
    XCTAssertTrue(widgets.waitForExistence(timeout: 10), poster.debugDescription)
    widgets.tap()
    XCTAssertTrue(
      poster.navigationBars["PRComplicationGalleryView"].waitForExistence(timeout: 10),
      poster.debugDescription)
    attachScreen("Widget-锁屏组件库", app: poster)
    let gallery = XCTAttachment(string: poster.debugDescription)
    gallery.name = "Widget-锁屏组件库结构"
    gallery.lifetime = .keepAlways
    add(gallery)
    let moviepilot = poster.cells.matching(NSPredicate(format: "label CONTAINS %@", "MoviePilot"))
      .firstMatch
    for _ in 0..<4 {
      if moviepilot.exists && moviepilot.isHittable { break }
      // 最后一个 collection 是当前图库；整屏坐标会命中后面的墙纸编辑滚动层。
      try XCTUnwrap(poster.collectionViews.allElementsBoundByIndex.last).swipeUp()
    }
    XCTAssertTrue(moviepilot.exists && moviepilot.isHittable, poster.debugDescription)
    moviepilot.tap()
    XCTAssertTrue(
      poster.descendants(matching: .any).matching(
        NSPredicate(format: "label BEGINSWITH %@", "MoviePilot 状态")
      ).firstMatch.waitForExistence(timeout: 15), poster.debugDescription)
    attachScreen("Widget-锁屏圆形与矩形预览", app: poster)
    let sizes = XCTAttachment(string: poster.debugDescription)
    sizes.name = "Widget-锁屏尺寸结构"
    sizes.lifetime = .keepAlways
    add(sizes)
    poster.buttons["关闭"].firstMatch.tap()
    XCTAssertTrue(sheetHandle.waitForExistence(timeout: 5))
    sheetHandle.tap()
    let inline = try XCTUnwrap(
      poster.buttons.matching(identifier: "inline-widget-reticle-view").allElementsBoundByIndex.last
    )
    XCTAssertTrue(inline.waitForExistence(timeout: 8))
    inline.tap()
    let inlineWidget = poster.cells.matching(
      NSPredicate(format: "label BEGINSWITH %@", "MoviePilot, MoviePilot 状态")
    ).firstMatch
    for _ in 0..<5 {
      if inlineWidget.exists && inlineWidget.isHittable { break }
      if poster.collectionViews.count > 1 {
        try XCTUnwrap(poster.collectionViews.allElementsBoundByIndex.last).swipeUp()
      } else if poster.tables.firstMatch.exists {
        poster.tables.firstMatch.swipeUp()
      } else {
        try XCTUnwrap(poster.scrollViews.allElementsBoundByIndex.last).swipeUp()
      }
    }
    XCTAssertTrue(inlineWidget.exists && inlineWidget.isHittable, poster.debugDescription)
    attachScreen("Widget-锁屏行内预览", app: poster)
    if !inlineWidget.isSelected { inlineWidget.tap() }
    XCTAssertTrue(inlineWidget.isSelected, poster.debugDescription)
    sheetHandle.tap()
    XCTAssertTrue(poster.buttons["完成"].isHittable)
    attachScreen("Widget-锁屏行内已添加", app: poster)
  }

  /// 初始化探测覆盖各本地地址形式；未初始化时仅保留原生重新检查，不暴露网页。
  func testLocalNetworkTransports() async throws {
    let fixtures = try await networkFixtures()
    XCTAssertGreaterThanOrEqual(fixtures.servers.count, 4, "需覆盖 IPv4、IPv6、私网及本地名称")
    for (index, server) in fixtures.servers.enumerated() {
      let app = try launchLogin(server: server)
      XCTAssertTrue(app.buttons["重新检查"].waitForExistence(timeout: 25), "原生请求须收到夹具的未初始化状态")
      XCTAssertFalse(app.buttons["使用网页登录"].exists)
      XCTAssertFalse(app.webViews.firstMatch.exists)
      attachScreen("网络-原生初始化检查-\(index + 1)", app: app)
      app.terminate()
    }
  }

  /// 明确覆盖浏览器不支持的网卡标识地址，保留编辑入口并避免先进入一个无法工作的登录页。
  func testScopedIPv6AddressRecovery() async throws {
    let fixtures = try await networkFixtures()
    let app = launchConnection(server: fixtures.unsupportedScopedIPv6)
    XCTAssertTrue(
      app.staticTexts["此 IPv6 地址包含网卡标识，网页无法使用。请改用 .local 主机名或其他可访问的地址。"]
        .waitForExistence(timeout: 10))
    XCTAssertTrue(app.textFields["MoviePilot 服务地址"].isEnabled)
    XCTAssertTrue(app.buttons["连接"].isEnabled)
    XCTAssertFalse(app.textFields["用户名"].exists)
    attachScreen("网络-网卡标识地址兼容提示", app: app)
  }

  /// 证书错误、服务不可达及超时必须有具体提示，网页失败还须保留恢复入口。
  func testNetworkFailureRecovery() async throws {
    let fixtures = try await networkFixtures()
    let cases = [
      (fixtures.untrustedCertificate, "服务器的 HTTPS 证书未受系统信任或已失效。请修复证书后重试。"),
      (fixtures.unavailable, "无法连接服务，请检查地址、端口和服务状态后重试。"),
      (fixtures.timedOut, "连接超时，请检查网络及服务状态后重试。"),
    ]
    for (index, scenario) in cases.enumerated() {
      let app = try launchLogin(server: scenario.0)
      XCTAssertTrue(app.staticTexts[scenario.1].waitForExistence(timeout: 30))
      XCTAssertTrue(app.buttons["更改地址"].isEnabled)
      XCTAssertFalse(app.buttons["使用网页登录"].exists)
      XCTAssertFalse(app.webViews.firstMatch.exists)
      attachScreen("网络-原生失败提示-\(index + 1)", app: app)
      app.buttons["更改地址"].tap()
      XCTAssertTrue(app.textFields["MoviePilot 服务地址"].waitForExistence(timeout: 10))
      attachScreen("网络-失败后更改地址-\(index + 1)", app: app)
      app.terminate()
    }
  }

  /// 网络验收仅使用显式指定的本机夹具；普通 CI 不访问用户实例或外部网络。
  private func networkFixtures() async throws -> NetworkFixtures {
    guard let value = ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_NETWORK_FIXTURE"],
      let url = URL(string: value), url.host == "127.0.0.1", url.scheme == "http"
    else { throw XCTSkip("网络矩阵需要显式配置本机隔离夹具。") }
    let (data, _) = try await URLSession.shared.data(from: url.appendingPathComponent("__cases"))
    return try JSONDecoder().decode(NetworkFixtures.self, from: data)
  }

  /// 普通重新加载继续使用当前路由与登录会话，不能把恢复操作变成完整网页模式。
  func testReloadRestoresNativeNavigation() throws {
    let app = try signIn()
    app.tabBars["native-root-navigation"].buttons["推荐"].tap()
    XCTAssertTrue(app.navigationBars["推荐"].waitForExistence(timeout: 10))
    settlePage(app)
    app.buttons["操作菜单"].tap()
    app.buttons["连接与显示"].tap()
    app.buttons["重新加载"].tap()
    XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 35))
    XCTAssertTrue(app.navigationBars["推荐"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["操作菜单"].isHittable)
    XCTAssertFalse(app.staticTexts["暂时无法打开 MoviePilot"].exists)
    attachScreen("恢复-重新加载保留原生导航与当前页面", app: app)
  }

  /// 后台往返保留现有面板和输入，正常恢复不应重新载入整个文档。
  func testBackgroundResumePreservesNativePanel() throws {
    let app = try signIn()
    settlePage(app)
    app.buttons["操作菜单"].tap()
    app.buttons["搜索"].firstMatch.tap()
    let field = app.searchFields["native-panel-search-field"]
    XCTAssertTrue(field.waitForExistence(timeout: 8))
    field.tap()
    field.typeText("后台保留\n")
    XCUIDevice.shared.press(.home)
    XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
    app.activate()
    XCTAssertTrue(field.waitForExistence(timeout: 12))
    XCTAssertEqual(field.value as? String, "后台保留")
    app.buttons["native-panel-close"].tap()
    XCTAssertTrue(app.tabBars["native-root-navigation"].exists)
    attachScreen("恢复-后台返回保留原生面板状态", app: app)
  }

  /// 隔离宿主终止当前模拟器专用 WebContent，验证真正进程回收后的自动接管。
  func testTerminatedWebContentRecoversNativeNavigation() async throws {
    guard let value = ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_PROCESS_FIXTURE"],
      let fixture = URL(string: value), fixture.host == "127.0.0.1", fixture.scheme == "http"
    else { throw XCTSkip("进程回收验收需要专用模拟器及本机隔离夹具。") }
    let app = try signIn()
    app.tabBars["native-root-navigation"].buttons["推荐"].tap()
    XCTAssertTrue(app.navigationBars["推荐"].waitForExistence(timeout: 10))
    settlePage(app)
    XCUIDevice.shared.press(.home)
    XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
    var request = URLRequest(url: fixture.appendingPathComponent("__fixture/terminate-web-content"))
    request.httpMethod = "POST"
    let (data, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    let result = try JSONSerialization.jsonObject(with: data) as? [String: Int]
    XCTAssertEqual(result?["terminated"], 1, "夹具必须只终止专用模拟器的一个内容进程")
    app.activate()
    XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 35))
    XCTAssertTrue(app.navigationBars["推荐"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["操作菜单"].isHittable)
    XCTAssertFalse(app.staticTexts["暂时无法打开 MoviePilot"].exists)
    attachScreen("恢复-后台进程回收后恢复原生框架", app: app)
  }

  /// 隔离中转夹具验证原生设置、真实绑定码与主屏幕通知链接，不访问外部推送服务。
  func testNotificationSettingsAndHotLink() async throws {
    guard let fixture = ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_NOTIFICATION_FIXTURE"],
      let server = URL(string: fixture)
    else { throw XCTSkip("通知联调仅在隔离夹具中执行。") }
    let app = try signIn()
    settlePage(app)
    dismissUpdateReminderIfVisible(app)
    app.buttons["操作菜单"].tap()
    app.buttons["连接与显示"].tap()
    app.buttons["通知"].firstMatch.tap()
    let settings = app.tables["notification-settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 10))
    XCTAssertTrue(settings.cells["notification-generate"].waitForExistence(timeout: 15))
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "isEnabled == true"),
      object: settings.cells["notification-generate"])
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
    settings.cells["notification-center-reset"].tap()
    let serviceCenter = settings.cells["notification-service-center"]
    XCTAssertEqual(serviceCenter.value as? String, "https://movie-pilot.org")
    attachScreen("通知-免费自签与主屏幕入口", app: app)
    serviceCenter.tap()
    let centerEditor = app.alerts["通知服务中心"]
    XCTAssertTrue(centerEditor.textFields["notification-center-address"].exists)
    XCTAssertEqual(
      centerEditor.textFields["notification-center-address"].value as? String,
      "https://movie-pilot.org")
    centerEditor.buttons["取消"].tap()
    app.buttons["完成"].tap()
    app.buttons["操作菜单"].tap()
    app.buttons["连接与显示"].tap()
    app.buttons["通知"].firstMatch.tap()
    XCTAssertTrue(settings.waitForExistence(timeout: 10))
    XCTAssertEqual(serviceCenter.value as? String, "https://movie-pilot.org")
    let loaded = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "isEnabled == true"),
      object: settings.cells["notification-generate"])
    XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 15), .completed)
    settings.cells["notification-generate"].tap()
    XCTAssertTrue(app.alerts["通知"].waitForExistence(timeout: 15))
    XCTAssertFalse(settings.cells["notification-copy-code"].exists)
    app.alerts["通知"].buttons["好"].tap()
    settings.cells["notification-center-instance"].tap()
    settings.cells["notification-generate"].tap()
    XCTAssertTrue(settings.cells["notification-copy-code"].waitForExistence(timeout: 15))
    attachScreen("通知-Server一次性绑定码", app: app)
    app.buttons["完成"].tap()
    _ = try await URLSession.shared.data(from: server.appendingPathComponent("__fixture/open"))
    confirmNotificationAppOpening()
    XCTAssertTrue(app.tables["native-quick-panel"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.navigationBars["通知中心"].exists)
    attachScreen("通知-链接返回原生通知中心", app: app)
    app.buttons["native-panel-close"].tap()
    _ = try await URLSession.shared.data(
      from: URL(string: "__fixture/open?other=true", relativeTo: server)!)
    confirmNotificationAppOpening()
    XCTAssertTrue(
      app.alerts["通知"].staticTexts["这条通知属于其他实例或账号，请切换后查看通知中心。"].waitForExistence(timeout: 10))
    app.alerts["通知"].buttons["好"].tap()
  }

  /// 通知链接经系统入口冷启动，等待原登录完成后再打开既有通知中心。
  func testNotificationColdStartLink() async throws {
    guard let fixture = ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_NOTIFICATION_FIXTURE"],
      let server = URL(string: fixture)
    else { throw XCTSkip("通知联调仅在隔离夹具中执行。") }
    let app = try signIn()
    settlePage(app)
    _ = try await URLSession.shared.data(
      from: URL(string: "__fixture/open?cold=true", relativeTo: server)!)
    confirmNotificationAppOpening()
    let outcome = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        app.textFields["用户名"].exists || app.tables["native-quick-panel"].exists
      }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [outcome], timeout: 20), .completed)
    if app.textFields["用户名"].exists {
      let environment = ProcessInfo.processInfo.environment
      app.textFields["用户名"].tap()
      app.textFields["用户名"].typeText(environment["MOVIEPILOT_E2E_USERNAME"] ?? "")
      app.secureTextFields["密码"].tap()
      app.secureTextFields["密码"].typeText((environment["MOVIEPILOT_E2E_PASSWORD"] ?? "") + "\n")
      let prompt = app.alerts["已登录"]
      if prompt.waitForExistence(timeout: 3) { prompt.buttons["好"].tap() }
    }
    XCTAssertTrue(app.tables["native-quick-panel"].waitForExistence(timeout: 45))
    XCTAssertTrue(app.navigationBars["通知中心"].exists)
    attachScreen("通知-冷启动等待登录后打开", app: app)
  }

  /// 自定义 scheme 的系统确认属于真实用户交接，自动化也必须明确点击打开。
  private func confirmNotificationAppOpening() {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let open = springboard.alerts.buttons["打开"]
    if open.waitForExistence(timeout: 3) { open.tap() }
  }

  /// 资源门和原生协商都完成前只展示静态启动页，内容不能提前露出。
  func testStaticStartupWaitsForContent() async throws {
    let server = try await prepareNativeOnlyFixture(mode: "delayed")
    let app = try launchLogin(server: server)
    authenticateFixture(app, remember: false)
    let startup = app.otherElements["native-startup-screen"]
    XCTAssertTrue(startup.waitForExistence(timeout: 10))
    XCTAssertFalse(app.webViews.firstMatch.exists)
    XCTAssertFalse(app.navigationBars.firstMatch.exists)
    _ = try await prepareNativeOnlyFixture(mode: "healthy")
    XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 30))
    XCTAssertFalse(startup.exists)
  }

  /// 从连接、原生登录到原生菜单，再进入原 HTML 插件页并返回菜单。
  func testNativeLoginAndMoreMenu() throws {
    let app = try signIn()
    // 按公开标签查找系统导航，不依赖 UIKit 的内部容器层级。
    let more = app.buttons["更多"]
    XCTAssertTrue(more.waitForExistence(timeout: 45), "登录后应显示原生主导航入口")
    more.tap()
    let menu = app.tables["more-menu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 10), "更多页应由 UIKit 表格接管")
    attachScreen("原生更多菜单", app: app)
    let search = revealMoreSearch(app)
    XCTAssertTrue(search.exists)
    search.tap()
    search.typeText("插件")
    let plugin = menu.cells.containing(.staticText, identifier: "插件").firstMatch
    XCTAssertTrue(plugin.waitForExistence(timeout: 5))
    plugin.tap()
    let classification = app.buttons["插件，页内分类"]
    XCTAssertTrue(classification.waitForExistence(timeout: 15))
    XCTAssertTrue(app.webViews.firstMatch.exists, "业务页面继续来自原有 HTML")
    attachScreen("原HTML插件页与原生导航", app: app)
    app.buttons["返回"].tap()
    XCTAssertTrue(menu.waitForExistence(timeout: 10))
    attachScreen("返回原生更多菜单", app: app)
  }

  /// 按当前权限目录逐项打开真实页面，截图用于视觉复核，过程不提交任何业务表单。
  func testCaptureAppGallery() throws {
    guard ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_CAPTURE"] == "1" else {
      throw XCTSkip("截图册只在显式开启的私有验收运行中采集。")
    }
    let app = try signIn()
    XCTAssertLessThan(app.frame.width, app.frame.height, "截图验收使用 iPhone Pro 竖屏")
    let more = app.tabBars["native-root-navigation"].buttons["更多"]
    settlePage(app)
    attachScreen("框架-单行原生导航", app: app)
    XCTAssertTrue(more.exists, "iPhone Pro 主导航应显示在底部")
    XCTAssertEqual(app.tabBars.count, 1, "底部只保留一个主导航组")
    XCTAssertGreaterThan(more.frame.minY, app.frame.height / 2)
    for title in ["仪表盘", "推荐", "探索"] {
      let entry = app.buttons[title].firstMatch
      guard entry.exists else { continue }
      entry.tap()
      XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15))
      XCTAssertTrue(
        app.navigationBars[title].waitForExistence(timeout: 10), "HTML 路由切换后原生标题必须联动")
      settlePage(app)
      assertBottomLayout(app)
      attachScreen("页面-\(title)", app: app)
      if title == "推荐" {
        let categories = app.buttons["推荐，页内分类"]
        categories.tap()
        attachScreen("交互-原生中文分类菜单", app: app)
        app.buttons["电影"].firstMatch.tap()
        let selected = XCTNSPredicateExpectation(
          predicate: NSPredicate(format: "value == %@", "电影"), object: categories)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
        attachScreen("交互-中文分类联动", app: app)
        categories.tap()
        app.buttons["全部"].firstMatch.tap()
        settlePage(app)
        let link = app.webViews.links["更多"].firstMatch
        if link.exists {
          link.tap()
          XCTAssertTrue(app.buttons["返回"].waitForExistence(timeout: 10))
          XCTAssertTrue(app.buttons["推荐"].waitForExistence(timeout: 10))
          XCTAssertTrue(app.buttons["推荐"].isSelected, "HTML 内部跳转应保留所属主导航")
          settlePage(app)
          let title = app.navigationBars.firstMatch.identifier
          XCTAssertNotEqual(title, "MoviePilot", "详情顶部标题应沿用原 HTML 的业务标题")
          XCTAssertFalse(app.webViews.staticTexts[title].exists, "页面级标题只在原生导航中出现")
          attachScreen("交互-HTML页面跳转与导航联动", app: app)
          app.buttons["返回"].tap()
          XCTAssertTrue(app.navigationBars["推荐"].waitForExistence(timeout: 10))
        }
      }
    }
    app.buttons["更多"].tap()
    let menu = app.tables["more-menu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 10))
    let names = menu.cells.allElementsBoundByIndex.map { $0.staticTexts.firstMatch.label }
      .filter { !$0.isEmpty }
    XCTAssertFalse(names.isEmpty)
    attachScreen("页面-更多", app: app)
    let catalog = XCTAttachment(string: names.joined(separator: "\n"))
    catalog.name = "本次授权菜单目录"
    catalog.lifetime = .keepAlways
    add(catalog)
    for title in names {
      let search = revealMoreSearch(app)
      XCTAssertTrue(search.waitForExistence(timeout: 10))
      search.tap()
      if let value = search.value as? String, value != search.placeholderValue {
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
      }
      search.typeText(title)
      let item = menu.cells.containing(.staticText, identifier: title).firstMatch
      XCTAssertTrue(item.waitForExistence(timeout: 5))
      item.tap()
      XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15))
      let back = app.buttons["返回"]
      XCTAssertTrue(back.waitForExistence(timeout: 15), "页面跳转后原生返回应同步出现")
      settlePage(app)
      let categoryTitle = app.buttons["\(title)，页内分类"]
      if categoryTitle.exists {
        XCTAssertGreaterThanOrEqual(categoryTitle.frame.width, 64, "页内分类标题不能逐字挤成竖排")
        XCTAssertLessThanOrEqual(categoryTitle.frame.height, 44, "顶部标题保持一行导航的高度")
      }
      assertBottomLayout(app)
      attachScreen("页面-\(title)", app: app)
      capturePageCategories(title, app: app)
      // 分类可能写入 Router 查询历史；逐页采集按产品要求用“更多”直接回目录。
      more.tap()
      XCTAssertTrue(menu.waitForExistence(timeout: 10))
      XCTAssertFalse(app.buttons["返回"].exists, "点击更多后不保留分类或业务页返回栈")
    }
  }

  /// 助手三个标题动作由原生菜单接管；历史子窗返回后保留父窗和原始 HTML 输入区。
  func testNativeAgentSheetMenu() async throws {
    try await setUIScenario("agent")
    let app = try signIn()
    let trigger = app.webViews.buttons.matching(
      NSPredicate(format: "label == %@ OR label == %@", "奶龙", "智能助手")
    ).firstMatch
    attachScreen("交互-Agent入口与页面", app: app)
    XCTAssertTrue(trigger.waitForExistence(timeout: 15))
    trigger.tap()
    let menu = app.buttons["native-sheet-menu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 12))
    XCTAssertFalse(app.webViews.buttons["历史会话"].firstMatch.isHittable)
    XCTAssertFalse(app.webViews.buttons["新会话"].firstMatch.isHittable)
    attachScreen("交互-Agent原生标题栏", app: app)
    menu.tap()
    for title in ["历史会话", "更换形象", "新会话"] {
      XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 5))
    }
    attachScreen("交互-Agent原生三点菜单", app: app)
    app.buttons["历史会话"].tap()
    XCTAssertTrue(app.navigationBars["历史会话"].waitForExistence(timeout: 8))
    attachScreen("交互-Agent历史会话原生弹窗", app: app)
    app.buttons["native-sheet-close"].tap()
    XCTAssertTrue(menu.waitForExistence(timeout: 8))
    menu.tap()
    app.buttons["更换形象"].tap()
    XCTAssertTrue(app.webViews.buttons["返回对话"].waitForExistence(timeout: 10))
    attachScreen("交互-Agent原有形象选择", app: app)
    app.webViews.buttons["返回对话"].tap()
    menu.tap()
    app.buttons["新会话"].tap()
    XCTAssertTrue(app.webViews.staticTexts["今天想处理什么？"].waitForExistence(timeout: 8))
    app.buttons["native-sheet-close"].tap()
    XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 8))
    try await setUIScenario("default")
  }

  /// 页面标题栏筛选也使用原生列表，选择继续更新已有 Vue 筛选条件。
  func testNativePageHeaderActions() throws {
    let app = try signIn()
    app.tabBars["native-root-navigation"].buttons["更多"].tap()
    let menu = app.tables["more-menu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 10))
    let search = revealMoreSearch(app)
    search.tap()
    search.typeText("站点管理")
    menu.cells.containing(.staticText, identifier: "站点管理").firstMatch.tap()
    XCTAssertTrue(app.navigationBars["站点管理"].waitForExistence(timeout: 15))
    settlePage(app)
    XCTAssertFalse(app.webViews.staticTexts["站点管理"].exists, "正文不再重复页面标题")
    XCTAssertFalse(app.webViews.buttons["筛选"].exists, "标题旁操作由框架呈现")
    attachScreen("交互-站点统一标题与渐变顶栏", app: app)
    app.buttons["操作菜单"].tap()
    XCTAssertTrue(app.buttons["筛选"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["排序"].exists)
    XCTAssertTrue(app.staticTexts["常用入口"].exists)
    XCTAssertTrue(app.staticTexts["当前页面"].exists, "页面动作必须与跨页面入口明确分组")
    XCTAssertTrue(app.buttons["搜索"].exists)
    XCTAssertLessThan(app.buttons["搜索"].frame.minY, app.buttons["筛选"].frame.minY)
    attachScreen("交互-站点标题操作进入三点菜单", app: app)
    app.buttons["筛选"].tap()
    let filter = app.tables["native-quick-panel"]
    XCTAssertTrue(filter.waitForExistence(timeout: 10))
    XCTAssertTrue(filter.cells["native-panel-item-connected"].exists)
    XCTAssertTrue(app.tabBars["native-root-navigation"].exists, "筛选菜单保留底部导航")
    attachScreen("交互-原生站点筛选菜单", app: app)
    filter.cells["native-panel-item-connected"].tap()
    XCTAssertTrue(app.buttons["操作菜单"].waitForExistence(timeout: 8))
    app.buttons["返回"].tap()
    XCTAssertTrue(menu.waitForExistence(timeout: 10))
  }

  /// 插件和整理历史筛选继续调用原 Vue 状态，原生菜单可关闭、重开和切换分类。
  func testNativePluginAndHistoryFilters() throws {
    let app = try signIn()
    openMorePage("插件", app: app)
    let category = app.buttons["插件，页内分类"]
    XCTAssertTrue(category.waitForExistence(timeout: 10))
    app.buttons["操作菜单"].tap()
    app.buttons["筛选"].tap()
    let panel = app.tables["native-quick-panel"]
    XCTAssertTrue(panel.waitForExistence(timeout: 8))
    XCTAssertTrue(panel.cells["native-panel-item-running"].exists)
    XCTAssertTrue(panel.cells["native-panel-item-updates"].exists)
    XCTAssertTrue(app.searchFields["native-panel-search-field"].exists)
    attachScreen("交互-原生已安装插件筛选", app: app)
    panel.cells["native-panel-item-running"].tap()
    category.tap()
    app.buttons["插件市场"].firstMatch.tap()
    settlePage(app)
    app.buttons["操作菜单"].tap()
    app.buttons["筛选"].tap()
    XCTAssertTrue(panel.waitForExistence(timeout: 8))
    XCTAssertTrue(panel.cells["native-panel-item-count"].exists)
    XCTAssertTrue(panel.cells["native-panel-item-average_rating"].exists)
    attachScreen("交互-原生插件市场筛选与排序", app: app)
    panel.cells["native-panel-item-average_rating"].tap()
    openMorePage("媒体整理", app: app)
    settlePage(app)
    app.buttons["操作菜单"].tap()
    app.buttons["状态筛选"].tap()
    XCTAssertTrue(panel.waitForExistence(timeout: 8))
    XCTAssertTrue(panel.cells["native-panel-item-all"].exists)
    XCTAssertTrue(panel.cells["native-panel-item-success"].exists)
    XCTAssertTrue(panel.cells["native-panel-item-failed"].exists)
    attachScreen("交互-原生整理历史状态筛选", app: app)
    panel.cells["native-panel-item-success"].tap()
    XCTAssertTrue(app.buttons["操作菜单"].waitForExistence(timeout: 8))
  }

  /// 订阅状态、排序和分享关键字都在系统面板输入，原网页 watcher 消费同一状态。
  func testNativeSubscriptionAndShareFilters() throws {
    let app = try signIn()
    openMorePage("电视剧订阅", app: app)
    let category = app.buttons["电视剧订阅，页内分类"]
    XCTAssertTrue(category.waitForExistence(timeout: 10))
    settlePage(app)
    app.buttons["操作菜单"].tap()
    app.buttons["筛选"].tap()
    let panel = app.tables["native-quick-panel"]
    XCTAssertTrue(panel.waitForExistence(timeout: 8))
    XCTAssertTrue(panel.cells["native-panel-item-status-all"].exists)
    XCTAssertTrue(panel.cells["native-panel-item-sort-custom"].exists)
    XCTAssertTrue(app.searchFields["native-panel-search-field"].exists)
    attachScreen("交互-原生订阅状态与排序筛选", app: app)
    panel.cells["native-panel-item-status-all"].tap()
    category.tap()
    app.buttons["订阅分享"].firstMatch.tap()
    settlePage(app)
    app.buttons["操作菜单"].tap()
    app.buttons["筛选"].tap()
    XCTAssertTrue(panel.waitForExistence(timeout: 8))
    let field = app.searchFields["native-panel-search-field"]
    XCTAssertTrue(field.exists)
    field.tap()
    field.typeText("示例\n")
    XCTAssertEqual(field.value as? String, "示例")
    attachScreen("交互-原生订阅分享搜索", app: app)
    app.buttons["native-panel-close"].tap()
    openMorePage("工作流", app: app)
    let workflow = app.buttons["工作流，页内分类"]
    XCTAssertTrue(workflow.waitForExistence(timeout: 10))
    workflow.tap()
    app.buttons["工作流分享"].firstMatch.tap()
    settlePage(app)
    app.buttons["操作菜单"].tap()
    app.buttons["筛选"].tap()
    XCTAssertTrue(panel.waitForExistence(timeout: 8))
    XCTAssertTrue(field.exists)
    field.tap()
    field.typeText("示例\n")
    XCTAssertEqual(field.value as? String, "示例")
    attachScreen("交互-原生工作流分享搜索", app: app)
    app.buttons["native-panel-close"].tap()
    XCTAssertTrue(app.tabBars["native-root-navigation"].exists)
  }

  /// 搜索框与菜单项对齐，文件刷新只通过原生菜单触发同一 HTML 列表更新。
  func testMoreSearchAndFileActions() throws {
    let app = try signIn()
    app.tabBars["native-root-navigation"].buttons["更多"].tap()
    let menu = app.tables["more-menu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 10))
    let search = revealMoreSearch(app)
    XCTAssertTrue(search.exists)
    let firstRow = menu.cells.firstMatch
    XCTAssertEqual(search.frame.minX, firstRow.frame.minX, accuracy: 1)
    XCTAssertEqual(search.frame.maxX, firstRow.frame.maxX, accuracy: 1)
    attachScreen("页面-更多", app: app)
    search.tap()
    search.typeText("文件管理")
    attachScreen("交互-更多菜单搜索", app: app)
    menu.cells.containing(.staticText, identifier: "文件管理").firstMatch.tap()
    XCTAssertTrue(app.navigationBars["文件管理"].waitForExistence(timeout: 15))
    settlePage(app)
    XCTAssertFalse(app.webViews.staticTexts["文件管理"].exists, "正文不保留重复标题")
    XCTAssertFalse(app.webViews.buttons["刷新"].exists, "刷新不再单独占用正文一行")
    attachScreen("页面-文件管理", app: app)
    app.buttons["操作菜单"].tap()
    let refresh = app.buttons["刷新"]
    XCTAssertTrue(refresh.waitForExistence(timeout: 5))
    XCTAssertTrue(refresh.isEnabled)
    attachScreen("交互-文件管理刷新菜单", app: app)
    refresh.tap()
    settlePage(app)
    XCTAssertTrue(app.navigationBars["文件管理"].exists)
    XCTAssertTrue(app.webViews.firstMatch.exists)
    XCTAssertFalse(app.webViews.buttons["刷新"].exists)
    app.buttons["返回"].tap()
    XCTAssertTrue(menu.waitForExistence(timeout: 10))
  }

  /// 单独采集设定首页，公开演示配置也必须满足原表单校验，不修改后端配置。
  func testCaptureSettingsPage() throws {
    guard ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_CAPTURE"] == "1" else {
      throw XCTSkip("截图只在显式开启的私有验收运行中采集。")
    }
    let app = try signIn()
    app.tabBars["native-root-navigation"].buttons["更多"].tap()
    let menu = app.tables["more-menu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 10))
    let search = revealMoreSearch(app)
    search.tap()
    search.typeText("设定")
    menu.cells.containing(.staticText, identifier: "设定").firstMatch.tap()
    XCTAssertTrue(app.buttons["设定，页内分类"].waitForExistence(timeout: 15))
    settlePage(app)
    XCTAssertFalse(app.webViews.staticTexts["API Token不得低于16位"].exists)
    attachScreen("页面-设定", app: app)
    attachScreen("页面-设定 · 系统", app: app)
  }

  /// 按 UIKit 公开的标题及副标题查询系统菜单，动作标识不等同于辅助功能标识。
  private func nativeUserItem(_ title: String, app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(
      NSPredicate(format: "label == %@ OR label BEGINSWITH %@", title, title + ",")
    )
    .firstMatch
  }

  /// 主题入口直接位于用户菜单内，设置业务仍交给原 HTML 弹窗。
  func testNativeHTMLPresentation() throws {
    let app = try signIn()
    settlePage(app)
    app.tabBars["native-root-navigation"].buttons["更多"].tap()
    let menu = app.tables["more-menu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 10))
    assertBottomLayout(app)
    attachScreen("页面-更多主题与居中底栏", app: app)
    let search = revealMoreSearch(app)
    search.tap()
    search.typeText("插件")
    menu.cells.containing(.staticText, identifier: "插件").firstMatch.tap()
    XCTAssertTrue(app.buttons["插件，页内分类"].waitForExistence(timeout: 15))
    app.buttons["操作菜单"].tap()
    let user = nativeUserItem("用户", app: app)
    let connection = app.buttons["连接与显示"].firstMatch
    XCTAssertTrue(user.waitForExistence(timeout: 8))
    XCTAssertGreaterThanOrEqual(user.frame.minY, connection.frame.maxY - 2)
    attachScreen("交互-常用入口用户位于最后", app: app)
    nativeUserItem("用户", app: app).tap()
    let theme = nativeUserItem("主题", app: app)
    let language = nativeUserItem("语言", app: app)
    XCTAssertTrue(theme.waitForExistence(timeout: 8), "用户入口必须进入系统二级菜单")
    XCTAssertFalse(app.tables["native-quick-panel"].exists)
    for item in ["附加样式", "界面布局"] {
      XCTAssertFalse(app.buttons[item].exists)
    }
    attachScreen("交互-原生用户菜单", app: app)
    XCTAssertEqual(language.frame.minY, theme.frame.maxY, accuracy: 3, "主题和语言应相邻，不插入分类标题")
    attachScreen("交互-用户菜单主题与语言相邻", app: app)
    nativeUserItem("主题", app: app).tap()
    XCTAssertTrue(app.navigationBars["主题定制"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["native-sheet-close"].exists)
    XCTAssertTrue(app.webViews.staticTexts["色调"].firstMatch.waitForExistence(timeout: 10))
    XCTAssertFalse(app.webViews.staticTexts["圆角"].exists)
    XCTAssertTrue(app.webViews.switches["浅色"].firstMatch.exists)
    XCTAssertTrue(app.webViews.switches["深色"].firstMatch.exists)
    XCTAssertTrue(app.webViews.switches["跟随系统"].firstMatch.exists)
    settlePage(app)
    XCTAssertGreaterThan(
      app.navigationBars["主题定制"].frame.minY, app.frame.height * 0.35, "主题定制初次使用系统半屏 Sheet")
    attachScreen("交互-主题明暗与主色半屏", app: app)
    attachScreen("交互-主题定制安全区", app: app)
    dismissOverlays(app)
    app.tabBars["native-root-navigation"].buttons["更多"].tap()
    XCTAssertTrue(menu.waitForExistence(timeout: 10), "从业务页点击更多必须立即回到原生目录")
    XCTAssertFalse(app.buttons["返回"].exists, "回到目录后不能残留业务返回栈")
  }

  /// 手动明暗和跟随系统共用玻璃主题，并在系统半屏中即时同步原生与 HTML 外观。
  func testNativeGlassAppearanceSelection() async throws {
    try await setSystemAppearance("dark")
    let app = try signIn()
    settlePage(app)
    app.buttons["操作菜单"].tap()
    nativeUserItem("用户", app: app).tap()
    XCTAssertTrue(nativeUserItem("主题", app: app).waitForExistence(timeout: 8))
    nativeUserItem("主题", app: app).tap()
    XCTAssertTrue(app.navigationBars["主题定制"].waitForExistence(timeout: 10))
    for mode in ["浅色", "深色", "跟随系统"] {
      let choice = app.webViews.switches[mode].firstMatch
      XCTAssertTrue(choice.waitForExistence(timeout: 8))
      choice.tap()
      settlePage(app)
      XCTAssertEqual(choice.value as? String, "1", "三项明暗选择应保持互斥的当前选中状态")
      attachScreen("交互-主题手动选择-\(mode)", app: app)
    }
    try await setSystemAppearance("light")
    settlePage(app)
    attachScreen("交互-主题跟随系统浅色", app: app)
    app.buttons["native-sheet-close"].tap()
    settlePage(app)
    app.buttons["操作菜单"].tap()
    attachScreen("交互-跟随浅色的原生菜单", app: app)
    dismissOverlays(app)
    try await setSystemAppearance("dark")
  }

  /// 切换模拟器系统明暗，验证固定玻璃主题与系统浮层同步，而非修改网页主题偏好。
  func testNativeMaterialsInLightAndDarkThemes() async throws {
    let app = try signIn()
    settlePage(app)
    let roots = app.tabBars["native-root-navigation"]
    roots.buttons["推荐"].tap()
    let categories = app.buttons["推荐，页内分类"]
    XCTAssertTrue(categories.waitForExistence(timeout: 10))
    categories.tap()
    attachScreen("交互-原生中文分类菜单", app: app)
    attachScreen("交互-原生页内分类菜单", app: app)
    app.buttons["全部"].firstMatch.tap()
    roots.buttons["仪表盘"].tap()
    settlePage(app)
    for (theme, appearance) in [("浅色", "light"), ("深色", "dark")] {
      try await setSystemAppearance(appearance)
      settlePage(app)
      app.buttons["操作菜单"].tap()
      nativeUserItem("用户", app: app).tap()
      XCTAssertTrue(nativeUserItem("主题", app: app).waitForExistence(timeout: 8))
      nativeUserItem("主题", app: app).tap()
      let panel = app.tables["native-quick-panel"]
      XCTAssertTrue(app.navigationBars["主题定制"].waitForExistence(timeout: 10))
      settlePage(app)
      attachScreen("交互-\(theme)主题系统磨砂 Sheet", app: app)
      app.buttons["native-sheet-close"].tap()
      XCTAssertFalse(app.buttons["native-sheet-close"].waitForExistence(timeout: 1))
      settlePage(app)
      for title in ["搜索", "插件面板"] {
        app.buttons["操作菜单"].tap()
        XCTAssertTrue(app.buttons[title].firstMatch.waitForExistence(timeout: 5))
        app.buttons[title].firstMatch.tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        settlePage(app)
        attachScreen("交互-\(theme)主题原生\(title)", app: app)
        app.buttons["native-panel-close"].tap()
      }
    }
  }

  /// 换主题、滚动复用和重新进入目录后保留统一图标，文件整理使用明确的文件夹符号。
  func testMoreMenuSymbolsAfterThemeChanges() async throws {
    let app = try signIn()
    let roots = app.tabBars["native-root-navigation"]
    for (theme, appearance) in [("浅色", "light"), ("深色", "dark")] {
      try await setSystemAppearance(appearance)
      settlePage(app)
      roots.buttons["更多"].tap()
      let menu = app.tables["more-menu"]
      XCTAssertTrue(menu.waitForExistence(timeout: 10))
      settlePage(app)
      attachScreen("交互-\(theme)更多菜单统一图标-顶部", app: app)
      let organize = menu.cells.containing(.staticText, identifier: "媒体整理").firstMatch
      for _ in 0..<5 where !organize.isHittable { menu.swipeUp() }
      XCTAssertTrue(organize.exists)
      XCTAssertTrue(organize.isHittable)
      attachScreen("交互-\(theme)更多菜单文件整理图标", app: app)
      menu.swipeUp()
      menu.swipeDown()
      attachScreen("交互-\(theme)更多菜单滚动复用", app: app)
      roots.buttons["仪表盘"].tap()
      roots.buttons["更多"].tap()
      XCTAssertTrue(menu.waitForExistence(timeout: 10))
      attachScreen("交互-\(theme)更多菜单重新进入", app: app)
    }
  }

  /// 受控目录经真实网页桥接显示，保留明暗模式下分组卡片与搜索框的实际截图。
  func testMoreMenuNeutralSurfaces() async throws {
    guard let server = ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_MENU_FIXTURE"],
      server == "http://127.0.0.1:5232"
    else { throw XCTSkip("需要显式指定本机目录外观夹具。") }
    let app = try launchLogin(server: server)
    authenticateFixture(app)
    let menu = app.tables["more-menu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 15))
    for (theme, appearance) in [("深色", "dark"), ("浅色", "light")] {
      try await setSystemAppearance(appearance)
      _ = revealMoreSearch(app)
      settlePage(app)
      XCTAssertTrue(menu.cells.containing(.staticText, identifier: "电影订阅").firstMatch.exists)
      attachScreen("更多-\(theme)系统中性灰分组", app: app)
      menu.swipeUp()
      XCTAssertTrue(menu.cells.containing(.staticText, identifier: "媒体整理").firstMatch.exists)
      attachScreen("更多-\(theme)系统中性灰滚动", app: app)
    }
  }

  /// 五个全局入口使用系统控件，搜索和原业务动作之间不再出现网页菜单遮挡。
  func testNativeGlobalPanels() throws {
    let app = try signIn()
    settlePage(app)
    for (title, screenshot) in [
      ("捷径", "交互-原生捷径面板"),
      ("通知中心", "交互-原生消息中心"),
      ("插件面板", "交互-原生插件面板"),
      ("搜索", "交互-原生全局搜索"),
    ] {
      app.buttons["操作菜单"].tap()
      XCTAssertTrue(app.buttons[title].firstMatch.waitForExistence(timeout: 5))
      if title == "捷径" {
        XCTAssertTrue(app.staticTexts["常用入口"].exists)
        attachScreen("交互-顶部常用入口与页面操作分组", app: app)
      }
      app.buttons[title].firstMatch.tap()
      let panel = app.tables["native-quick-panel"]
      XCTAssertTrue(panel.waitForExistence(timeout: 8))
      settlePage(app)
      XCTAssertGreaterThanOrEqual(panel.frame.minY, 100, "浮层不能藏在系统顶栏后")
      if title == "捷径" || title == "插件面板" {
        XCTAssertGreaterThan(panel.frame.minY, app.frame.height * 0.35, "网格初次使用系统半屏 Sheet")
        XCTAssertGreaterThan(panel.frame.width, app.frame.width - 50)
      } else {
        XCTAssertLessThan(panel.frame.maxY, app.frame.height - 75, "普通面板为底栏保留显示区域")
        if title == "通知中心" {
          XCTAssertGreaterThan(panel.frame.width, app.frame.width - 34, "长正文通知中心使用接近安全区全宽")
        }
      }
      if title == "捷径" {
        let first = panel.buttons["native-panel-item-nameTest"]
        let second = panel.buttons["native-panel-item-ruleTest"]
        let third = panel.buttons["native-panel-item-logging"]
        XCTAssertTrue(first.isHittable && second.isHittable && third.isHittable)
        XCTAssertEqual(first.frame.minY, second.frame.minY, accuracy: 2)
        XCTAssertEqual(second.frame.minY, third.frame.minY, accuracy: 2)
        XCTAssertLessThan(first.frame.maxX, second.frame.maxX)
        XCTAssertFalse(panel.cells["native-panel-item-nameTest"].exists)
      }
      if title == "插件面板" {
        let tile = panel.buttons.matching(
          NSPredicate(format: "identifier BEGINSWITH %@", "native-panel-item-plugin-")
        ).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "插件验收必须展示实际安装的插件")
        let loaded = XCTNSPredicateExpectation(
          predicate: NSPredicate(format: "value == %@", "插件图标已加载"), object: tile)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 15), .completed)
      }
      if title == "搜索" {
        let field = app.searchFields["native-panel-search-field"]
        XCTAssertTrue(field.exists, "全局搜索使用系统输入框")
        field.tap()
        field.typeText("插件\n")
        XCTAssertTrue(panel.staticTexts["插件"].firstMatch.waitForExistence(timeout: 8))
      }
      if title == "通知中心", ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_MEDALS"] == "1" {
        XCTAssertTrue(
          panel.staticTexts["MoviePilot 通知已就绪"].waitForExistence(timeout: 8), "验证接口消息已呈现，不能只验空面板")
        let poster = panel.cells.containing(.staticText, identifier: "演示影片已入库").firstMatch
        let loaded = XCTNSPredicateExpectation(
          predicate: NSPredicate(format: "value == %@", "含海报"), object: poster)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 15), .completed, "必须加载图片，不能只验证占位符")
      }
      attachScreen(screenshot, app: app)
      app.buttons["native-panel-close"].tap()
      XCTAssertTrue(app.buttons["操作菜单"].waitForExistence(timeout: 5))
    }
    app.buttons["操作菜单"].tap()
    nativeUserItem("用户", app: app).tap()
    let username = ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_USERNAME"] ?? ""
    let summary = nativeUserItem("用户", app: app)
    XCTAssertTrue(summary.waitForExistence(timeout: 8))
    XCTAssertTrue(summary.label.contains(username), "账号摘要由系统菜单头部完整显示")
    XCTAssertFalse(app.tables["native-quick-panel"].exists)
    XCTAssertTrue(nativeUserItem("重启", app: app).exists)
    XCTAssertTrue(nativeUserItem("退出登录", app: app).exists)
    attachScreen("交互-原生用户信息与头像", app: app)
    let medals = nativeUserItem("我的勋章", app: app)
    if medals.waitForExistence(timeout: 3) {
      medals.tap()
      let close = app.buttons["native-sheet-close"]
      XCTAssertTrue(close.waitForExistence(timeout: 10))
      XCTAssertGreaterThan(close.frame.minY, 35, "勋章关闭按钮由原生弹窗栏统一呈现")
      XCTAssertLessThan(close.frame.maxY, 155)
      XCTAssertGreaterThan(close.frame.minX, app.frame.width - 80)
      attachScreen("交互-社区勋章关闭位置", app: app)
      close.tap()
      XCTAssertTrue(
        app.tabBars["native-root-navigation"].buttons["更多"].waitForExistence(timeout: 8))
    } else {
      dismissOverlays(app)
    }
  }

  /// 首次展开必须完整显示常用设置；权限项目较多时，系统菜单仍能滚动操作底部账号动作。
  func testNativeUserSubmenuInitialHeight() throws {
    let app = try signIn()
    settlePage(app)
    for cycle in 1...2 {
      app.buttons["操作菜单"].tap()
      nativeUserItem("用户", app: app).tap()
      let logout = nativeUserItem("退出登录", app: app)
      XCTAssertTrue(logout.waitForExistence(timeout: 8))
      settlePage(app)
      attachScreen("交互-用户二级菜单初始高度-\(cycle)", app: app)
      for title in ["个人信息", "系统设定", "主题", "语言"] {
        let item = nativeUserItem(title, app: app)
        XCTAssertTrue(item.isHittable, "用户菜单首屏应可直接操作\(title)，不能只存在于屏外")
      }
      if !logout.isHittable {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: end)
      }
      XCTAssertTrue(nativeUserItem("重启", app: app).isHittable)
      XCTAssertTrue(logout.isHittable, "系统滚动不能将底部账号操作永久裁掉")
      attachScreen("交互-用户菜单分组与底部操作-\(cycle)", app: app)
      XCTAssertFalse(app.tables["native-quick-panel"].exists, "仍使用原生二级菜单")
      app.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.78)).tap()
      XCTAssertTrue(app.buttons["操作菜单"].waitForExistence(timeout: 5))
    }
  }

  /// 真实表格滚动跨越后端分页，旧行保持可回看、可展开，末尾不再显示翻页入口。
  func testNotificationContinuousLoading() async throws {
    try await setUIScenario("notifications-feed")
    let app = try signIn()
    settlePage(app)
    app.buttons["操作菜单"].tap()
    app.buttons["通知中心"].firstMatch.tap()
    let panel = app.tables["native-quick-panel"]
    XCTAssertTrue(panel.waitForExistence(timeout: 8))
    XCTAssertTrue(panel.staticTexts["连续通知 01"].waitForExistence(timeout: 8))
    XCTAssertFalse(app.buttons["native-panel-more"].exists)
    XCTAssertFalse(panel.staticTexts["上一步"].exists)
    scrollNotifications(panel, to: panel.staticTexts["连续通知 21"])
    attachScreen("通知-触底连续追加", app: app)
    scrollNotifications(panel, to: panel.staticTexts["连续通知 45"])
    XCTAssertTrue(app.staticTexts["native-panel-feed-end"].waitForExistence(timeout: 8))
    let completedRequests = try await notificationRequests()
    XCTAssertEqual(completedRequests, [1, 2, 3])
    attachScreen("通知-连续加载末尾", app: app)
    scrollNotifications(panel, to: panel.staticTexts["连续通知 01"], upward: false)
    panel.staticTexts["连续通知 01"].tap()
    XCTAssertTrue(
      panel.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "正文完整结束"))
        .firstMatch.waitForExistence(timeout: 8))
    attachScreen("通知-回看与展开旧消息", app: app)
    app.buttons["native-panel-close"].tap()
    try await setUIScenario("default")
  }

  /// 下一 API 页首次失败后停止自动请求，用户重试成功仍在原列表继续追加。
  func testNotificationLoadRetry() async throws {
    try await setUIScenario("notifications-error")
    let app = try signIn()
    settlePage(app)
    app.buttons["操作菜单"].tap()
    app.buttons["通知中心"].firstMatch.tap()
    let panel = app.tables["native-quick-panel"]
    XCTAssertTrue(panel.waitForExistence(timeout: 8))
    let retry = app.buttons["native-panel-retry"]
    scrollNotifications(panel, to: retry)
    let failedRequests = try await notificationRequests()
    XCTAssertEqual(failedRequests, [1, 2])
    try await Task.sleep(for: .seconds(1))
    let waitingRequests = try await notificationRequests()
    XCTAssertEqual(waitingRequests, [1, 2], "失败后不能自动循环重试")
    attachScreen("通知-加载失败保留列表与重试", app: app)
    retry.tap()
    scrollNotifications(panel, to: panel.staticTexts["连续通知 45"])
    XCTAssertTrue(app.staticTexts["native-panel-feed-end"].waitForExistence(timeout: 8))
    let retriedRequests = try await notificationRequests()
    XCTAssertEqual(retriedRequests, [1, 2, 2, 3])
    attachScreen("通知-重试后连续加载完成", app: app)
    app.buttons["native-panel-close"].tap()
    try await setUIScenario("default")
  }

  /// 只操作当前面板的内容区域，每次拖动等待真实快照更新，不调用网页内部测试入口。
  private func scrollNotifications(
    _ panel: XCUIElement, to target: XCUIElement, upward: Bool = true
  ) {
    for _ in 0..<45 {
      if target.exists && target.isHittable { return }
      panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.85 : 0.22))
        .press(
          forDuration: 0.05,
          thenDragTo: panel.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.22 : 0.85)))
    }
    XCTAssertTrue(target.exists && target.isHittable, "连续滚动应到达目标通知或重试按钮")
  }

  /// 只读取本机夹具记录的分页序号，避免把同一 API 页重复请求误判为成功追加。
  private func notificationRequests() async throws -> [Int] {
    guard let value = ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_PROCESS_FIXTURE"],
      let fixture = URL(string: value), fixture.host == "127.0.0.1", fixture.scheme == "http"
    else { throw XCTSkip("连续通知验收需要本机分页夹具。") }
    let (data, _) = try await URLSession.shared.data(
      from: fixture.appendingPathComponent("__fixture/metrics"))
    let metrics = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    return try XCTUnwrap(metrics?["notificationRequests"] as? [Int])
  }

  /// 系统半屏展开不会改变前景动作的可用状态，保留同一网格的两种高度截图供颜色验收。
  func testNativeGridSheetExpansion() async throws {
    try await setUIScenario("default")
    let app = try signIn()
    settlePage(app)
    for title in ["捷径", "插件面板"] {
      app.buttons["操作菜单"].tap()
      app.buttons[title].firstMatch.tap()
      let panel = app.tables["native-quick-panel"]
      XCTAssertTrue(panel.waitForExistence(timeout: 8))
      settlePage(app)
      let first = panel.buttons.matching(
        NSPredicate(format: "identifier BEGINSWITH %@", "native-panel-item-")
      ).firstMatch
      XCTAssertTrue(first.isEnabled)
      let initialY = panel.frame.minY
      XCTAssertGreaterThan(initialY, app.frame.height * 0.35)
      attachScreen("交互-\(title)半屏文字亮度", app: app)
      let origin = app.coordinate(withNormalizedOffset: .zero)
      origin.withOffset(CGVector(dx: app.frame.width / 2, dy: initialY + 8)).press(
        forDuration: 0.1,
        thenDragTo: origin.withOffset(CGVector(dx: app.frame.width / 2, dy: 105)))
      let expanded = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in panel.frame.minY < initialY - 150 }, object: nil)
      XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 8), .completed)
      XCTAssertTrue(first.isEnabled)
      XCTAssertTrue(first.isHittable)
      attachScreen("交互-\(title)展开文字亮度", app: app)
      app.buttons["native-panel-close"].tap()
    }
  }

  /// 真实 Vue 重启确认由系统 alert 接管，验证完整正文和取消，不提交真实重启。
  func testNativeConfirmationKeepsMessageAndCancellation() throws {
    let app = try signIn()
    settlePage(app)
    app.buttons["操作菜单"].tap()
    nativeUserItem("用户", app: app).tap()
    let restart = nativeUserItem("重启", app: app)
    XCTAssertTrue(restart.waitForExistence(timeout: 8))
    restart.tap()
    let alert = app.alerts.firstMatch
    XCTAssertTrue(alert.waitForExistence(timeout: 10), "必须是系统确认框，不能再次打开 HTML Sheet")
    XCTAssertGreaterThanOrEqual(alert.staticTexts.count, 2, "标题和完整提示正文都应可见")
    XCTAssertTrue(alert.staticTexts["重启后，您将被注销并需要重新登录。"].exists)
    XCTAssertFalse(app.otherElements["native-web-sheet"].exists)
    attachScreen("交互-系统确认框完整正文", app: app)
    alert.buttons["取消"].tap()
    XCTAssertTrue(alert.waitForNonExistence(timeout: 8))
    XCTAssertTrue(app.tabBars["native-root-navigation"].exists)
    XCTAssertTrue(app.buttons["操作菜单"].isEnabled)
    attachScreen("交互-系统确认取消返回主页面", app: app)
  }

  /// 实际订阅卡片进入批量选择、编辑与文件统计，保留原业务回调但不保存或删除订阅。
  func testNativeSubscriptionBatchAndEditor() async throws {
    try await setUIScenario("subscription")
    let app = try signIn()
    openMorePage("电视剧订阅", app: app)
    let card = app.webViews.staticTexts.matching(
      NSPredicate(format: "label BEGINSWITH %@", "演示剧集")
    ).firstMatch
    XCTAssertTrue(card.waitForExistence(timeout: 15))
    let maintenance = app.buttons["native-bottom-action"]
    XCTAssertTrue(maintenance.waitForExistence(timeout: 8))
    attachScreen("交互-订阅动态按钮语义图标", app: app)
    maintenance.tap()
    XCTAssertTrue(app.buttons["更新订阅元数据"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["刷新订阅资源"].exists)
    XCTAssertTrue(app.buttons["默认订阅规则"].exists)
    attachScreen("交互-订阅维护菜单语义图标", app: app)
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.3)).tap()
    app.buttons["操作菜单"].tap()
    XCTAssertTrue(app.buttons["批量操作"].waitForExistence(timeout: 5))
    attachScreen("交互-订阅批量操作明确名称", app: app)
    app.buttons["批量操作"].tap()
    XCTAssertTrue(app.webViews.staticTexts["已选择 0/1 项"].waitForExistence(timeout: 8))
    card.tap()
    XCTAssertTrue(app.webViews.staticTexts["已选择 1/1 项"].waitForExistence(timeout: 8))
    attachScreen("交互-订阅批量选择状态", app: app)
    app.webViews.buttons["退出批量操作"].tap()
    XCTAssertTrue(app.webViews.staticTexts["已选择 1/1 项"].waitForNonExistence(timeout: 8))
    card.tap()
    XCTAssertTrue(app.navigationBars["编辑订阅"].waitForExistence(timeout: 12))
    XCTAssertTrue(app.buttons["native-sheet-close"].exists)
    XCTAssertTrue(app.webViews.staticTexts["搜索关键词"].exists)
    settlePage(app)
    attachScreen("交互-订阅编辑无空闲加载线", app: app)
    app.buttons["native-sheet-close"].tap()
    let cardMenu = app.webViews.descendants(matching: .any).matching(identifier: "更多").firstMatch
    XCTAssertTrue(cardMenu.waitForExistence(timeout: 8))
    cardMenu.tap()
    attachScreen("交互-订阅卡片原菜单", app: app)
    let statistics = app.webViews.staticTexts["文件统计"]
    if statistics.waitForExistence(timeout: 2) {
      statistics.tap()
    } else {
      // WebKit 返回同一 WebView 后偶尔不刷新传送菜单的无障碍树，按已核对的实际菜单行触控。
      app.webViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.63, dy: 0.716)).tap()
    }
    XCTAssertTrue(app.navigationBars["文件统计"].waitForExistence(timeout: 12))
    XCTAssertTrue(app.buttons["native-sheet-close"].exists)
    settlePage(app)
    attachScreen("交互-订阅文件统计原生标题", app: app)
    app.buttons["native-sheet-close"].tap()
    try await setUIScenario("default")
  }

  /// 多张真实进度卡片作为底页反复打开编辑，保留输入和返回位置，不保存订阅。
  func testNativePopulatedSubscriptionSheet() async throws {
    try await setUIScenario("subscription-grid")
    let app = try signIn()
    openMorePage("电视剧订阅", app: app)
    let card = app.webViews.staticTexts.matching(
      NSPredicate(format: "label BEGINSWITH %@", "演示剧集 01")
    ).firstMatch
    XCTAssertTrue(card.waitForExistence(timeout: 15))
    attachScreen("交互-多张订阅卡片与进度条底页", app: app)
    for cycle in 0..<3 {
      card.tap()
      XCTAssertTrue(app.navigationBars["编辑订阅"].waitForExistence(timeout: 12))
      XCTAssertTrue(app.webViews.staticTexts["总集数"].waitForExistence(timeout: 10))
      XCTAssertTrue(app.webViews.staticTexts["质量"].waitForExistence(timeout: 8))
      attachScreen("交互-多卡片订阅编辑-\(cycle)", app: app)
      app.buttons["native-sheet-close"].tap()
      XCTAssertTrue(app.navigationBars["电视剧订阅"].waitForExistence(timeout: 8))
      XCTAssertTrue(card.isHittable)
    }
    attachScreen("交互-订阅编辑关闭保留底页", app: app)
    try await setUIScenario("default")
  }

  /// 浏览父窗打开下载子窗并多次返回，验证只有当前内容可见且原列表不重载、不丢失。
  func testNativeNestedSheetRestoresParent() async throws {
    try await setUIScenario("nested")
    let app = try signIn()
    openMorePage("站点管理", app: app)
    let site = app.webViews.staticTexts["演示站点"].firstMatch
    XCTAssertTrue(site.waitForExistence(timeout: 15))
    // 名称紧邻导航滚动边缘；使用同一卡片的统计区域，避开打开站点网页的独立地址操作。
    let usage = app.webViews.staticTexts["0.00 B"].firstMatch
    XCTAssertTrue(usage.waitForExistence(timeout: 8))
    XCTAssertTrue(usage.isHittable)
    usage.tap()
    // WebKit 首次触控可能仅展开原卡片的悬停操作，等待后再点击同一入口，不注入弹窗状态。
    if !app.navigationBars["浏览"].waitForExistence(timeout: 2) { usage.tap() }
    let resource = app.webViews.staticTexts.matching(
      NSPredicate(format: "label BEGINSWITH %@", "MoviePilot Demo S01E01")
    ).firstMatch
    XCTAssertTrue(app.navigationBars["浏览"].waitForExistence(timeout: 12))
    XCTAssertTrue(resource.waitForExistence(timeout: 12))
    attachScreen("交互-嵌套弹窗浏览列表", app: app)
    for cycle in 0..<3 {
      resource.tap()
      XCTAssertTrue(app.navigationBars["确认下载"].waitForExistence(timeout: 10))
      XCTAssertTrue(app.webViews.buttons["开始下载"].exists)
      attachScreen("交互-嵌套确认下载-\(cycle)", app: app)
      app.buttons["native-sheet-close"].tap()
      attachScreen("交互-嵌套关闭子窗首帧-\(cycle)", app: app)
      XCTAssertTrue(app.navigationBars["浏览"].waitForExistence(timeout: 8))
      XCTAssertFalse(app.webViews.buttons["开始下载"].exists)
      XCTAssertTrue(resource.isHittable)
      attachScreen("交互-嵌套返回浏览无旧内容-\(cycle)", app: app)
    }
    app.buttons["native-sheet-close"].tap()
    XCTAssertTrue(site.waitForExistence(timeout: 8))
    try await setUIScenario("default")
  }

  /// 文件详情、处理中和识别结果连续使用原生弹层，关闭后目录保持原位。
  func testNativeFileDetailsHeader() async throws {
    try await setUIScenario("file")
    let app = try signIn()
    openMorePage("文件管理", app: app)
    let action = app.webViews.buttons["操作 MoviePilot Demo.S01E01.2026.1080p.WEB-DL.mkv"]
    XCTAssertTrue(action.waitForExistence(timeout: 15))
    action.tap()
    XCTAssertTrue(app.navigationBars["文件详情"].waitForExistence(timeout: 12))
    XCTAssertTrue(app.buttons["native-sheet-close"].isHittable)
    XCTAssertFalse(app.webViews.staticTexts["文件详情"].exists)
    settlePage(app)
    attachScreen("交互-文件详情单层标题与系统关闭", app: app)
    app.webViews.buttons["识别"].tap()
    let status = app.otherElements["native-progress-status"]
    XCTAssertTrue(status.waitForExistence(timeout: 8))
    XCTAssertFalse(app.buttons["native-sheet-close"].exists)
    XCTAssertTrue(app.progressIndicators["native-progress-value"].exists)
    attachScreen("交互-原生处理中紧凑弹层", app: app)
    XCTAssertTrue(app.navigationBars["识别结果"].waitForExistence(timeout: 15))
    XCTAssertTrue(
      app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "MoviePilot Demo"))
        .firstMatch.exists)
    settlePage(app)
    attachScreen("交互-媒体识别结果原生标题与关闭", app: app)
    app.buttons["native-sheet-close"].tap()
    XCTAssertTrue(action.waitForExistence(timeout: 8))
    try await setUIScenario("default")
  }

  /// 原版本历史的加载、空、短、长内容共用底部操作，不执行安装或更新。
  func testNativeVersionHistoryFooter() async throws {
    for scenario in ["history-loading", "history-empty", "history-short", "history-long"] {
      try await setUIScenario(scenario)
      let app = try signIn()
      openMorePage("插件", app: app)
      XCTAssertTrue(
        app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "演示插件"))
          .firstMatch.waitForExistence(timeout: 15))
      let menu = app.webViews.descendants(matching: .any).matching(identifier: "更多").firstMatch
      XCTAssertTrue(menu.waitForExistence(timeout: 8))
      menu.tap()
      let history = app.descendants(matching: .any).matching(identifier: "版本历史").firstMatch
      if history.waitForExistence(timeout: 2) {
        history.tap()
      } else {
        // iOS 27 的 WebKit 不总向 XCTest 暴露此菜单；按已截图确认的只读夹具行位触控原按钮。
        attachScreen("交互-版本历史原菜单", app: app)
        app.coordinate(withNormalizedOffset: .zero).withOffset(
          CGVector(dx: menu.frame.maxX - 74, dy: menu.frame.maxY + 8 + 48 * 6 + 24)
        ).tap()
      }
      XCTAssertTrue(app.buttons["native-sheet-close"].waitForExistence(timeout: 12))
      let update = app.webViews.buttons["更新到最新版本"]
      XCTAssertTrue(update.waitForExistence(timeout: 8))
      XCTAssertGreaterThan(update.frame.minY, app.frame.height - 160)
      XCTAssertLessThan(update.frame.maxY, app.frame.height - 20)
      attachScreen("交互-版本历史底部固定-\(scenario)", app: app)
      if scenario != "history-loading" {
        let close = app.buttons["native-sheet-close"]
        let initial = close.frame.minY
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: app.frame.width / 2, dy: initial - 12)).press(
          forDuration: 0.1,
          thenDragTo: origin.withOffset(CGVector(dx: app.frame.width / 2, dy: 80)))
        settlePage(app)
        XCTAssertGreaterThan(update.frame.minY, app.frame.height - 160)
        attachScreen("交互-版本历史展开底部固定-\(scenario)", app: app)
      }
      app.buttons["native-sheet-close"].tap()
      app.terminate()
    }
    try await setUIScenario("default")
  }

  /// 仅显式启用的本机夹具可切换只读展示数据，不在产品桥或生产实例增加测试入口。
  private func setUIScenario(_ scenario: String) async throws {
    guard let value = ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_PROCESS_FIXTURE"],
      let fixture = URL(string: value), fixture.host == "127.0.0.1", fixture.scheme == "http"
    else { throw XCTSkip("展示状态验收需要本机受控夹具。") }
    var request = URLRequest(url: fixture.appendingPathComponent("__fixture/scenario"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: ["scenario": scenario])
    let (_, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
  }

  /// 系统配色只由专用模拟器夹具改变，不给产品桥增加测试或主题切换后门。
  private func setSystemAppearance(_ appearance: String) async throws {
    guard let value = ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_PROCESS_FIXTURE"],
      let fixture = URL(string: value), fixture.host == "127.0.0.1", fixture.scheme == "http"
    else { throw XCTSkip("系统明暗验收需要本机受控夹具。") }
    var request = URLRequest(url: fixture.appendingPathComponent("__fixture/appearance"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: ["appearance": appearance])
    let (_, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
  }

  /// 推荐榜单返回与更多目录重复点击都以已确认 Router 位置为准。
  func testRankingBackAndMoreRoot() throws {
    let app = try signIn()
    let roots = app.tabBars["native-root-navigation"]
    roots.buttons["推荐"].tap()
    XCTAssertTrue(app.navigationBars["推荐"].waitForExistence(timeout: 10))
    settlePage(app)
    let ranking = app.webViews.links["更多"].firstMatch
    XCTAssertTrue(ranking.waitForExistence(timeout: 15), "夹具应包含可进入的真实榜单入口")
    ranking.tap()
    XCTAssertTrue(app.buttons["返回"].waitForExistence(timeout: 10))
    settlePage(app)
    attachScreen("交互-推荐榜单详情", app: app)
    app.buttons["返回"].tap()
    XCTAssertTrue(app.navigationBars["推荐"].waitForExistence(timeout: 10), "一次返回必须离开榜单")
    attachScreen("交互-榜单返回推荐", app: app)
    ranking.tap()
    XCTAssertTrue(app.buttons["返回"].waitForExistence(timeout: 10))
    roots.buttons["更多"].tap()
    XCTAssertTrue(app.tables["more-menu"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["返回"].exists)
    assertBottomLayout(app)
  }

  /// 榜单与更多往返后逐项真实点击底栏，覆盖同项连点与恢复入口最近业务页面的命中。
  func testRankingKeepsBottomNavigationResponsive() throws {
    let app = try signIn()
    let roots = app.tabBars["native-root-navigation"]
    for cycle in 1...4 {
      roots.buttons["推荐"].tap()
      if app.buttons["返回"].exists { app.buttons["返回"].tap() }
      XCTAssertTrue(app.navigationBars["推荐"].waitForExistence(timeout: 10))
      settlePage(app)
      let ranking = app.webViews.links["更多"].firstMatch
      XCTAssertTrue(ranking.waitForExistence(timeout: 15))
      ranking.tap()
      XCTAssertTrue(app.buttons["返回"].waitForExistence(timeout: 10))
      settlePage(app)
      let rankingTitle = app.navigationBars.firstMatch.identifier
      attachScreen("交互-榜单底栏连续切换-\(cycle)", app: app)
      for title in ["更多", "更多", "探索", "仪表盘", "推荐", "仪表盘"] {
        let button = roots.buttons[title]
        XCTAssertTrue(button.isEnabled && button.isHittable, "榜单离开后底栏须可点击：\(title)")
        button.tap()
        if title == "更多" {
          XCTAssertTrue(app.tables["more-menu"].waitForExistence(timeout: 10))
        } else {
          let expected = title == "推荐" ? rankingTitle : title
          XCTAssertTrue(app.navigationBars[expected].waitForExistence(timeout: 10))
        }
      }
    }
    assertBottomLayout(app)
    attachScreen("交互-榜单多次往返后底栏可用", app: app)
  }

  /// 更多默认只显示目录，下拉露出搜索；重新点击更多会清除筛选并再次收起。
  func testMoreSearchRevealsOnPullDown() throws {
    let app = try signIn()
    let more = app.tabBars["native-root-navigation"].buttons["更多"]
    more.tap()
    XCTAssertTrue(app.tables["more-menu"].waitForExistence(timeout: 10))
    let field = app.descendants(matching: .any)["more-menu-search"]
    XCTAssertFalse(field.isHittable, "默认不占用目录首屏")
    attachScreen("交互-更多默认收起搜索", app: app)
    let search = revealMoreSearch(app)
    attachScreen("交互-更多下拉显示搜索", app: app)
    search.tap()
    search.typeText("插件\n")
    XCTAssertTrue(
      app.tables["more-menu"].cells.containing(.staticText, identifier: "插件").firstMatch.exists)
    more.tap()
    XCTAssertFalse(field.isHittable, "再次进入更多恢复目录并收起搜索")
    XCTAssertTrue(
      app.tables["more-menu"].cells.containing(.staticText, identifier: "电影订阅").firstMatch.exists)
  }

  /// 动态按钮出现与消失只平移整组导航，不重新压缩主按钮与选中反馈。
  func testBottomNavigationKeepsItemGeometry() throws {
    let app = try signIn()
    app.tabBars["native-root-navigation"].buttons["更多"].tap()
    XCTAssertTrue(app.tables["more-menu"].waitForExistence(timeout: 10))
    settlePage(app)
    let bar = app.tabBars["native-root-navigation"]
    let initial = bar.buttons.allElementsBoundByIndex.map(\.frame)
    let width = bar.frame.width
    XCTAssertFalse(app.buttons["native-bottom-action"].exists)
    openMorePage("文件管理", app: app)
    XCTAssertTrue(app.buttons["native-bottom-action"].waitForExistence(timeout: 12))
    settlePage(app)
    assertBottomLayout(app)
    let dynamic = bar.buttons.allElementsBoundByIndex.map(\.frame)
    let geometry = XCTAttachment(
      string: "withoutAction=\(initial)\nwithAction=\(dynamic)\nbarWidth=\(width)")
    geometry.name = "底栏按钮实际几何"
    geometry.lifetime = .keepAlways
    add(geometry)
    XCTAssertEqual(bar.frame.width, width, accuracy: 1)
    for i in 1..<initial.count {
      XCTAssertEqual(
        dynamic[i].midX - dynamic[i - 1].midX,
        initial[i].midX - initial[i - 1].midX, accuracy: 1)
      XCTAssertGreaterThanOrEqual(dynamic[i].midX - dynamic[i - 1].midX, 60)
    }
    attachScreen("交互-固定间距底栏含动态动作", app: app)
    bar.buttons["更多"].tap()
    XCTAssertTrue(app.tables["more-menu"].waitForExistence(timeout: 10))
    settlePage(app)
    XCTAssertFalse(app.buttons["native-bottom-action"].exists)
    XCTAssertEqual(bar.frame.width, width, accuracy: 1)
    XCTAssertEqual(bar.frame.midX, app.frame.midX, accuracy: 1)
    attachScreen("交互-固定间距底栏整组居中", app: app)
  }

  /// 根页不响应侧滑，详情短滑不返回，完成侧滑只消费一次原路由返回。
  func testEdgeSwipeBackAndSheetDismissal() throws {
    let app = try signIn()
    app.tabBars["native-root-navigation"].buttons["推荐"].tap()
    XCTAssertTrue(app.navigationBars["推荐"].waitForExistence(timeout: 10))
    settlePage(app)
    let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.55))
    let finish = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.55))
    edge.press(forDuration: 0.1, thenDragTo: finish)
    XCTAssertTrue(app.navigationBars["推荐"].exists, "根页没有可消费的返回栈")
    let ranking = app.webViews.links["更多"].firstMatch
    XCTAssertTrue(ranking.waitForExistence(timeout: 15))
    ranking.tap()
    XCTAssertTrue(app.buttons["返回"].waitForExistence(timeout: 10))
    settlePage(app)
    let title = app.navigationBars.firstMatch.identifier
    edge.press(
      forDuration: 0.1,
      thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.55)))
    XCTAssertTrue(app.navigationBars[title].exists, "短滑不能返回或触发业务动作")
    XCTAssertTrue(app.buttons["返回"].exists)
    edge.press(forDuration: 0.1, thenDragTo: finish)
    XCTAssertTrue(app.navigationBars["推荐"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["返回"].exists)
    attachScreen("交互-左边缘侧滑返回推荐", app: app)
    app.buttons["操作菜单"].tap()
    app.buttons["捷径"].firstMatch.tap()
    let panel = app.tables["native-quick-panel"]
    XCTAssertTrue(panel.waitForExistence(timeout: 8))
    panel.buttons["native-panel-item-nameTest"].tap()
    let close = app.buttons["native-sheet-close"]
    XCTAssertTrue(close.waitForExistence(timeout: 12))
    edge.press(forDuration: 0.1, thenDragTo: finish)
    XCTAssertTrue(close.waitForNonExistence(timeout: 10), "业务弹窗优先消费侧滑关闭")
    XCTAssertTrue(app.navigationBars["推荐"].exists, "关闭弹窗不能跳过其下的页面")
    attachScreen("交互-左边缘侧滑关闭业务弹窗", app: app)
  }

  /// 慢速拖动并停留，视频可核对中间帧；短滑回弹后仍能连续完成同一页面的返回。
  func testInteractiveBackCardCancellationAndCompletion() throws {
    let app = try signIn()
    app.tabBars["native-root-navigation"].buttons["推荐"].tap()
    XCTAssertTrue(app.navigationBars["推荐"].waitForExistence(timeout: 10))
    settlePage(app)
    for cycle in 0..<2 {
      let ranking = app.webViews.links["更多"].firstMatch
      XCTAssertTrue(ranking.waitForExistence(timeout: 15))
      ranking.tap()
      XCTAssertTrue(app.buttons["返回"].waitForExistence(timeout: 10))
      settlePage(app)
      let title = app.navigationBars.firstMatch.identifier
      let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.55))
      edge.press(
        forDuration: 0.1,
        thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.24, dy: 0.55)),
        withVelocity: .slow, thenHoldForDuration: 1.5)
      XCTAssertTrue(app.navigationBars[title].exists, "松手位移不足时只回弹，不提前切换网页")
      XCTAssertTrue(app.buttons["返回"].exists)
      XCTAssertFalse(app.otherElements["native-back-transition"].exists)
      attachScreen("交互-跟手卡片取消-\(cycle + 1)", app: app)
      edge.press(
        forDuration: 0.1,
        thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.64, dy: 0.55)),
        withVelocity: .slow, thenHoldForDuration: 1.5)
      XCTAssertTrue(app.navigationBars["推荐"].waitForExistence(timeout: 10))
      XCTAssertFalse(app.buttons["返回"].exists)
      XCTAssertFalse(app.otherElements["native-back-transition"].exists)
      attachScreen("交互-跟手卡片完成-\(cycle + 1)", app: app)
    }
  }

  /// 系统搜索选择类型后仍使用前端既有路由和来源参数，捷径仍打开原业务弹窗。
  func testNativeSearchAndShortcutActions() throws {
    let app = try signIn()
    app.buttons["操作菜单"].tap()
    app.buttons["搜索"].firstMatch.tap()
    let panel = app.tables["native-quick-panel"]
    XCTAssertTrue(panel.waitForExistence(timeout: 8))
    let field = app.searchFields["native-panel-search-field"]
    field.tap()
    field.typeText("示例\n")
    let media = panel.cells["native-panel-item-media-media"]
    XCTAssertTrue(media.waitForExistence(timeout: 8))
    media.tap()
    let run = app.buttons["native-panel-primary-action"]
    XCTAssertTrue(run.waitForExistence(timeout: 5))
    XCTAssertTrue(run.isHittable, "搜索必须是无需滚动即可点击的原生按钮")
    XCTAssertEqual(run.label, "搜索")
    XCTAssertFalse(panel.cells["native-panel-item-run-media"].exists)
    attachScreen("交互-原生搜索来源选择", app: app)
    run.tap()
    let result = app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS %@", "示例"))
      .firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 15), "系统搜索必须进入原 HTML 搜索结果")
    XCTAssertFalse(panel.exists)
    app.buttons["返回"].tap()
    let originalTitle = app.navigationBars.firstMatch.identifier
    app.buttons["操作菜单"].tap()
    app.buttons["捷径"].firstMatch.tap()
    XCTAssertTrue(panel.waitForExistence(timeout: 8))
    panel.buttons["native-panel-item-nameTest"].tap()
    XCTAssertTrue(app.buttons["native-sheet-close"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.webViews.staticTexts["识别数据源"].waitForExistence(timeout: 10))
    let input = app.webViews.textViews.firstMatch
    XCTAssertTrue(input.exists, "捷径应打开原名称识别输入表单")
    attachScreen("交互-原生捷径打开业务弹窗", app: app)
    input.tap()
    input.typeText("MoviePilot Demo (2026)")
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    XCTAssertTrue((input.value as? String)?.contains("MoviePilot Demo (2026)") == true)
    attachScreen("交互-原生业务弹窗软键盘", app: app)
    dismissOverlays(app)
    XCTAssertTrue(app.navigationBars[originalTitle].waitForExistence(timeout: 8))
    XCTAssertFalse(app.keyboards.firstMatch.exists, "原生关闭应结束原 HTML 输入并恢复原页面")
  }

  /// 三个快捷工具复用真实 HTML 表单，验收明暗系统弹层中的输入、结果、分类和固定保存栏。
  func testNativeToolSheetDesign() async throws {
    guard let server = ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_TOOL_SERVER"],
      server == "http://127.0.0.1:5237"
    else { throw XCTSkip("工具弹层验收需要独立本机合成夹具。") }
    let app = try launchLogin(server: server)
    authenticateFixture(app, remember: false)
    XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 30))
    for mode in ["dark", "light"] {
      try await setSystemAppearance(mode)
      for tool in ["nameTest", "ruleTest", "words"] {
        app.buttons["操作菜单"].tap()
        app.buttons["捷径"].firstMatch.tap()
        let panel = app.tables["native-quick-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        panel.buttons["native-panel-item-\(tool)"].tap()
        XCTAssertTrue(app.buttons["native-sheet-close"].waitForExistence(timeout: 10))
        settlePage(app)
        let web = app.webViews.firstMatch
        if tool == "words" {
          let save = web.buttons["保存更改"]
          XCTAssertTrue(save.waitForExistence(timeout: 10))
          XCTAssertLessThan(save.frame.maxY, app.frame.maxY, "保存操作必须保留在弹层底部安全区内")
          attachScreen("交互-\(mode)词表分段与统一底色", app: app)
          let format = web.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "支持的配置格式")
          ).firstMatch
          XCTAssertTrue(format.waitForExistence(timeout: 5))
          format.tap()
          settlePage(app)
          attachScreen("交互-\(mode)词表配置说明展开", app: app)
          web.buttons["集数规则"].tap()
          XCTAssertTrue(
            web.textFields.matching(NSPredicate(format: "value == %@", "标准集数"))
              .firstMatch.waitForExistence(timeout: 8))
          attachScreen("交互-\(mode)词表规则平面布局", app: app)
        } else {
          let input = tool == "nameTest" ? web.textViews.firstMatch : web.textFields.firstMatch
          XCTAssertTrue(input.waitForExistence(timeout: 10))
          input.tap()
          if !app.keyboards.firstMatch.waitForExistence(timeout: 2) { input.tap() }
          XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
          input.typeText("MoviePilot.Demo.S01E03.2160p.WEB-DL")
          // 选择已有来源或规则组，按真实表单交互结束文本输入并继续提交。
          let selected = tool == "nameTest" ? "TheMovieDB" : "请选择"
          let choice = tool == "nameTest" ? "TheMovieDB" : "高清优先"
          web.staticTexts[selected].firstMatch.tap()
          let option = web.otherElements.matching(identifier: choice)
          XCTAssertTrue(option.firstMatch.waitForExistence(timeout: 8))
          option.allElementsBoundByIndex.last?.tap()
          web.buttons[tool == "nameTest" ? "识别" : "测试"].tap()
          let result = web.staticTexts[tool == "nameTest" ? "星际漫游" : "命中过滤规则"].firstMatch
          XCTAssertTrue(result.waitForExistence(timeout: 15))
          for _ in 0..<5 where !result.isHittable { web.swipeUp(velocity: .slow) }
          XCTAssertTrue(result.isHittable)
          attachScreen("交互-\(mode)\(tool)统一结果布局", app: app)
        }
        app.buttons["native-sheet-close"].tap()
        XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 10))
      }
    }
    try await setSystemAppearance("dark")
  }

  /// 从真实捷径入口检查词表横向命中区域及日志标题/菜单，避免只检查页面的滚动宽度。
  func testNativeWordsWidthAndLogTitle() async throws {
    guard let server = ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_TOOL_SERVER"],
      server == "http://127.0.0.1:5237"
    else { throw XCTSkip("工具布局回归验收需要独立本机合成夹具。") }
    let app = try launchLogin(server: server)
    authenticateFixture(app, remember: false)
    XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 30))
    /// 仅通过注册的原生捷径动作打开原 Vue 内容，不增加测试专用页面入口。
    func openShortcut(_ name: String) {
      app.buttons["操作菜单"].tap()
      app.buttons["捷径"].firstMatch.tap()
      let panel = app.tables["native-quick-panel"]
      XCTAssertTrue(panel.waitForExistence(timeout: 8))
      panel.buttons["native-panel-item-\(name)"].tap()
      XCTAssertTrue(app.buttons["native-sheet-close"].waitForExistence(timeout: 10))
      settlePage(app)
    }
    for mode in ["dark", "light"] {
      try await setSystemAppearance(mode)
      openShortcut("words")
      let web = app.webViews.firstMatch
      let save = web.buttons["保存更改"]
      XCTAssertTrue(save.waitForExistence(timeout: 10))
      XCTAssertTrue(save.isHittable)
      XCTAssertGreaterThanOrEqual(save.frame.minX, web.frame.minX)
      XCTAssertLessThanOrEqual(save.frame.maxX, web.frame.maxX)
      XCTAssertLessThan(save.frame.maxY, app.frame.maxY)
      for title in ["识别词", "制作组", "占位符", "屏蔽词", "集数规则"] {
        let tab = web.buttons[title]
        XCTAssertTrue(tab.isHittable)
        XCTAssertGreaterThanOrEqual(tab.frame.minX, web.frame.minX)
        XCTAssertLessThanOrEqual(tab.frame.maxX, web.frame.maxX)
      }
      if mode == "dark" { attachScreen("修复-词表深色完整宽度", app: app) }
      web.buttons["集数规则"].tap()
      let add = web.buttons["新增规则"]
      XCTAssertTrue(add.waitForExistence(timeout: 8))
      XCTAssertTrue(add.isHittable)
      XCTAssertLessThanOrEqual(add.frame.maxX, web.frame.maxX)
      XCTAssertLessThanOrEqual(save.frame.maxX, web.frame.maxX)
      if mode == "light" { attachScreen("修复-词表浅色集数规则", app: app) }
      app.buttons["native-sheet-close"].tap()
      XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 10))
      openShortcut("logging")
      XCTAssertTrue(app.staticTexts["实时日志"].firstMatch.waitForExistence(timeout: 8))
      let menu = app.buttons["native-sheet-menu"]
      XCTAssertTrue(menu.isHittable)
      if mode == "dark" { attachScreen("修复-实时日志独立标题", app: app) }
      menu.tap()
      XCTAssertTrue(app.buttons["下载"].firstMatch.waitForExistence(timeout: 5))
      XCTAssertTrue(app.buttons["在新窗口中打开"].firstMatch.exists)
      if mode == "dark" { attachScreen("修复-实时日志原生操作菜单", app: app) }
      app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88)).tap()
      app.buttons["native-sheet-close"].tap()
      XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 10))
    }
    try await setSystemAppearance("dark")
  }

  /// 连续打开关闭原表单保留底页滚动位置，真实文档请求计数不能增加。
  func testWebSheetPreservesPageAcrossRepeatedTransitions() async throws {
    guard let value = ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_PROCESS_FIXTURE"],
      let fixture = URL(string: value), fixture.host == "127.0.0.1", fixture.scheme == "http"
    else { throw XCTSkip("连续转场验收需要本机文档计数夹具。") }
    /// 读取独立代理的顶层 HTML 请求计数，不使用生产页面内的测试钩子。
    func documentLoads() async throws -> Int {
      let (data, _) = try await URLSession.shared.data(
        from: fixture.appendingPathComponent("__fixture/metrics"))
      let metrics = try JSONSerialization.jsonObject(with: data) as? [String: Int]
      return try XCTUnwrap(metrics?["documentLoads"])
    }
    let app = try signIn()
    app.tabBars["native-root-navigation"].buttons["仪表盘"].tap()
    settlePage(app)
    app.webViews.firstMatch.swipeUp()
    settlePage(app)
    let marker = app.webViews.staticTexts["媒体统计"].firstMatch
    XCTAssertTrue(marker.exists)
    let position = marker.frame.minY
    let requests = try await documentLoads()
    attachScreen("交互-连续弹窗前主页面滚动位置", app: app)
    for index in 1...3 {
      app.buttons["操作菜单"].tap()
      app.buttons["捷径"].firstMatch.tap()
      let panel = app.tables["native-quick-panel"]
      XCTAssertTrue(panel.waitForExistence(timeout: 8))
      panel.buttons["native-panel-item-nameTest"].tap()
      let close = app.buttons["native-sheet-close"]
      XCTAssertTrue(close.waitForExistence(timeout: 12))
      XCTAssertTrue(app.webViews.staticTexts["识别数据源"].waitForExistence(timeout: 8))
      attachScreen("交互-连续弹窗内容-\(index)", app: app)
      close.tap()
      XCTAssertTrue(close.waitForNonExistence(timeout: 10))
      XCTAssertTrue(app.navigationBars["仪表盘"].exists)
      XCTAssertFalse(app.otherElements["native-startup-screen"].exists)
      XCTAssertEqual(marker.frame.minY, position, accuracy: 2, "关闭弹窗须保留底页滚动位置")
      let currentRequests = try await documentLoads()
      XCTAssertEqual(currentRequests, requests, "转场不能重新加载主文档")
      attachScreen("交互-连续弹窗关闭后主页面-\(index)", app: app)
    }
  }

  /// 插件图标网格支持长按固定，普通点击直接进入原 HTML 详情而非额外的列表菜单。
  func testNativePluginGridActions() throws {
    let app = try signIn()
    app.buttons["操作菜单"].tap()
    app.buttons["插件面板"].firstMatch.tap()
    let panel = app.tables["native-quick-panel"]
    XCTAssertTrue(panel.waitForExistence(timeout: 8))
    let tile = panel.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "native-panel-item-plugin-")
    ).firstMatch
    XCTAssertTrue(tile.waitForExistence(timeout: 10))
    let identifier = tile.identifier
    tile.press(forDuration: 1)
    let pin = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "固定 ", "取消固定 ")
    ).firstMatch
    XCTAssertTrue(pin.waitForExistence(timeout: 5))
    attachScreen("交互-插件网格长按操作", app: app)
    pin.tap()
    XCTAssertTrue(panel.waitForExistence(timeout: 5), "固定操作保留网格")
    let current = panel.buttons[identifier]
    XCTAssertTrue(current.waitForExistence(timeout: 5))
    current.tap()
    XCTAssertTrue(app.buttons["native-sheet-close"].waitForExistence(timeout: 12))
    XCTAssertFalse(panel.exists, "点击插件直接打开原业务详情")
    attachScreen("交互-插件网格打开原详情", app: app)
    app.buttons["native-sheet-close"].tap()
    XCTAssertTrue(app.buttons["操作菜单"].waitForExistence(timeout: 8))
  }

  /// 每种媒体搜索在选择来源后保留固定按钮，返回一级菜单时移除旧分类按钮。
  func testNativeSearchPrimaryActionForEveryMediaType() throws {
    let app = try signIn()
    for type in ["media", "music", "collection", "person"] {
      app.buttons["操作菜单"].tap()
      app.buttons["搜索"].firstMatch.tap()
      let panel = app.tables["native-quick-panel"]
      XCTAssertTrue(panel.waitForExistence(timeout: 8))
      let field = app.searchFields["native-panel-search-field"]
      field.tap()
      if let current = field.value as? String, current != field.placeholderValue, !current.isEmpty {
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
      }
      field.typeText("示例\n")
      let category = panel.cells["native-panel-item-media-\(type)"]
      XCTAssertTrue(category.waitForExistence(timeout: 8))
      let categoryTitle = category.staticTexts.element(boundBy: 0).label
      category.tap()
      let run = app.buttons["native-panel-primary-action"]
      XCTAssertTrue(run.waitForExistence(timeout: 5))
      XCTAssertTrue(run.isHittable)
      XCTAssertEqual(run.label, "搜索")
      let source = panel.cells.matching(
        NSPredicate(format: "identifier BEGINSWITH %@", "native-panel-item-source-\(type)-")
      ).firstMatch
      XCTAssertTrue(source.exists)
      source.tap()
      XCTAssertTrue(run.isHittable, "选择来源不得提前搜索或隐藏按钮")
      attachScreen("交互-原生\(type)搜索按钮", app: app)
      app.navigationBars[categoryTitle].buttons.element(boundBy: 0).tap()
      XCTAssertTrue(field.waitForExistence(timeout: 5))
      XCTAssertFalse(run.exists, "一级搜索不能残留上一分类的提交按钮")
      category.tap()
      XCTAssertTrue(run.waitForExistence(timeout: 5))
      run.tap()
      XCTAssertTrue(
        NSPredicate(format: "exists == false").evaluate(with: panel)
          || panel.waitForNonExistence(timeout: 15))
      XCTAssertTrue(app.buttons["返回"].waitForExistence(timeout: 10))
      app.buttons["返回"].tap()
      XCTAssertTrue(app.buttons["操作菜单"].waitForExistence(timeout: 10))
    }
  }

  /// 显式启用受控勋章夹具时，关闭按钮必须位于弹窗内部右上角且可以完成关闭。
  func testCommunityMedalClosePlacement() throws {
    guard ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_MEDALS"] == "1" else {
      throw XCTSkip("勋章位置验收需要启用受控社区资料夹具。")
    }
    let app = try signIn()
    app.buttons["操作菜单"].tap()
    nativeUserItem("用户", app: app).tap()
    let medals = nativeUserItem("我的勋章", app: app)
    XCTAssertTrue(medals.waitForExistence(timeout: 8))
    XCTAssertTrue(medals.exists, "受控夹具必须实际展示社区勋章入口，不能跳过验收")
    medals.tap()
    let close = app.buttons["native-sheet-close"]
    XCTAssertTrue(close.waitForExistence(timeout: 10))
    XCTAssertGreaterThan(close.frame.minY, 35)
    XCTAssertLessThan(close.frame.maxY, 155)
    XCTAssertGreaterThan(close.frame.minX, app.frame.width - 80)
    attachScreen("交互-社区勋章关闭位置", app: app)
    close.tap()
    XCTAssertTrue(app.tabBars["native-root-navigation"].buttons["更多"].waitForExistence(timeout: 8))
  }

  /// 采集不含凭据的竖屏账户界面与软键盘，由运行配置选择系统明暗外观。
  func testCaptureAccountLayout() throws {
    guard ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_CAPTURE"] == "1" else {
      throw XCTSkip("只在私有截图运行中采集。")
    }
    let app = try launchLogin()
    app.textFields["用户名"].tap()
    attachScreen("框架-空白登录键盘", app: app)
    app.secureTextFields["密码"].tap()
    XCTAssertTrue(app.buttons["显示密码"].exists)
    app.buttons["显示密码"].tap()
    XCTAssertTrue(app.buttons["隐藏密码"].exists)
    attachScreen("框架-密码可见切换", app: app)
    app.buttons["隐藏密码"].tap()
  }

  /// 旋转单独运行并保留原图，节点结果不能替代横屏内容裁切的视觉检查。
  func testCaptureAccountRotation() throws {
    guard ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_CAPTURE"] == "1" else {
      throw XCTSkip("只在私有旋转验收中采集。")
    }
    let app = try launchLogin()
    app.secureTextFields["密码"].tap()
    XCUIDevice.shared.orientation = .landscapeLeft
    settlePage(app)
    XCTAssertGreaterThan(app.frame.width, app.frame.height, "等待 App 完成横屏布局")
    attachScreen("框架-登录横屏与键盘", app: app)
    let hierarchy = XCTAttachment(string: app.debugDescription)
    hierarchy.name = "框架-空白横屏登录布局"
    hierarchy.lifetime = .keepAlways
    add(hierarchy)
    let field = app.secureTextFields["密码"]
    let viewport = app.scrollViews.firstMatch.frame
    XCTAssertTrue(field.isHittable, "旋转后当前输入框仍可操作")
    XCTAssertGreaterThanOrEqual(field.frame.minY, viewport.minY, "输入框上沿不能藏在导航栏后")
    XCTAssertLessThanOrEqual(field.frame.maxY, viewport.maxY, "输入框下沿不能超出可见滚动区域")
    XCUIDevice.shared.orientation = .portrait
  }

  /// 用户手动滚动仍能触达原生登录操作，键盘避让不能将滚动位置拉回。
  func testAccountKeyboardAllowsManualScroll() async throws {
    let server = try await prepareNativeOnlyFixture(mode: "healthy")
    let app = try launchLogin(server: server)
    app.secureTextFields["密码"].tap()
    XCUIDevice.shared.orientation = .landscapeLeft
    defer { XCUIDevice.shared.orientation = .portrait }
    settlePage(app)
    let login = app.buttons["登录"]
    for _ in 0..<6 {
      if login.isHittable { break }
      app.scrollViews.firstMatch.swipeUp()
    }
    XCTAssertTrue(login.isHittable, "手动滚动不能被输入框自动定位拉回")
    XCTAssertFalse(app.buttons["使用网页登录"].exists)
  }

  /// 真实 WK 卡片长按触发系统上下文菜单，取消和打开文件统计不遗留 HTML 菜单。
  func testNativeCardContextMenu() async throws {
    guard let server = ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_CARD_MENU_SERVER"],
      server == "http://127.0.0.1:5247"
    else { throw XCTSkip("卡片长按需要独立本机合成夹具。") }
    try await cardMenuControl("reset")
    let app = try launchCardMenuApp(server: server)
    XCTAssertTrue(app.navigationBars["电视剧订阅"].waitForExistence(timeout: 30))
    XCTAssertTrue(app.otherElements["native-startup-screen"].waitForNonExistence(timeout: 15))
    let card = try await cardMenuPoint(app)
    card.tap()
    XCTAssertTrue(app.navigationBars["编辑订阅"].waitForExistence(timeout: 10), "短按保留原编辑动作")
    app.buttons["native-sheet-close"].tap()
    XCTAssertTrue(app.navigationBars["电视剧订阅"].waitForExistence(timeout: 8))
    let first = try await cardMenuPoint(app)
    first.press(forDuration: 1)
    XCTAssertTrue(app.buttons["文件统计"].waitForExistence(timeout: 8), app.debugDescription)
    XCTAssertTrue(app.buttons["取消订阅"].exists)
    var state = try await cardMenuState()
    let page = try XCTUnwrap(state["page"] as? [String: Any])
    XCTAssertEqual(page["htmlMenus"] as? Int, 0)
    XCTAssertEqual(page["selection"] as? String, "")
    attachScreen("卡片-系统长按菜单与真实预览", app: app)
    app.coordinate(withNormalizedOffset: .init(dx: 0.02, dy: 0.12)).tap()
    XCTAssertTrue(app.buttons["文件统计"].waitForNonExistence(timeout: 8))
    let second = try await cardMenuPoint(app)
    second.press(forDuration: 1)
    XCTAssertTrue(app.buttons["文件统计"].waitForExistence(timeout: 8))
    app.buttons["文件统计"].tap()
    XCTAssertTrue(app.navigationBars["文件统计"].waitForExistence(timeout: 12))
    state = try await cardMenuState()
    XCTAssertEqual(
      (state["requests"] as? [String])?.filter { $0 == "/api/v1/subscribe/files/2501" }.count, 1)
    attachScreen("卡片-长按动作交接文件统计", app: app)
    app.buttons["native-sheet-close"].tap()
    XCTAssertTrue(app.navigationBars["电视剧订阅"].waitForExistence(timeout: 8))
    app.tabBars["native-root-navigation"].buttons["仪表盘"].tap()
    XCTAssertTrue(app.navigationBars["仪表盘"].waitForExistence(timeout: 8))
    XCTAssertFalse(app.buttons["文件统计"].exists)
  }

  /// 滚动、后台和旋转撤销系统菜单；辅助入口使用同一原生动作与受限高度。
  func testNativeCardContextLifecycleAndAccessibleMenu() async throws {
    guard
      ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_CARD_MENU_SERVER"]
        == "http://127.0.0.1:5247"
    else { throw XCTSkip("卡片菜单生命周期需要独立本机夹具。") }
    try await cardMenuControl("reset")
    let app = try launchCardMenuApp(server: "http://127.0.0.1:5247")
    XCTAssertTrue(app.navigationBars["电视剧订阅"].waitForExistence(timeout: 30))
    XCTAssertTrue(app.otherElements["native-startup-screen"].waitForNonExistence(timeout: 15))
    let initial = try await cardMenuPoint(app)
    initial.press(forDuration: 0.1, thenDragTo: initial.withOffset(.init(dx: 0, dy: -200)))
    XCTAssertFalse(app.buttons["文件统计"].exists, "拖动只滚动页面，不打开长按菜单")
    let afterScroll = try await cardMenuPoint(app)
    afterScroll.press(forDuration: 1)
    XCTAssertTrue(app.buttons["文件统计"].waitForExistence(timeout: 8))
    XCUIDevice.shared.press(.home)
    app.activate()
    XCTAssertTrue(app.buttons["文件统计"].waitForNonExistence(timeout: 8))
    let resumed = try await cardMenuPoint(app)
    resumed.press(forDuration: 1)
    XCTAssertTrue(app.buttons["文件统计"].waitForExistence(timeout: 8))
    XCUIDevice.shared.orientation = .landscapeLeft
    XCTAssertTrue(app.buttons["文件统计"].waitForNonExistence(timeout: 8))
    XCUIDevice.shared.orientation = .portrait
    _ = try await cardMenuPoint(app)
    // 夹具只激活页面中真实无障碍按钮的 DOM click；不冒充 VoiceOver 语音或硬件验收。
    try await cardMenuControl("command", value: ["command": "accessible"])
    let table = app.tables["nativeOperationMenu"]
    XCTAssertTrue(table.waitForExistence(timeout: 8))
    let sheet = app.otherElements["native-operation-menu-sheet"]
    XCTAssertTrue(sheet.exists)
    XCTAssertLessThanOrEqual(sheet.frame.height, app.frame.height * 2 / 3 + 2)
    attachScreen("卡片-辅助操作原生列表与高度", app: app)
    let statistics = table.cells.containing(.staticText, identifier: "文件统计").firstMatch
    for _ in 0..<4 {
      if statistics.isHittable { break }
      table.swipeUp()
    }
    XCTAssertTrue(statistics.isHittable)
    statistics.tap()
    XCTAssertTrue(app.navigationBars["文件统计"].waitForExistence(timeout: 12))
    XCTAssertFalse(table.exists, "业务弹窗出现时系统操作列表必须已退出")
    app.buttons["native-sheet-close"].tap()
    XCTAssertTrue(app.navigationBars["电视剧订阅"].waitForExistence(timeout: 8))
  }

  /// 插件高级操作保持原来的二级位置，系统菜单和辅助列表均不触发业务写入。
  func testNativeCardNestedPluginMenu() async throws {
    guard
      ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_CARD_MENU_SERVER"]
        == "http://127.0.0.1:5247"
    else { throw XCTSkip("插件卡片菜单需要独立本机合成夹具。") }
    try await cardMenuControl("reset")
    let app = try launchCardMenuApp(server: "http://127.0.0.1:5247")
    XCTAssertTrue(app.navigationBars["电视剧订阅"].waitForExistence(timeout: 30))
    try await cardMenuControl("command", value: ["command": "plugins"])
    XCTAssertTrue(app.navigationBars["插件"].waitForExistence(timeout: 12))
    let card = try await cardMenuPoint(app)
    card.press(forDuration: 1)
    let advanced = app.buttons["高级操作"]
    XCTAssertTrue(advanced.waitForExistence(timeout: 8), app.debugDescription)
    XCTAssertLessThan(app.buttons["查看数据"].frame.minY, advanced.frame.minY)
    XCTAssertLessThan(advanced.frame.minY, app.buttons["设置"].frame.minY)
    advanced.tap()
    for title in ["运行能力", "数据诊断", "实例管理", "重新加载"] {
      XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 5), title)
    }
    XCTAssertLessThan(app.buttons["运行能力"].frame.minY, app.buttons["重新加载"].frame.minY)
    attachScreen("卡片-插件原生二级菜单", app: app)
    app.coordinate(withNormalizedOffset: .init(dx: 0.02, dy: 0.12)).tap()
    XCTAssertTrue(app.buttons["重新加载"].waitForNonExistence(timeout: 8))
    try await cardMenuControl("command", value: ["command": "accessible"])
    let table = app.tables["nativeOperationMenu"]
    XCTAssertTrue(table.waitForExistence(timeout: 8))
    table.cells.containing(.staticText, identifier: "高级操作").firstMatch.tap()
    XCTAssertTrue(table.cells.containing(.staticText, identifier: "运行能力").firstMatch.exists)
    XCTAssertTrue(table.cells.containing(.staticText, identifier: "重新加载").firstMatch.exists)
    app.buttons["返回上一级菜单"].tap()
    XCTAssertTrue(table.cells.containing(.staticText, identifier: "高级操作").firstMatch.exists)
    app.buttons["native-operation-menu-close"].tap()
    XCTAssertTrue(table.waitForNonExistence(timeout: 8))
    let state = try await cardMenuState()
    XCTAssertEqual((state["writes"] as? [String])?.filter { $0 != "/api/v1/notification/app" }, [])
    XCTAssertFalse(app.staticTexts["暂时无法打开 MoviePilot"].exists)
  }

  /// 点击真实文件存储激活器后用系统短列表呈现，关闭重开及原目录回调均只执行一次。
  func testNativeStandaloneShortMenu() async throws {
    try requireStandaloneFixture()
    try await standaloneControl("reset", value: ["variant": "short"])
    let app = try launchCardMenuApp(server: "http://127.0.0.1:5248")
    XCTAssertTrue(app.navigationBars["文件管理"].waitForExistence(timeout: 30))
    try await standalonePoint(app).tap()
    let table = app.tables["nativeOperationMenu"]
    XCTAssertTrue(table.waitForExistence(timeout: 8), app.debugDescription)
    XCTAssertEqual(table.cells.count, 3)
    XCTAssertFalse(table.cells.containing(.staticText, identifier: "本地").firstMatch.isEnabled)
    XCTAssertLessThan(
      table.cells.containing(.staticText, identifier: "本地").firstMatch.frame.minY,
      table.cells.containing(.staticText, identifier: "合成云盘 01").firstMatch.frame.minY)
    assertStandaloneHeight(app)
    XCTAssertLessThan(
      app.otherElements["native-operation-menu-sheet"].frame.height, app.frame.height * 0.55)
    let before = try await standaloneState()
    XCTAssertEqual((before["page"] as? [String: Any])?["htmlMenus"] as? Int, 0)
    attachScreen("独立菜单-短列表与原禁用状态", app: app)
    app.buttons["native-operation-menu-close"].tap()
    XCTAssertTrue(table.waitForNonExistence(timeout: 8))
    try await standalonePoint(app).tap()
    XCTAssertTrue(table.waitForExistence(timeout: 8))
    table.cells.containing(.staticText, identifier: "合成云盘 01").firstMatch.tap()
    XCTAssertTrue(table.waitForNonExistence(timeout: 8))
    _ = try await standalonePoint(app, title: "合成云盘 01")
    let after = try await standaloneState()
    XCTAssertEqual(
      (after["lists"] as? [[String: Any]])?.filter { $0["storage"] as? String == "cloud01" }.count,
      1)
    XCTAssertEqual((after["page"] as? [String: Any])?["htmlMenus"] as? Int, 0)
    XCTAssertFalse(app.staticTexts["暂时无法打开 MoviePilot"].exists)
  }

  /// 长菜单最多三分之二屏并可滚动到底；旋转、后台、来源隐藏和导航不会留下旧票据。
  func testNativeStandaloneLongMenuAndLifecycle() async throws {
    try requireStandaloneFixture()
    try await standaloneControl("reset", value: ["variant": "long"])
    let app = try launchCardMenuApp(server: "http://127.0.0.1:5248")
    XCTAssertTrue(app.navigationBars["文件管理"].waitForExistence(timeout: 30))
    try await standalonePoint(app).tap()
    let table = app.tables["nativeOperationMenu"]
    XCTAssertTrue(table.waitForExistence(timeout: 8))
    assertStandaloneHeight(app)
    attachScreen("独立菜单-长列表受限高度", app: app)
    let last = table.cells.containing(.staticText, identifier: "合成云盘 39").firstMatch
    for _ in 0..<15 {
      if last.isHittable { break }
      table.swipeUp()
    }
    XCTAssertTrue(last.isHittable, "最高受限后末项仍须通过内部滚动可达")
    last.tap()
    XCTAssertTrue(table.waitForNonExistence(timeout: 8))
    _ = try await standalonePoint(app, title: "合成云盘 39")
    var state = try await standaloneState()
    XCTAssertEqual(
      (state["lists"] as? [[String: Any]])?.filter { $0["storage"] as? String == "cloud39" }.count,
      1)
    XCUIDevice.shared.orientation = .landscapeLeft
    let landscapePoint = try await standalonePoint(app, title: "合成云盘 39")
    let rotated = try await standaloneState()
    let rotatedPage = try XCTUnwrap(rotated["page"] as? [String: Any])
    let top = try XCTUnwrap(
      Double((rotatedPage["nativeTop"] as? String ?? "").replacingOccurrences(of: "px", with: "")))
    XCTAssertGreaterThanOrEqual(
      top, app.navigationBars.firstMatch.frame.maxY - app.webViews.firstMatch.frame.minY - 2)
    landscapePoint.tap()
    XCTAssertTrue(table.waitForExistence(timeout: 8))
    assertStandaloneHeight(app)
    app.buttons["native-operation-menu-close"].tap()
    XCTAssertTrue(table.waitForNonExistence(timeout: 8))
    XCUIDevice.shared.orientation = .portrait
    try await standalonePoint(app, title: "合成云盘 39").tap()
    XCTAssertTrue(table.waitForExistence(timeout: 8))
    XCUIDevice.shared.press(.home)
    app.activate()
    XCTAssertTrue(table.waitForNonExistence(timeout: 8))
    try await standalonePoint(app, title: "合成云盘 39").tap()
    XCTAssertTrue(table.waitForExistence(timeout: 8))
    try await standaloneControl("command", value: ["command": "hide"])
    XCTAssertTrue(table.waitForNonExistence(timeout: 8))
    try await standaloneControl("command", value: ["command": "show"])
    try await standalonePoint(app, title: "合成云盘 39").tap()
    XCTAssertTrue(table.waitForExistence(timeout: 8))
    try await standaloneControl("command", value: ["command": "dashboard"])
    XCTAssertTrue(table.waitForNonExistence(timeout: 8))
    XCTAssertTrue(app.navigationBars["仪表盘"].waitForExistence(timeout: 8))
    state = try await standaloneState()
    XCTAssertEqual((state["page"] as? [String: Any])?["htmlMenus"] as? Int, 0)
    XCTAssertFalse(app.staticTexts["暂时无法打开 MoviePilot"].exists)
  }

  /// 辅助字号使用真实系统字体重新量测，长列表受限后仍能选到最后一项。
  func testNativeStandaloneAccessibilityTextSize() async throws {
    try requireStandaloneFixture()
    try await standaloneControl("reset", value: ["variant": "long"])
    let app = try launchCardMenuApp(
      server: "http://127.0.0.1:5248",
      contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL")
    XCTAssertTrue(app.navigationBars["文件管理"].waitForExistence(timeout: 30))
    try await standalonePoint(app).tap()
    let table = app.tables["nativeOperationMenu"]
    XCTAssertTrue(table.waitForExistence(timeout: 8))
    assertStandaloneHeight(app)
    XCTAssertGreaterThan(table.cells.element(boundBy: 0).frame.height, 60)
    attachScreen("独立菜单-辅助字号受限高度", app: app)
    let last = table.cells.containing(.staticText, identifier: "根目录").firstMatch
    for _ in 0..<30 {
      if last.isHittable { break }
      table.swipeUp()
    }
    XCTAssertTrue(last.isHittable)
    app.buttons["native-operation-menu-close"].tap()
    XCTAssertTrue(table.waitForNonExistence(timeout: 8))
  }

  /// 纯协议夹具独立验证 UIKit 的副标题、旗帜、徽标、保留展开和嵌套；不冒充业务回调验收。
  func testNativeStandaloneProtocolMenuTree() async throws {
    try requireStandaloneFixture()
    try await standaloneControl("reset", value: ["variant": "short"])
    let app = try launchCardMenuApp(server: "http://127.0.0.1:5248")
    XCTAssertTrue(app.navigationBars["文件管理"].waitForExistence(timeout: 30))
    _ = try await standalonePoint(app)
    try await standaloneControl("command", value: ["command": "tree"])
    let table = app.tables["nativeOperationMenu"]
    XCTAssertTrue(table.waitForExistence(timeout: 8))
    assertStandaloneHeight(app)
    let language = table.cells["operation-fixture-language"]
    XCTAssertTrue(language.staticTexts["跟随原菜单名称"].exists)
    XCTAssertTrue(language.isSelected)
    XCTAssertFalse(table.cells["operation-fixture-disabled"].isEnabled)
    XCTAssertFalse(table.cells["operation-fixture-loading"].isEnabled)
    XCTAssertTrue(table.cells["operation-fixture-loading"].activityIndicators.firstMatch.exists)
    table.cells["operation-fixture-toggle"].tap()
    XCTAssertTrue(table.staticTexts["已启用"].waitForExistence(timeout: 8))
    XCTAssertTrue(table.cells["operation-fixture-toggle"].isSelected)
    attachScreen("独立菜单-徽标旗帜与保持展开", app: app)
    let submenu = table.cells["operation-fixture-submenu"]
    if !submenu.isHittable { table.swipeUp() }
    submenu.tap()
    XCTAssertTrue(table.cells["operation-fixture-detail"].waitForExistence(timeout: 8))
    XCTAssertTrue(table.cells["operation-fixture-reset"].exists)
    assertStandaloneHeight(app)
    app.buttons["返回上一级菜单"].tap()
    XCTAssertTrue(table.cells["operation-fixture-submenu"].waitForExistence(timeout: 8))
    app.buttons["native-operation-menu-close"].tap()
    XCTAssertTrue(table.waitForNonExistence(timeout: 8))
    let state = try await standaloneState()
    XCTAssertEqual(
      (state["events"] as? [[String: Any]])?.filter {
        $0["type"] as? String == "standaloneMenu.select"
      }.count, 1)
    XCTAssertEqual((state["lists"] as? [[String: Any]])?.count, 1, "纯协议场景不能执行文件业务")
  }

  /// 测试只能指向本机专用端口，不允许对真实实例注入来源隐藏或合成存储。
  private func requireStandaloneFixture() throws {
    guard
      ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_STANDALONE_MENU_SERVER"]
        == "http://127.0.0.1:5248"
    else { throw XCTSkip("独立菜单需要本机 FileToolbar 合成夹具。") }
  }

  /// 复杂筛选继续在系统 Sheet 中显示原 HTML，选择与全选清空仍刷新原资源结果。
  func testNativeTorrentFilterHTMLSheets() async throws {
    try requireTorrentFilterFixture()
    continueAfterFailure = false
    try await torrentFilterControl("reset")
    let app = try launchCardMenuApp(server: "http://127.0.0.1:5250")
    try await waitForTorrentCards(4)
    try await torrentFilterPoint(app, title: "站点").tap()
    let sheet = app.otherElements["native-web-sheet"]
    XCTAssertTrue(sheet.waitForExistence(timeout: 8), app.debugDescription)
    XCTAssertFalse(app.tables["nativeOperationMenu"].exists)
    let dialog = app.webViews.otherElements.matching(
      NSPredicate(format: "label CONTAINS %@", "网页对话框")
    ).firstMatch
    let siteA = dialog.staticTexts["合成站点 A"]
    let siteB = dialog.staticTexts["合成站点 B"]
    XCTAssertTrue(siteA.waitForExistence(timeout: 8), app.debugDescription)
    siteA.tap()
    try await waitForTorrentCards(2)
    siteB.tap()
    try await waitForTorrentCards(4)
    let more = app.buttons["native-sheet-menu"]
    XCTAssertTrue(more.waitForExistence(timeout: 8))
    more.tap()
    nativeUserItem("清除", app: app).tap()
    try await waitForTorrentCards(4)
    more.tap()
    nativeUserItem("全选", app: app).tap()
    try await waitForTorrentCards(4)
    app.webViews.buttons["确定"].tap()
    XCTAssertTrue(sheet.waitForNonExistence(timeout: 8))
    try await torrentFilterPoint(app, title: "综合筛选").tap()
    XCTAssertTrue(sheet.waitForExistence(timeout: 8))
    XCTAssertFalse(app.tables["nativeOperationMenu"].exists)
    XCTAssertTrue(app.webViews.staticTexts["分辨率"].waitForExistence(timeout: 8))
    more.tap()
    nativeUserItem("清除全部", app: app).tap()
    try await waitForTorrentCards(4)
    dialog.staticTexts["合成站点 A"].tap()
    try await waitForTorrentCards(2)
    dialog.staticTexts["S01"].tap()
    try await waitForTorrentCards(1)
    app.buttons["native-sheet-close"].tap()
    XCTAssertTrue(sheet.waitForNonExistence(timeout: 8))
    XCTAssertFalse(app.staticTexts["暂时无法打开 MoviePilot"].exists)
  }

  /// 设置添加与个人资料认证沿用网页原顺序、状态和业务回调，不转换框架用户菜单。
  func testNativeSettingsAndAccountSecurityMenus() async throws {
    try requireTorrentFilterFixture()
    continueAfterFailure = false
    try await torrentFilterControl("reset")
    let app = try launchCardMenuApp(server: "http://127.0.0.1:5250")
    try await waitForTorrentCards(4)
    let table = app.tables["nativeOperationMenu"]
    for (route, title, items) in [
      ("directory", "添加存储", ["本地", "合成云盘", "自定义"]),
      ("system", "添加下载器", ["qBittorrent", "Transmission", "自定义"]),
      ("system", "添加媒体服务器", ["Emby", "Jellyfin", "自定义"]),
      ("notification", "添加通知渠道", ["Telegram", "Slack", "自定义"]),
    ] {
      try await torrentFilterControl("command", value: ["route": route])
      try await torrentFilterPoint(app, title: title).tap()
      XCTAssertTrue(table.waitForExistence(timeout: 8), title)
      XCTAssertEqual(table.cells.count, items.count, title)
      for item in items {
        XCTAssertTrue(
          table.cells.containing(.staticText, identifier: item).firstMatch.exists, title)
      }
      for (first, second) in zip(items, items.dropFirst()) {
        XCTAssertLessThan(
          table.cells.containing(.staticText, identifier: first).firstMatch.frame.minY,
          table.cells.containing(.staticText, identifier: second).firstMatch.frame.minY)
      }
      assertStandaloneHeight(app)
      app.buttons["native-operation-menu-close"].tap()
      XCTAssertTrue(table.waitForNonExistence(timeout: 8))
    }
    try await torrentFilterControl("command", value: ["route": "profile"])
    try await torrentFilterPoint(app, title: "账号安全").tap()
    XCTAssertTrue(table.waitForExistence(timeout: 8))
    XCTAssertEqual(table.cells.count, 2)
    let otp = table.cells.containing(.staticText, identifier: "二次验证").firstMatch
    let passkey = table.cells.containing(.staticText, identifier: "通行密钥管理").firstMatch
    XCTAssertLessThan(otp.frame.minY, passkey.frame.minY)
    XCTAssertEqual(otp.value as? String, "已启用")
    XCTAssertTrue(otp.staticTexts["密码登录需二次验证"].exists)
    otp.tap()
    XCTAssertTrue(table.waitForNonExistence(timeout: 8))
    XCTAssertTrue(app.buttons["native-sheet-close"].waitForExistence(timeout: 8))
    var state = try await torrentFilterState()
    XCTAssertEqual((state["page"] as? [String: Any])?["htmlMenus"] as? Int, 0)
    app.buttons["native-sheet-close"].tap()
    try await torrentFilterPoint(app, title: "账号安全").tap()
    XCTAssertTrue(table.waitForExistence(timeout: 8))
    passkey.tap()
    XCTAssertTrue(table.waitForNonExistence(timeout: 8))
    XCTAssertTrue(app.buttons["native-sheet-close"].waitForExistence(timeout: 8))
    state = try await torrentFilterState()
    XCTAssertEqual((state["page"] as? [String: Any])?["htmlMenus"] as? Int, 0)
    XCTAssertFalse(app.staticTexts["暂时无法打开 MoviePilot"].exists)
  }

  /// MediaCard 长按复用原搜索和季订阅，原按钮仍可操作，无菜单卡片也不选中文字。
  func testNativeMediaCardSearchAndSubscribe() async throws {
    try requireTorrentFilterFixture()
    continueAfterFailure = false
    try await torrentFilterControl("reset")
    let app = try launchCardMenuApp(server: "http://127.0.0.1:5250")
    try await waitForTorrentCards(4)
    try await torrentFilterControl("command", value: ["route": "media"])
    try await torrentFilterPoint(app, title: "媒体卡片").press(forDuration: 1)
    let subscribe = app.buttons["订阅"]
    let search = app.buttons["搜索"]
    XCTAssertTrue(subscribe.waitForExistence(timeout: 8), app.debugDescription)
    XCTAssertTrue(search.exists)
    XCTAssertLessThan(search.frame.minY, subscribe.frame.minY)
    var state = try await torrentFilterState()
    var page = try XCTUnwrap(state["page"] as? [String: Any])
    XCTAssertEqual(page["mediaReady"] as? Bool, true)
    XCTAssertEqual(page["mediaSelect"] as? String, "none")
    XCTAssertEqual(page["selection"] as? String, "")
    XCTAssertEqual(page["htmlMenus"] as? Int, 0)
    attachScreen("媒体卡片-原生搜索订阅长按菜单", app: app)
    subscribe.tap()
    XCTAssertTrue(app.navigationBars["请选择订阅季"].waitForExistence(timeout: 10))
    app.buttons["native-sheet-close"].tap()
    try await torrentFilterPoint(app, title: "媒体卡片").tap()
    _ = try await torrentFilterPoint(app, title: "媒体搜索")
    try await torrentFilterPoint(app, title: "媒体订阅").tap()
    XCTAssertTrue(app.navigationBars["请选择订阅季"].waitForExistence(timeout: 10))
    app.buttons["native-sheet-close"].tap()
    try await torrentFilterPoint(app, title: "媒体卡片").press(forDuration: 1)
    XCTAssertTrue(search.waitForExistence(timeout: 8))
    search.tap()
    try await waitForTorrentCards(4)
    state = try await torrentFilterState()
    page = try XCTUnwrap(state["page"] as? [String: Any])
    // 原页面完成搜索后会主动清理 URL 查询，使用原业务保存的搜索身份核对回调。
    XCTAssertEqual(page["searchMediaId"] as? String, "1001")
    try await torrentFilterControl("command", value: ["route": "system"])
    try await torrentFilterPoint(app, title: "无菜单卡片").press(forDuration: 1)
    state = try await torrentFilterState()
    page = try XCTUnwrap(state["page"] as? [String: Any])
    XCTAssertEqual(page["noMenuSelect"] as? String, "none")
    XCTAssertEqual(page["selection"] as? String, "")
    XCTAssertFalse(app.buttons["复制"].exists)
    XCTAssertFalse(app.tables["nativeOperationMenu"].exists)
    XCTAssertFalse(app.staticTexts["暂时无法打开 MoviePilot"].exists)
  }

  /// 小幅按方向滚动到目标，避免整屏快速滑动跳过相邻分类。
  private func scrollOperationCell(_ cell: XCUIElement, in table: XCUIElement) {
    for _ in 0..<12 {
      if cell.isHittable { return }
      let below = cell.frame.midY > table.frame.midY
      let start = table.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: below ? 0.7 : 0.4))
      let end = table.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: below ? 0.4 : 0.7))
      start.press(forDuration: 0.05, thenDragTo: end)
    }
    XCTAssertTrue(cell.isHittable, table.debugDescription)
  }

  /// 新验收只访问固定本机数据，缺少显式环境变量时不连接任何业务实例。
  private func requireTorrentFilterFixture() throws {
    guard
      ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_TORRENT_FILTER_SERVER"]
        == "http://127.0.0.1:5250"
    else { throw XCTSkip("资源筛选需要本机隔离夹具。") }
  }

  /// 通过有限命令切换真实业务路由，不从测试端直接调用网页菜单业务函数。
  private func torrentFilterControl(_ path: String, value: [String: String] = [:]) async throws {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:5250/__filters/\(path)")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: value)
    let (_, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
  }

  /// 只读取合成页面的可见控件尺寸、结果数与菜单残留数。
  private func torrentFilterState() async throws -> [String: Any] {
    let (data, _) = try await URLSession.shared.data(
      from: URL(string: "http://127.0.0.1:5250/__filters/state")!)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  /// 等待原 Vue 筛选回调真实改变资源结果，避免只核对系统行勾选外观。
  private func waitForTorrentCards(_ count: Int) async throws {
    for _ in 0..<100 {
      let state = try await torrentFilterState()
      if let page = state["page"] as? [String: Any], page["active"] as? String == "active",
        page["cards"] as? Int == count
      {
        return
      }
      try await Task.sleep(for: .milliseconds(150))
    }
    XCTFail("原页面筛选结果未变为 \(count) 项")
    throw NSError(domain: "TorrentFilterFixture", code: 1)
  }

  /// 实际按钮不足一屏时滚动至当前量测位置，不按列表下标猜测可点击区域。
  private func torrentFilterPoint(_ app: XCUIApplication, title: String) async throws
    -> XCUICoordinate
  {
    for _ in 0..<100 {
      let state = try await torrentFilterState()
      if let page = state["page"] as? [String: Any], page["active"] as? String == "active",
        let points = page["points"] as? [String: [String: Double]], let rect = points[title],
        let x = rect["x"], let y = rect["y"], let width = rect["width"], let height = rect["height"]
      {
        let web = app.webViews.firstMatch
        let top = app.navigationBars.firstMatch.frame.maxY - web.frame.minY + 4
        let bottom = app.tabBars["native-root-navigation"].frame.minY - web.frame.minY - 4
        if y < top {
          web.swipeDown()
        } else if y + height > bottom {
          web.swipeUp()
        } else {
          return web.coordinate(withNormalizedOffset: .zero).withOffset(
            .init(dx: x + width / 2, dy: y + height / 2))
        }
      }
      try await Task.sleep(for: .milliseconds(150))
    }
    XCTFail("真实网页菜单入口不可达：\(title)")
    throw NSError(domain: "TorrentFilterFixture", code: 2)
  }

  /// 系统 sheet 自身而非内部表格必须遵守可用屏幕上限。
  private func assertStandaloneHeight(_ app: XCUIApplication) {
    let sheet = app.otherElements["native-operation-menu-sheet"]
    XCTAssertTrue(sheet.exists)
    XCTAssertGreaterThan(sheet.frame.height, 100)
    XCTAssertLessThanOrEqual(sheet.frame.height, app.frame.height * 2 / 3 + 2)
  }

  /// 私有控制仅选择固定合成场景，不传认证或真实文件路径。
  private func standaloneControl(_ path: String, value: [String: String]) async throws {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:5248/__standalone/\(path)")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: value)
    let (_, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
  }

  /// 触点来自真实激活器的当前 DOM 量测，不通过固定坐标或菜单行位置匹配动作。
  private func standalonePoint(_ app: XCUIApplication, title: String = "本地") async throws
    -> XCUICoordinate
  {
    for _ in 0..<100 {
      let state = try await standaloneState()
      if let page = state["page"] as? [String: Any], page["active"] as? String == "active",
        page["trigger"] as? String == title, let rect = page["rect"] as? [String: Double],
        let x = rect["x"], let y = rect["y"], let width = rect["width"],
        let height = rect["height"], width > 0, height > 0
      {
        let web = app.webViews.firstMatch
        let top = app.navigationBars.firstMatch.frame.maxY - web.frame.minY + 4
        let bottom = app.tabBars["native-root-navigation"].frame.minY - web.frame.minY - 4
        let visibleTop = max(top, y)
        let visibleBottom = min(bottom, y + height)
        guard visibleBottom - visibleTop > 4 else {
          web.swipeDown()
          continue
        }
        return web.coordinate(withNormalizedOffset: .zero).withOffset(
          .init(dx: x + width / 2, dy: (visibleTop + visibleBottom) / 2))
      }
      try await Task.sleep(for: .milliseconds(150))
    }
    XCTFail("真实存储菜单激活器未在当前前端就绪")
    throw NSError(domain: "StandaloneMenuFixture", code: 1)
  }

  /// 读取的状态只含合成存储代码、HTML 菜单数和系统菜单回包。
  private func standaloneState() async throws -> [String: Any] {
    let (data, _) = try await URLSession.shared.data(
      from: URL(string: "http://127.0.0.1:5248/__standalone/state")!)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  /// 合成实例允许首次登录或已保存会话恢复，不把后者误判成登录表单缺失。
  private func launchCardMenuApp(server: String, contentSizeCategory: String? = nil) throws
    -> XCUIApplication
  {
    let app = launchConnection(
      server: server, captureScreens: false, contentSizeCategory: contentSizeCategory)
    let account = app.textFields["用户名"]
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        account.exists || app.tabBars["native-root-navigation"].exists
      }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed)
    if account.exists { authenticateFixture(app, remember: false) }
    return app
  }

  /// 控制命令只发往本机固定夹具，不允许对真实 MoviePilot 执行测试写入。
  private func cardMenuControl(_ path: String, value: [String: String] = [:]) async throws {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:5247/__menus/\(path)")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: value)
    let (_, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
  }

  /// 量测来自实际卡片 DOM 和当前 WebView frame，不按屏幕上固定列表下标猜触点。
  private func cardMenuPoint(_ app: XCUIApplication) async throws -> XCUICoordinate {
    for _ in 0..<80 {
      let state = try await cardMenuState()
      if let page = state["page"] as? [String: Any], let count = page["ready"] as? Int, count > 0,
        let rectangles = page["rectangles"] as? [[String: Double]]
      {
        let web = app.webViews.firstMatch
        let top = app.navigationBars.firstMatch.frame.maxY - web.frame.minY + 8
        let bottom = app.tabBars["native-root-navigation"].frame.minY - web.frame.minY - 8
        for rect in rectangles {
          guard let x = rect["x"], let y = rect["y"], let width = rect["width"],
            let height = rect["height"]
          else { continue }
          let visibleTop = max(top, y)
          let visibleBottom = min(bottom, y + height)
          guard visibleBottom - visibleTop > 48 else { continue }
          return web.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: x + width / 2, dy: (visibleTop + visibleBottom) / 2))
        }
      }
      try await Task.sleep(for: .milliseconds(150))
    }
    XCTFail("等待真实前端协商卡片菜单并完成 DOM 量测超时")
    throw NSError(domain: "CardMenuFixture", code: 1)
  }

  /// 私有测试只读取本机合成请求和界面状态，不读取产品凭据或个人实例。
  private func cardMenuState() async throws -> [String: Any] {
    let url = URL(string: "http://127.0.0.1:5247/__menus/state")!
    let (data, _) = try await URLSession.shared.data(from: url)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  /// 公共登录前置只读取私有运行参数，截图不包含账号输入或密码。
  private func signIn() throws -> XCUIApplication {
    let environment = ProcessInfo.processInfo.environment
    guard let username = environment["MOVIEPILOT_E2E_USERNAME"],
      let password = environment["MOVIEPILOT_E2E_PASSWORD"],
      !username.isEmpty, !password.isEmpty
    else { throw XCTSkip("需要通过私有测试运行配置指定实例和账号。") }
    let app = try launchLogin()
    let account = app.textFields["用户名"]
    account.tap()
    attachScreen("框架-登录键盘", app: app)
    account.typeText(username)
    app.secureTextFields["密码"].tap()
    app.secureTextFields["密码"].typeText(password + "\n")
    // 未签名的模拟器可能拒绝 Keychain；明确关闭已告知的降级提示再验收页面交接。
    let outcome = app.buttons.matching(NSPredicate(format: "label IN %@", ["更多", "好"])).firstMatch
    XCTAssertTrue(outcome.waitForExistence(timeout: 45))
    if app.alerts["已登录"].exists { app.alerts["已登录"].buttons["好"].tap() }
    XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 45), "等待网页确认原生导航接管")
    XCTAssertFalse(app.otherElements["native-startup-screen"].exists, "资源与导航完成后启动页必须消失")
    return app
  }

  /// 从空白实例选择启动，连接后停在原生登录界面，不提交任何认证请求。
  private func launchLogin(server: String? = nil, captureScreens: Bool = true) throws
    -> XCUIApplication
  {
    guard let server = server ?? ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_SERVER"],
      !server.isEmpty
    else { throw XCTSkip("需要指定私有验收实例。") }
    let app = launchConnection(server: server, captureScreens: captureScreens)
    let account = app.textFields["用户名"]
    XCTAssertTrue(account.waitForExistence(timeout: 15))
    XCTAssertTrue(app.secureTextFields["密码"].exists)
    if captureScreens { attachScreen("框架-登录", app: app) }
    return app
  }

  /// 启动空白选择并通过真实地址输入提交连接，供成功路径与地址校验失败共用。
  private func launchConnection(
    server: String, captureScreens: Bool = true, contentSizeCategory: String? = nil
  ) -> XCUIApplication {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    let app = XCUIApplication()
    app.launchArguments = [
      "-moviepilot.instance.selected.v1", "", "-AppleLanguages", "(zh-Hans)",
      "-AppleLocale", "zh_CN",
    ]
    if let contentSizeCategory {
      app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSizeCategory]
    }
    app.launch()
    let address = app.textFields["MoviePilot 服务地址"]
    XCTAssertTrue(address.waitForExistence(timeout: 10))
    if captureScreens { attachScreen("框架-连接", app: app) }
    address.tap()
    let clear = address.buttons.firstMatch
    if clear.exists { clear.tap() }
    address.typeText(server)
    XCTAssertEqual(address.value as? String, server, "先确认地址已完整替换，再提交连接")
    // 使用 URL 键盘的前往键，避免自动滚动按钮时打断根控制器交接。
    address.typeText("\n")
    return app
  }

  /// 返回先关闭嵌套网页菜单；只有确认后方导航恢复才继续业务返回。
  private func dismissOverlays(_ app: XCUIApplication) {
    for _ in 0..<3 {
      if app.buttons["native-sheet-close"].exists {
        app.buttons["native-sheet-close"].tap()
      } else if app.buttons["native-panel-close"].exists {
        app.buttons["native-panel-close"].tap()
      } else if app.tabBars["native-root-navigation"].buttons["更多"].exists
        && app.tabBars["native-root-navigation"].buttons["更多"].isEnabled
      {
        return
      } else {
        app.buttons["返回"].tap()
      }
      let closed = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "exists == true AND enabled == true"),
        object: app.tabBars["native-root-navigation"].buttons["更多"])
      if XCTWaiter.wait(for: [closed], timeout: 3) == .completed { return }
    }
    XCTAssertTrue(
      app.tabBars["native-root-navigation"].buttons["更多"].exists
        && app.tabBars["native-root-navigation"].buttons["更多"].isEnabled,
      "原生返回应交由既有 HTML 弹层关闭逻辑处理")
  }

  /// 主入口与动态动作必须处于同一行，两组之间留白，不能叠成上下两层。
  private func assertBottomLayout(_ app: XCUIApplication) {
    let roots = app.tabBars["native-root-navigation"].buttons.allElementsBoundByIndex
    XCTAssertEqual(roots.count, 4)
    XCTAssertEqual(roots.last?.label, "更多", "主导航最后一项保持为更多菜单")
    let more = app.tabBars["native-root-navigation"].buttons["更多"]
    XCTAssertTrue(more.exists)
    XCTAssertEqual(app.tabBars.count, 1, "不能同时保留旧底栏")
    for root in roots {
      XCTAssertEqual(root.frame.midY, more.frame.midY, accuracy: 4)
      XCTAssertGreaterThanOrEqual(root.frame.height, 52, "主导航保持原生底栏的大点击区域")
      XCTAssertGreaterThanOrEqual(root.frame.width, 52)
    }
    let action = app.buttons["native-bottom-action"]
    if action.exists {
      XCTAssertEqual(action.frame.midY, more.frame.midY, accuracy: 4)
      XCTAssertGreaterThanOrEqual(action.frame.minX - more.frame.maxX, 8)
    } else {
      XCTAssertEqual(
        app.tabBars["native-root-navigation"].frame.midX, app.frame.midX, accuracy: 2,
        "没有动态动作时，主导航应居中使用整行空间")
    }
  }

  /// 使用真实列表下拉露出搜索，不通过点击屏幕外元素绕过默认收起的交互。
  private func revealMoreSearch(_ app: XCUIApplication) -> XCUIElement {
    let search = app.descendants(matching: .any)["more-menu-search"]
    let menu = app.tables["more-menu"]
    for _ in 0..<3 {
      if search.exists && search.isHittable { break }
      menu.swipeDown()
    }
    XCTAssertTrue(search.isHittable)
    return search
  }

  /// 从任意业务页重置更多目录，再按原目录标题打开页面，不直接操纵 Web 路由。
  private func openMorePage(_ title: String, app: XCUIApplication) {
    app.tabBars["native-root-navigation"].buttons["更多"].tap()
    let menu = app.tables["more-menu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 10))
    let search = revealMoreSearch(app)
    search.tap()
    if let value = search.value as? String, value != search.placeholderValue {
      search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
    }
    search.typeText(title)
    menu.cells.containing(.staticText, identifier: title).firstMatch.tap()
    XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15))
  }

  /// 逐一操作主要页面的原生分类入口，保留当前分类已呈现的真实业务画面。
  private func capturePageCategories(_ title: String, app: XCUIApplication) {
    let pageTabs: [String: [String]] = [
      "电影订阅": ["我的订阅", "热门订阅"],
      "电视剧订阅": ["我的订阅", "热门订阅", "订阅分享"],
      "音乐订阅": ["我的订阅"],
      "插件": ["我的插件", "插件市场"],
      "工作流": ["我的工作流", "工作流分享"],
      "设定": ["系统", "存储 & 目录", "站点", "规则", "搜索 & 下载", "订阅", "通知"],
    ]
    guard let tabs = pageTabs[title] else { return }
    let category = app.buttons["\(title)，页内分类"]
    XCTAssertTrue(category.waitForExistence(timeout: 10))
    for tab in tabs {
      category.tap()
      let item = app.buttons[tab].firstMatch
      XCTAssertTrue(item.waitForExistence(timeout: 5), "原生分类必须保留全部现有入口")
      item.tap()
      let selected = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "value == %@", tab), object: category)
      XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
      settlePage(app)
      attachScreen("页面-\(title) · \(tab)", app: app)
    }
  }

  /// 等待网页首屏更新与已出现的加载指示结束；最终是否完整由截图复核决定。
  private func settlePage(_ app: XCUIApplication) {
    let idle = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in !app.activityIndicators.firstMatch.exists }, object: nil)
    _ = XCTWaiter.wait(for: [idle], timeout: 10)
    RunLoop.current.run(until: Date().addingTimeInterval(1.5))
  }

  /// 将系统最终画面保存在测试结果包中，避免仅以节点查询替代外观验收。
  private func attachScreen(_ name: String, app: XCUIApplication) {
    dismissUpdateReminderIfVisible(app)
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// 截图前只延后实例的本机资源更新提醒，避免通知卡片遮住正文，不下载或安装更新。
  private func dismissUpdateReminderIfVisible(_ app: XCUIApplication) {
    let reminder = app.webViews.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "发现站点资源更新")
    ).firstMatch
    guard reminder.exists && reminder.isHittable else { return }
    let later = app.webViews.buttons["稍后"]
    guard later.isHittable else { return }
    later.tap()
    let closed = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: reminder)
    XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 3), .completed)
  }
}
