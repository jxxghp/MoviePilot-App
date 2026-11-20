import UIKit
import XCTest

/// API-only 服务通过真实按钮验收原生入口，不启动前端或借用网页登录结果。
@MainActor
final class NativeV2EntryTests: XCTestCase {
  private let base = "http://127.0.0.1:5330/"
  private let arguments = ["--native-v2", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]

  /// 显式交互运行时才从一次性回环通道取得凭据；App 自己连接真实后端执行只读浏览。
  func testLiveBackendReadOnlyMediaScreens() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let port = environment["MOVIEPILOT_NATIVE_V2_LIVE_INPUT_PORT"],
      let number = Int(port), (1024...65535).contains(number),
      let nonce = environment["MOVIEPILOT_NATIVE_V2_LIVE_NONCE"], nonce.count >= 32
    else { throw XCTSkip("仅由交互式本机验收脚本运行，不从文件或测试源码获取真实凭据。") }
    continueAfterFailure = false
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(number)/session-input")!)
    request.setValue(nonce, forHTTPHeaderField: "X-MoviePilot-Live-Test")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      return XCTFail("一次性本机输入通道不可用。")
    }
    var input: LiveBackendInput? = try JSONDecoder().decode(LiveBackendInput.self, from: data)
    let app = XCUIApplication()
    defer {
      input = nil
      app.terminate()
    }
    app.launchArguments = arguments + ["-moviepilot.instance.selected.v1", ""]
    app.launch()
    let address = app.textFields["native-v2-address"]
    XCTAssertTrue(address.waitForExistence(timeout: 15))
    tap(address, app: app)
    let clear = app.buttons["native-v2-clear-address"]
    if clear.exists { clear.tap() }
    address.typeText("http://127.0.0.1:3001/\n")
    let nextPageIdentities = try XCTUnwrap(input?.nextPageIdentities)
    let discoverTab = tabButton("发现", app: app)
    let username = app.textFields["native-v2-username"]
    if !discoverTab.waitForExistence(timeout: 5) {
      XCTAssertTrue(username.waitForExistence(timeout: 15))
      tap(username, app: app)
      username.typeText(try XCTUnwrap(input?.username) + "\n")
      app.secureTextFields["native-v2-password"].typeText(try XCTUnwrap(input?.password) + "\n")
      input = nil
      dismissKeyboard(app)
      if app.switches["native-v2-remember-session"].value as? String == "1" {
        toggle("native-v2-remember-session", to: false, app: app)
      }
      tap(app.buttons["native-v2-login"], app: app)
      XCTAssertTrue(tabButton("发现", app: app).waitForExistence(timeout: 20))
    } else {
      input = nil
    }
    let more = app.buttons["native-discover-more-热门电影"]
    XCTAssertTrue(more.waitForExistence(timeout: 40))
    // 等待实际后端图片代理完成首屏解码，不用合成海报代替线上媒体素材。
    try await Task.sleep(nanoseconds: 4_000_000_000)
    captureDiscoverScrollPhases(app, prefix: "native-v2-live-discover")
    tap(more, app: app)
    let grid = app.scrollViews["native-discover-grid"]
    XCTAssertTrue(grid.waitForExistence(timeout: 8))
    capture("native-v2-live-grid-before-pagination")
    let expected = NSPredicate(
      format: "identifier IN %@",
      nextPageIdentities.map {
        "native-discover-grid-poster-" + $0
      })
    let nextPage = app.buttons.matching(expected).firstMatch
    for _ in 0..<10 where !nextPage.exists {
      grid.swipeUp()
      try await Task.sleep(nanoseconds: 500_000_000)
    }
    capture("native-v2-live-grid-pagination-state")
    XCTAssertTrue(nextPage.waitForExistence(timeout: 20))
    XCTAssertFalse(app.buttons["native-discover-grid-load-more"].exists)
    try await Task.sleep(nanoseconds: 1_000_000_000)
    capture("native-v2-live-grid-automatic-page")
    // 采集真实媒体详情、演职员/人物页、剧集分季、下载/订阅/日历工作台、仪表盘与媒体搜索画面（全程只读）。
    tap(nextPage, app: app)
    XCTAssertTrue(app.staticTexts["native-media-detail-title"].waitForExistence(timeout: 15))
    try await Task.sleep(nanoseconds: 2_000_000_000)
    capture("native-v2-live-detail")
    let detailScroll = app.scrollViews["native-media-detail-scroll"]
    if detailScroll.exists {
      detailScroll.swipeUp()
      try await Task.sleep(nanoseconds: 1_000_000_000)
      capture("native-v2-live-detail-cast")
    }
    let firstCast = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH 'native-media-detail-cast-'")
    ).firstMatch
    if firstCast.exists {
      tap(firstCast, app: app)
      if app.staticTexts["native-person-detail-name"].waitForExistence(timeout: 15) {
        try await Task.sleep(nanoseconds: 2_000_000_000)
        capture("native-v2-live-person")
      }
    }
    tap(tabButton("我的", app: app), app: app)
    let subsEntry = app.buttons["native-workspace-subscriptions"]
    if subsEntry.waitForExistence(timeout: 10) {
      tap(subsEntry, app: app)
      XCTAssertTrue(app.scrollViews["native-subscriptions-scroll"].waitForExistence(timeout: 15))
      try await Task.sleep(nanoseconds: 2_500_000_000)
      capture("native-v2-live-subscriptions")
      app.navigationBars.buttons.firstMatch.tap()
    }
    let resEntry = app.buttons["native-workspace-resources"]
    if resEntry.waitForExistence(timeout: 8) {
      tap(resEntry, app: app)
      XCTAssertTrue(
        app.scrollViews["native-resource-search-scroll"].waitForExistence(timeout: 15))
      try await Task.sleep(nanoseconds: 2_000_000_000)
      capture("native-v2-live-resources")
      app.navigationBars.buttons.firstMatch.tap()
    }
    let dlEntry = app.buttons["native-workspace-downloads"]
    if dlEntry.waitForExistence(timeout: 8) {
      tap(dlEntry, app: app)
      XCTAssertTrue(app.scrollViews["native-downloads-scroll"].waitForExistence(timeout: 15))
      try await Task.sleep(nanoseconds: 2_000_000_000)
      capture("native-v2-live-downloads")
      app.navigationBars.buttons.firstMatch.tap()
    }
    let calEntry = app.buttons["native-workspace-calendar"]
    if calEntry.waitForExistence(timeout: 8) {
      tap(calEntry, app: app)
      XCTAssertTrue(app.scrollViews["native-calendar-scroll"].waitForExistence(timeout: 15))
      try await Task.sleep(nanoseconds: 2_000_000_000)
      capture("native-v2-live-calendar")
      app.navigationBars.buttons.firstMatch.tap()
    }
    let historyEntry = app.buttons["native-workspace-history"]
    if historyEntry.waitForExistence(timeout: 8) {
      tap(historyEntry, app: app)
      XCTAssertTrue(app.scrollViews["native-history-scroll"].waitForExistence(timeout: 15))
      try await Task.sleep(nanoseconds: 2_000_000_000)
      capture("native-v2-live-history")
      app.navigationBars.buttons.firstMatch.tap()
    }
    let sitesEntry = app.buttons["native-workspace-sites"]
    if sitesEntry.waitForExistence(timeout: 8) {
      tap(sitesEntry, app: app)
      XCTAssertTrue(app.scrollViews["native-sites-scroll"].waitForExistence(timeout: 15))
      try await Task.sleep(nanoseconds: 1_500_000_000)
      capture("native-v2-live-sites")
      app.navigationBars.buttons.firstMatch.tap()
    }
    let filesEntry = app.buttons["native-workspace-files"]
    if filesEntry.waitForExistence(timeout: 8) {
      tap(filesEntry, app: app)
      XCTAssertTrue(app.scrollViews["native-files-scroll"].waitForExistence(timeout: 15))
      try await Task.sleep(nanoseconds: 1_500_000_000)
      capture("native-v2-live-files")
      app.navigationBars.buttons.firstMatch.tap()
    }
    let wfEntry = app.buttons["native-workspace-workflows"]
    if wfEntry.waitForExistence(timeout: 8) {
      tap(wfEntry, app: app)
      XCTAssertTrue(app.scrollViews["native-workflows-scroll"].waitForExistence(timeout: 15))
      try await Task.sleep(nanoseconds: 1_500_000_000)
      capture("native-v2-live-workflows")
      app.navigationBars.buttons.firstMatch.tap()
    }
    let msgEntry = app.buttons["native-workspace-messages"]
    if msgEntry.waitForExistence(timeout: 8) {
      tap(msgEntry, app: app)
      XCTAssertTrue(app.scrollViews["native-messages-scroll"].waitForExistence(timeout: 15))
      try await Task.sleep(nanoseconds: 2_000_000_000)
      capture("native-v2-live-messages")
      app.navigationBars.buttons.firstMatch.tap()
    }
    let settingsEntry = app.buttons["native-workspace-settings"]
    reveal(settingsEntry, app: app)
    if settingsEntry.waitForExistence(timeout: 8) {
      tap(settingsEntry, app: app)
      XCTAssertTrue(app.scrollViews["native-settings-scroll"].waitForExistence(timeout: 15))
      try await Task.sleep(nanoseconds: 1_500_000_000)
      capture("native-v2-live-settings")
      app.navigationBars.buttons.firstMatch.tap()
    }
    let usersEntry = app.buttons["native-workspace-users"]
    reveal(usersEntry, app: app)
    if usersEntry.waitForExistence(timeout: 8) {
      tap(usersEntry, app: app)
      XCTAssertTrue(app.scrollViews["native-users-scroll"].waitForExistence(timeout: 15))
      try await Task.sleep(nanoseconds: 1_500_000_000)
      capture("native-v2-live-users")
      app.navigationBars.buttons.firstMatch.tap()
    }
    tap(tabButton("仪表盘", app: app), app: app)
    XCTAssertTrue(
      app.descendants(matching: .any)["native-dashboard-storage"].firstMatch.waitForExistence(
        timeout: 15))
    try await Task.sleep(nanoseconds: 1_000_000_000)
    capture("native-v2-live-dashboard")
    tap(tabButton("搜索", app: app), app: app)
    let query = app.textFields["native-media-search-query"]
    XCTAssertTrue(query.waitForExistence(timeout: 8))
    query.tap()
    query.typeText("超感神探\n")
    try await Task.sleep(nanoseconds: 3_500_000_000)
    capture("native-v2-live-search")
    let firstResult = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH 'native-media-search-result-'")
    ).firstMatch
    if firstResult.waitForExistence(timeout: 8) {
      tap(firstResult, app: app)
      if app.staticTexts["native-media-detail-title"].waitForExistence(timeout: 15) {
        try await Task.sleep(nanoseconds: 2_000_000_000)
        capture("native-v2-live-tv-detail")
        let tvScroll = app.scrollViews.firstMatch
        if tvScroll.exists {
          tvScroll.swipeUp()
          try await Task.sleep(nanoseconds: 1_000_000_000)
          capture("native-v2-live-tv-seasons")
        }
      }
    }
    XCTAssertEqual(app.webViews.count, 0)
    // 退出后内存身份销毁，测试脚本会清理含登录活动的原始结果包。
  }

  /// 只存在于测试运行器内存中的输入，不保存主 Token、真实资料或服务端响应正文。
  private struct LiveBackendInput: Decodable {
    let username: String
    let password: String
    let nextPageIdentities: [String]
  }

  /// 从发现栏打开全部、加载下一页并进入选中作品；图片只由当前服务代理。
  func testNativeDiscoverLoadsArtworkAndPaginatedDetail() async throws {
    let app = try await signInToNativeBusiness()
    defer { app.terminate() }
    let more = app.buttons["native-discover-more-热门电影"]
    XCTAssertTrue(more.waitForExistence(timeout: 12))
    try await waitForArtwork("a", minimum: 4)
    captureDiscoverScrollPhases(app, prefix: "native-v2-discover")
    tap(more, app: app)
    let added = app.buttons["native-discover-grid-poster-themoviedb|113|电影"]
    for _ in 0..<6 where !added.exists { app.swipeUp() }
    XCTAssertTrue(added.waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["native-discover-grid-load-more"].exists)
    capture("native-v2-discover-grid")
    tap(added, app: app)
    let title = app.staticTexts["native-media-detail-title"]
    XCTAssertTrue(title.waitForExistence(timeout: 10))
    XCTAssertEqual(title.label, "合成电影 113")
    capture("native-v2-discover-detail")
    XCTAssertEqual(app.webViews.count, 0)
    let counts = try await stats()
    XCTAssertEqual(counts["a"]?["discover:tmdb_movies:2"], 1)
    XCTAssertEqual(counts["a"]?["GET api/v1/media/113"], 1)
    XCTAssertGreaterThan(counts["a"]?["image-served"] ?? 0, 0)
    XCTAssertNil(counts["a"]?["image-auth-rejected"])
    XCTAssertEqual(counts["unexpected"], [:])
  }

  /// P3.4 完整媒体详情：验证入库徽标、显式订阅与二次确认取消、演职员推入人物页以及剧集分季订阅。
  func testNativeMediaDetailSubscribesAndNavigatesToPerson() async throws {
    let app = try await signInToNativeBusiness()
    defer { app.terminate() }
    let more = app.buttons["native-discover-more-热门电影"]
    XCTAssertTrue(more.waitForExistence(timeout: 12))
    tap(more, app: app)
    let movie113 = app.buttons["native-discover-grid-poster-themoviedb|113|电影"]
    for _ in 0..<6 where !movie113.exists { app.swipeUp() }
    XCTAssertTrue(movie113.waitForExistence(timeout: 10))
    tap(movie113, app: app)
    XCTAssertTrue(app.staticTexts["native-media-detail-title"].waitForExistence(timeout: 10))
    XCTAssertTrue(
      app.descendants(matching: .any)["native-media-detail-library-badge"].firstMatch
        .waitForExistence(timeout: 8))
    let subscribe = app.buttons["native-media-detail-subscribe"]
    XCTAssertTrue(subscribe.waitForExistence(timeout: 8))
    tap(subscribe, app: app)
    XCTAssertTrue(
      app.descendants(matching: .any)["native-media-detail-feedback"].firstMatch
        .waitForExistence(timeout: 8))
    tap(subscribe, app: app)
    let confirmCancel = app.alerts["取消订阅"].buttons["取消订阅"]
    XCTAssertTrue(confirmCancel.waitForExistence(timeout: 8))
    confirmCancel.tap()
    let castButton = app.buttons["native-media-detail-cast-501"]
    reveal(castButton, app: app)
    XCTAssertTrue(castButton.waitForExistence(timeout: 8))
    tap(castButton, app: app)
    let personName = app.staticTexts["native-person-detail-name"]
    XCTAssertTrue(personName.waitForExistence(timeout: 10))
    XCTAssertEqual(personName.label, "合成主演")
    let tvWork = app.buttons["native-person-work-themoviedb|111|电视剧"]
    reveal(tvWork, app: app)
    XCTAssertTrue(tvWork.waitForExistence(timeout: 8))
    tap(tvWork, app: app)
    let seasonOne = app.buttons["native-media-detail-season-subscribe-1"]
    reveal(seasonOne, app: app)
    XCTAssertTrue(seasonOne.waitForExistence(timeout: 10))
    tap(seasonOne, app: app)
    XCTAssertTrue(
      app.descendants(matching: .any)["native-media-detail-feedback"].firstMatch
        .waitForExistence(timeout: 8))
    XCTAssertEqual(app.webViews.count, 0)
    let counts = try await stats()
    XCTAssertEqual(counts["a"]?["POST api/v1/subscribe/"], 2)
    XCTAssertEqual(counts["a"]?["DELETE api/v1/subscribe/media/113"], 1)
    XCTAssertEqual(counts["a"]?["GET api/v1/tmdb/person/501"], 1)
    XCTAssertEqual(counts["a"]?["GET api/v1/tmdb/person/credits/501"], 1)
    XCTAssertEqual(counts["unexpected"], [:])
  }

  /// P5.1 / P4.1 / P4.4：验证原生下载启停/确认删除、订阅筛选/暂停/确认删除与追剧日历切周，零 WebView。
  func testNativeDownloadsSubscriptionsAndCalendarFlows() async throws {
    let app = try await signInToNativeBusiness()
    defer { app.terminate() }
    tap(tabButton("我的", app: app), app: app)

    let subsEntry = app.buttons["native-workspace-subscriptions"]
    XCTAssertTrue(subsEntry.waitForExistence(timeout: 10))
    tap(subsEntry, app: app)
    XCTAssertTrue(app.scrollViews["native-subscriptions-scroll"].waitForExistence(timeout: 10))
    let subToggle = app.buttons["native-subscribe-toggle-702"]
    XCTAssertTrue(subToggle.waitForExistence(timeout: 10))
    tap(subToggle, app: app)
    XCTAssertTrue(
      app.descendants(matching: .any)["native-subscriptions-feedback"].firstMatch
        .waitForExistence(timeout: 8))
    let subDelete = app.buttons["native-subscribe-delete-701"]
    XCTAssertTrue(subDelete.waitForExistence(timeout: 8))
    tap(subDelete, app: app)
    let confirmSubDelete = app.alerts["取消订阅"].buttons["取消订阅"]
    XCTAssertTrue(confirmSubDelete.waitForExistence(timeout: 8))
    confirmSubDelete.tap()
    app.navigationBars.buttons.firstMatch.tap()

    let dlEntry = app.buttons["native-workspace-downloads"]
    XCTAssertTrue(dlEntry.waitForExistence(timeout: 10))
    tap(dlEntry, app: app)
    XCTAssertTrue(app.scrollViews["native-downloads-scroll"].waitForExistence(timeout: 10))
    let dlToggle = app.buttons["native-download-toggle-abc123def456"]
    XCTAssertTrue(dlToggle.waitForExistence(timeout: 10))
    tap(dlToggle, app: app)
    XCTAssertTrue(
      app.descendants(matching: .any)["native-downloads-feedback"].firstMatch
        .waitForExistence(timeout: 8))
    let dlDelete = app.buttons["native-download-delete-abc123def456"]
    XCTAssertTrue(dlDelete.waitForExistence(timeout: 8))
    tap(dlDelete, app: app)
    let confirmDlDelete = app.alerts["删除下载任务"].buttons["删除任务与文件"]
    XCTAssertTrue(confirmDlDelete.waitForExistence(timeout: 8))
    confirmDlDelete.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["native-downloads-empty"].firstMatch
        .waitForExistence(timeout: 10))
    app.navigationBars.buttons.firstMatch.tap()

    let calEntry = app.buttons["native-workspace-calendar"]
    XCTAssertTrue(calEntry.waitForExistence(timeout: 10))
    tap(calEntry, app: app)
    XCTAssertTrue(app.scrollViews["native-calendar-scroll"].waitForExistence(timeout: 10))
    let nextWeek = app.buttons["native-calendar-next-week"]
    XCTAssertTrue(nextWeek.waitForExistence(timeout: 8))
    tap(nextWeek, app: app)
    XCTAssertEqual(app.webViews.count, 0)

    let counts = try await stats()
    XCTAssertEqual(counts["a"]?["PUT api/v1/subscribe/status/702"], 1)
    XCTAssertEqual(counts["a"]?["DELETE api/v1/subscribe/701"], 1)
    XCTAssertEqual(counts["a"]?["GET api/v1/download/stop/abc123def456"], 1)
    XCTAssertEqual(counts["a"]?["DELETE api/v1/download/abc123def456"], 1)
    XCTAssertGreaterThanOrEqual(counts["a"]?["GET api/v1/subscribe/calendar"] ?? 0, 2)
    XCTAssertEqual(counts["unexpected"], [:])
  }

  /// P3.3b：验证详情页直达资源搜索、免费/画质过滤、确认弹窗取消及显式单次提交下载，零 WebView。
  func testNativeResourceSearchAndDownloadConfirmation() async throws {
    let app = try await signInToNativeBusiness()
    defer { app.terminate() }
    let more = app.buttons["native-discover-more-热门电影"]
    XCTAssertTrue(more.waitForExistence(timeout: 12))
    tap(more, app: app)
    let movie113 = app.buttons["native-discover-grid-poster-themoviedb|113|电影"]
    for _ in 0..<6 where !movie113.exists { app.swipeUp() }
    XCTAssertTrue(movie113.waitForExistence(timeout: 10))
    tap(movie113, app: app)
    let searchBtn = app.buttons["native-media-detail-search-resources"]
    XCTAssertTrue(searchBtn.waitForExistence(timeout: 12))
    tap(searchBtn, app: app)
    XCTAssertTrue(app.scrollViews["native-resource-search-scroll"].waitForExistence(timeout: 10))
    let freeFilter = app.buttons["native-resource-filter-免费"]
    XCTAssertTrue(freeFilter.waitForExistence(timeout: 10))
    tap(freeFilter, app: app)
    let dlBtn = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH 'native-resource-download-'")
    ).firstMatch
    XCTAssertTrue(dlBtn.waitForExistence(timeout: 10))
    tap(dlBtn, app: app)
    let cancelBtn = app.buttons["native-download-confirm-cancel"]
    XCTAssertTrue(cancelBtn.waitForExistence(timeout: 8))
    cancelBtn.tap()
    tap(dlBtn, app: app)
    let submitBtn = app.buttons["native-download-confirm-submit"]
    XCTAssertTrue(submitBtn.waitForExistence(timeout: 8))
    submitBtn.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["native-resource-feedback"].firstMatch
        .waitForExistence(timeout: 10))
    XCTAssertEqual(app.webViews.count, 0)
    let counts = try await stats()
    XCTAssertEqual(counts["a"]?["GET api/v1/search/media/113"], 1)
    XCTAssertEqual(counts["a"]?["POST api/v1/download/add"], 1)
    XCTAssertEqual(counts["unexpected"], [:])
  }

  /// P5.3 / P6.1 / P6.4：验证原生整理历史展开/确认删除、站点连通测试与消息中心分类过滤，零 WebView。
  func testNativeHistorySitesAndMessagesFlows() async throws {
    let app = try await signInToNativeBusiness()
    defer { app.terminate() }
    tap(tabButton("我的", app: app), app: app)

    let historyEntry = app.buttons["native-workspace-history"]
    XCTAssertTrue(historyEntry.waitForExistence(timeout: 10))
    tap(historyEntry, app: app)
    XCTAssertTrue(app.scrollViews["native-history-scroll"].waitForExistence(timeout: 10))
    let expandBtn = app.buttons["native-history-expand-801"]
    XCTAssertTrue(expandBtn.waitForExistence(timeout: 10))
    tap(expandBtn, app: app)
    let deleteBtn = app.buttons["native-history-delete-801"]
    XCTAssertTrue(deleteBtn.waitForExistence(timeout: 8))
    tap(deleteBtn, app: app)
    let confirmDelete = app.alerts["删除整理记录"].buttons["仅删除记录"]
    XCTAssertTrue(confirmDelete.waitForExistence(timeout: 8))
    confirmDelete.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["native-history-feedback"].firstMatch
        .waitForExistence(timeout: 8))
    app.navigationBars.buttons.firstMatch.tap()

    let sitesEntry = app.buttons["native-workspace-sites"]
    XCTAssertTrue(sitesEntry.waitForExistence(timeout: 10))
    tap(sitesEntry, app: app)
    XCTAssertTrue(app.scrollViews["native-sites-scroll"].waitForExistence(timeout: 10))
    let testSiteBtn = app.buttons["native-site-test-3"]
    XCTAssertTrue(testSiteBtn.waitForExistence(timeout: 10))
    tap(testSiteBtn, app: app)
    XCTAssertTrue(
      app.descendants(matching: .any)["native-site-test-passed"].firstMatch
        .waitForExistence(timeout: 10))
    app.navigationBars.buttons.firstMatch.tap()

    let msgEntry = app.buttons["native-workspace-messages"]
    XCTAssertTrue(msgEntry.waitForExistence(timeout: 10))
    tap(msgEntry, app: app)
    XCTAssertTrue(app.scrollViews["native-messages-scroll"].waitForExistence(timeout: 10))
    let subFilter = app.buttons["native-messages-filter-订阅"]
    XCTAssertTrue(subFilter.waitForExistence(timeout: 10))
    tap(subFilter, app: app)
    XCTAssertEqual(app.webViews.count, 0)

    let counts = try await stats()
    XCTAssertEqual(counts["a"]?["DELETE api/v1/history/transfer"], 1)
    XCTAssertEqual(counts["a"]?["GET api/v1/site/test/3"], 1)
    XCTAssertEqual(counts["a"]?["GET api/v1/message/web"], 1)
    XCTAssertEqual(counts["unexpected"], [:])
  }

  /// P5.2 / P5.4：验证原生多存储文件钻取/返回上级/删除确认，以及工作流手动运行与启用控制，零 WebView。
  func testNativeFileManagerAndWorkflowFlows() async throws {
    let app = try await signInToNativeBusiness()
    defer { app.terminate() }
    tap(tabButton("我的", app: app), app: app)

    let filesEntry = app.buttons["native-workspace-files"]
    reveal(filesEntry, app: app)
    XCTAssertTrue(filesEntry.waitForExistence(timeout: 10))
    tap(filesEntry, app: app)
    XCTAssertTrue(app.scrollViews["native-files-scroll"].waitForExistence(timeout: 10))
    let mediaFolder = app.buttons["native-file-open-media"]
    XCTAssertTrue(mediaFolder.waitForExistence(timeout: 10))
    tap(mediaFolder, app: app)
    let upBtn = app.buttons["native-files-up"]
    XCTAssertTrue(upBtn.waitForExistence(timeout: 10))
    tap(upBtn, app: app)
    let delFile = app.buttons["native-file-delete-samplemkv"]
    XCTAssertTrue(delFile.waitForExistence(timeout: 10))
    tap(delFile, app: app)
    let confirmDel = app.alerts["删除项目"].buttons["确认删除"]
    XCTAssertTrue(confirmDel.waitForExistence(timeout: 8))
    confirmDel.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["native-files-feedback"].firstMatch
        .waitForExistence(timeout: 8))
    app.navigationBars.buttons.firstMatch.tap()

    let wfEntry = app.buttons["native-workspace-workflows"]
    reveal(wfEntry, app: app)
    XCTAssertTrue(wfEntry.waitForExistence(timeout: 10))
    tap(wfEntry, app: app)
    XCTAssertTrue(app.scrollViews["native-workflows-scroll"].waitForExistence(timeout: 10))
    let runBtn = app.buttons["native-workflow-run-31"]
    XCTAssertTrue(runBtn.waitForExistence(timeout: 10))
    tap(runBtn, app: app)
    XCTAssertTrue(
      app.descendants(matching: .any)["native-workflows-feedback"].firstMatch
        .waitForExistence(timeout: 8))
    let toggleBtn = app.buttons["native-workflow-toggle-31"]
    XCTAssertTrue(toggleBtn.waitForExistence(timeout: 8))
    tap(toggleBtn, app: app)
    XCTAssertEqual(app.webViews.count, 0)

    let counts = try await stats()
    XCTAssertGreaterThanOrEqual(counts["a"]?["POST api/v1/storage/list"] ?? 0, 3)
    XCTAssertEqual(counts["a"]?["POST api/v1/storage/delete"], 1)
    XCTAssertEqual(counts["a"]?["POST api/v1/workflow/31/run"], 1)
    XCTAssertEqual(counts["a"]?["POST api/v1/workflow/31/pause"], 1)
    XCTAssertEqual(counts["unexpected"], [:])
  }

  /// P6.2 / P6.3：验证管理员系统设置白名单读写/增量单次保存与用户权限清单浏览，零 WebView。
  func testNativeSystemSettingsAndUsersFlows() async throws {
    let app = try await signInToNativeBusiness()
    defer { app.terminate() }
    tap(tabButton("我的", app: app), app: app)

    let settingsEntry = app.buttons["native-workspace-settings"]
    reveal(settingsEntry, app: app)
    XCTAssertTrue(settingsEntry.waitForExistence(timeout: 10))
    tap(settingsEntry, app: app)
    XCTAssertTrue(app.scrollViews["native-settings-scroll"].waitForExistence(timeout: 10))
    let saveBtn = app.buttons["native-settings-save"]
    XCTAssertTrue(saveBtn.waitForExistence(timeout: 10))
    XCTAssertFalse(saveBtn.isEnabled)
    toggle("native-settings-image-cache", to: false, app: app)
    XCTAssertTrue(saveBtn.isEnabled)
    tap(saveBtn, app: app)
    XCTAssertTrue(
      app.descendants(matching: .any)["native-settings-feedback"].firstMatch
        .waitForExistence(timeout: 10))
    XCTAssertFalse(saveBtn.isEnabled)
    app.navigationBars.buttons.firstMatch.tap()

    let usersEntry = app.buttons["native-workspace-users"]
    reveal(usersEntry, app: app)
    XCTAssertTrue(usersEntry.waitForExistence(timeout: 10))
    tap(usersEntry, app: app)
    XCTAssertTrue(app.scrollViews["native-users-scroll"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["native-a"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["native-b"].exists)
    let refreshBtn = app.buttons["native-users-refresh"]
    XCTAssertTrue(refreshBtn.exists)
    tap(refreshBtn, app: app)
    XCTAssertEqual(app.webViews.count, 0)

    let counts = try await stats()
    XCTAssertEqual(counts["a"]?["GET api/v1/system/env"], 1)
    XCTAssertEqual(counts["a"]?["POST api/v1/system/env"], 1)
    XCTAssertGreaterThanOrEqual(counts["a"]?["GET api/v1/user"] ?? 0, 2)
    XCTAssertEqual(counts["unexpected"], [:])
  }

  /// 单条发现源失败仍保留可用轨道；重试更新全部轨道且不注入预览样例。
  func testNativeDiscoverRetainsAvailableRailsAndRetriesPartialFailure() async throws {
    let app = try await signInToNativeBusiness(mode: "partial-discovery-failed")
    defer { app.terminate() }
    XCTAssertTrue(app.buttons["native-discover-more-热门电影"].waitForExistence(timeout: 12))
    let retry = app.buttons["native-discover-retry"]
    XCTAssertTrue(retry.waitForExistence(timeout: 8))
    XCTAssertFalse(app.buttons["native-discover-more-热门剧集"].exists)
    try await configure("a", mode: "ready")
    tap(retry, app: app)
    XCTAssertTrue(app.buttons["native-discover-more-热门剧集"].waitForExistence(timeout: 10))
    XCTAssertFalse(retry.exists)
    let counts = try await stats()
    XCTAssertEqual(counts["a"]?["discover:tmdb_movies:1"], 2)
    XCTAssertEqual(counts["a"]?["discover:tmdb_tvs:1"], 2)
    XCTAssertEqual(counts["unexpected"], [:])
  }

  /// 仅有发现权限也可原生搜索，草稿不发请求，失败由用户重试并继续分页。
  func testNativeMediaSearchOnlySubmitsOnActionAndRetries() async throws {
    let app = try await signInToNativeBusiness("b", mode: "discovery-only")
    defer { app.terminate() }
    let search = tabButton("搜索", app: app)
    XCTAssertTrue(search.waitForExistence(timeout: 8))
    tap(search, app: app)
    let field = app.textFields["native-media-search-query"]
    XCTAssertTrue(field.waitForExistence(timeout: 8))
    field.tap()
    field.typeText("galaxy")
    let draft = try await stats()
    XCTAssertNil(draft["b"]?["GET api/v1/media/search"])

    try await configure("b", mode: "search-failed")
    capture("native-v2-global-search")
    field.typeText("\n")
    let retry = app.buttons["native-media-search-retry"]
    XCTAssertTrue(retry.waitForExistence(timeout: 10))
    let failed = try await stats()
    XCTAssertEqual(failed["b"]?["search:galaxy:1"], 1)
    try await configure("b", mode: "discovery-only")
    tap(retry, app: app)
    let firstResult = app.buttons["native-media-search-result-电影:themoviedb:121"]
    XCTAssertTrue(firstResult.waitForExistence(timeout: 10))
    capture("native-v2-media-search")
    let lastResult = app.buttons["native-media-search-result-电影:themoviedb:129"]
    let scroll = app.scrollViews["native-media-search-scroll"]
    for _ in 0..<8 where !lastResult.exists { scroll.swipeUp() }
    XCTAssertFalse(app.buttons["native-media-search-more"].exists)
    tap(lastResult, app: app)
    let title = app.staticTexts["native-media-detail-title"]
    XCTAssertTrue(title.waitForExistence(timeout: 10))
    XCTAssertEqual(title.label, "合成电影 129")
    XCTAssertEqual(app.webViews.count, 0)
    let counts = try await stats()
    XCTAssertEqual(counts["b"]?["search:galaxy:1"], 2)
    XCTAssertEqual(counts["b"]?["search:galaxy:2"], 1)
    XCTAssertEqual(counts["b"]?["GET api/v1/media/129"], 1)
    XCTAssertEqual(counts["unexpected"], [:])
  }

  /// 一项存储读取失败不会隐藏媒体库和服务，管理员可通过可见重试恢复存储统计。
  func testNativeDashboardRetainsStatisticsDuringPartialFailure() async throws {
    let app = try await signInToNativeBusiness(mode: "storage-failed")
    defer { app.terminate() }
    tap(tabButton("仪表盘", app: app), app: app)
    let episodes = app.descendants(matching: .any)["native-dashboard-metric-episodes"].firstMatch
    let retry = app.buttons["native-dashboard-retry"]
    XCTAssertTrue(episodes.waitForExistence(timeout: 10))
    XCTAssertTrue((episodes.value as? String)?.contains("总量暂未获取") == true)
    XCTAssertTrue(retry.exists)
    try await configure("a", mode: "ready")
    tap(retry, app: app)
    let storage = app.descendants(matching: .any)["native-dashboard-storage"].firstMatch
    XCTAssertTrue(storage.waitForExistence(timeout: 10))
    capture("native-v2-dashboard")
    XCTAssertTrue(app.staticTexts["合成媒体库扫描"].exists)
    XCTAssertFalse(retry.exists)
    XCTAssertEqual(app.webViews.count, 0)
    let counts = try await stats()
    XCTAssertEqual(counts["a"]?["GET api/v1/dashboard/storage"], 2)
    XCTAssertEqual(counts["a"]?["GET api/v1/dashboard/statistic"], 2)
    XCTAssertEqual(counts["a"]?["GET api/v1/dashboard/schedule"], 2)
    XCTAssertEqual(counts["unexpected"], [:])
  }

  /// 单独授权 PT 搜索的普通账号仍能管理本身会话，影视和管理端点保持不可达。
  func testNativeBusinessHidesUnpermittedEntries() async throws {
    let app = try await signInToNativeBusiness("b", mode: "resource-search-only")
    defer { app.terminate() }
    assertAccount("b", app: app)
    capture("native-v2-account")
    XCTAssertFalse(tabButton("发现", app: app).exists)
    XCTAssertFalse(tabButton("搜索", app: app).exists)
    XCTAssertFalse(tabButton("仪表盘", app: app).exists)
    let counts = try await stats()
    XCTAssertTrue(
      counts["b"]?.keys.allSatisfy {
        !$0.contains("/discover/") && !$0.contains("/media/") && !$0.contains("/dashboard/")
      } == true)
    XCTAssertEqual(counts["unexpected"], [:])
  }

  /// 从真实连接与登录进入当前会话，等待业务壳出现但保留它的默认选项。
  private func signInToNativeBusiness(_ profile: String = "a", mode: String = "ready")
    async throws -> XCUIApplication
  {
    try await configure(profile, mode: mode, reset: true)
    let app = try cleanPicker()
    connect(profile, app: app)
    enterCredentials(profile, app: app)
    tap(app.buttons["native-v2-login"], app: app)
    XCTAssertTrue(tabButton("我的", app: app).waitForExistence(timeout: 15))
    return app
  }

  /// iPhone 底栏与 iPad 顶部浮动标签栏结构不同，统一解析当前平台的原生标签按钮。
  private func tabButton(_ label: String, app: XCUIApplication) -> XCUIElement {
    let tabBarButton = app.tabBars.buttons[label]
    if tabBarButton.exists { return tabBarButton }
    return app.buttons[label].firstMatch
  }

  /// 等待主画面上的真实图片代理回执，确保截图记录的是已渲染海报。
  private func waitForArtwork(_ profile: String, minimum: Int) async throws {
    let deadline = Date.now.addingTimeInterval(12)
    while Date.now < deadline {
      let current = try await stats()
      if (current[profile]?["image-served"] ?? 0) >= minimum { return }
      try await Task.sleep(nanoseconds: 200_000_000)
    }
    XCTFail("未收到足够的图片代理回执，未能确认海报加载。")
  }

  /// 以同一原生拖动距离采集首屏、文字上移、主视觉退出和正文四个连续位置。
  private func captureDiscoverScrollPhases(_ app: XCUIApplication, prefix: String) {
    let window = app.windows.firstMatch.frame
    let origin = app.coordinate(withNormalizedOffset: .zero)
    capture(prefix + "-phase-1")
    for phase in 2...4 {
      origin.withOffset(CGVector(dx: window.midX, dy: window.height * 0.70)).press(
        forDuration: 0.05,
        thenDragTo: origin.withOffset(CGVector(dx: window.midX, dy: window.height * 0.445)),
        withVelocity: .slow, thenHoldForDuration: 0.2)
      capture(prefix + "-phase-\(phase)")
    }
  }

  /// 来源节点的 0 不应被预选为周一，无改保存保留空格原文，主动选周日后才写 sun。
  func testPluginCronNumericWeekdayPreservesSource() async throws {
    let app = try await pluginAccount()
    try await verifyNumericWeekday(app, evidenceLabel: "normal")
    app.terminate()
  }

  /// 数字星期说明、自定义输入与显式选值在最大字号横屏下仍可操作并完整保存。
  func testPluginCronNumericWeekdayLargestTypeLandscape() async throws {
    let app = try await pluginAccount(extra: [
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
      "-AppleInterfaceStyle", "Light",
    ])
    defer {
      app.terminate()
      XCUIDevice.shared.orientation = .portrait
    }
    XCUIDevice.shared.orientation = .landscapeLeft
    try await verifyNumericWeekday(app, evidenceLabel: "largest")
  }

  /// 在真实 API-only 原生入口完成无改与改选两次保存，独立检查完整服务端回执。
  private func verifyNumericWeekday(_ app: XCUIApplication, evidenceLabel: String) async throws {
    let original = " 0 3 * * 0  "
    let plugin = "LibraryIntegrityWeekdayFixture"
    openPlugin(plugin, initialControl: "native-plugin-field-cron", app: app)
    openCron("cron", app: app)
    XCTAssertEqual(app.textFields["native-cron-expression"].value as? String, original)
    reveal(app.staticTexts["数字星期由插件解释；改选时使用星期名称。"].firstMatch, app: app)
    capture("cinematic-weekday-dialect-expression-" + evidenceLabel)
    tap(app.buttons["native-cron-unit-weekday"], app: app)
    XCTAssertTrue(app.buttons["native-cron-mode"].label.contains("自定义"))
    let custom = app.textFields["native-cron-custom-field"]
    reveal(custom, app: app)
    XCTAssertEqual(custom.value as? String, "0")
    XCTAssertFalse(app.buttons["native-cron-choice-weekday-0"].exists)
    capture("cinematic-weekday-dialect-custom-" + evidenceLabel)
    tap(app.buttons["native-cron-field-apply"], app: app)
    tap(app.buttons["native-cron-apply"], app: app)
    XCTAssertFalse(app.buttons["native-plugin-form-back"].exists)
    tap(app.buttons["native-plugin-form-save"], app: app)
    reveal(app.staticTexts["native-plugin-form-saved"], app: app)
    var state = try await pluginState()
    XCTAssertEqual(try cronModel(state, plugin: plugin)["cron"] as? String, original)
    openCron("cron", app: app)
    tap(app.buttons["native-cron-unit-weekday"], app: app)
    chooseCronMode("指定值", app: app)
    XCTAssertFalse(app.buttons["native-cron-field-apply"].isEnabled)
    tap(app.buttons["native-cron-choice-weekday-6"], app: app)
    XCTAssertTrue(app.buttons["native-cron-field-apply"].isEnabled)
    capture("cinematic-weekday-dialect-choice-" + evidenceLabel)
    tap(app.buttons["native-cron-field-apply"], app: app)
    tap(app.buttons["native-cron-apply"], app: app)
    tap(app.buttons["native-plugin-form-save"], app: app)
    reveal(app.staticTexts["native-plugin-form-saved"], app: app)
    state = try await pluginState()
    let model = try cronModel(state, plugin: plugin)
    XCTAssertEqual(model["cron"] as? String, "0 3 * * sun")
    XCTAssertEqual((model["future"] as? [String: Any])?["integer"] as? Int64, 9_007_199_254_740_993)
    XCTAssertEqual((state["counts"] as? [String: Int])?["PUT a/api/v1/plugin/" + plugin], 2)
    XCTAssertEqual((state["receipts"] as? [[String: Any]])?.count, 2)
    XCTAssertTrue((state["unexpected"] as? [String: Int])?.isEmpty == true)
    XCTAssertEqual(app.webViews.count, 0)
  }

  /// 完整官方 Cron 表单从真实入口编辑月底计划，添加缺省模型外的绑定并完整保存/重读。
  func testPluginCronSourceBuilderSavesCompletePhysicalForm() async throws {
    let app = try await pluginAccount()
    openPlugin("LibraryScraper_copy", app: app)
    capture("cinematic-cron-source-form")
    openCron("cron", app: app)
    XCTAssertEqual(app.textFields["native-cron-expression"].value as? String, "0 0 */7 * *")
    capture("cinematic-cron-expression-editor")
    tap(app.buttons["native-cron-unit-day"], app: app)
    XCTAssertTrue(app.navigationBars["日期"].waitForExistence(timeout: 5))
    chooseCronMode("月底", app: app)
    XCTAssertEqual(app.staticTexts["native-cron-field-preview"].label, "last")
    tap(app.buttons["native-cron-field-apply"], app: app)
    XCTAssertEqual(app.textFields["native-cron-expression"].value as? String, "0 0 last * *")
    capture("cinematic-cron-last-day")
    tap(app.buttons["native-cron-apply"], app: app)
    reveal(app.textFields["native-plugin-field-cron"], app: app)
    XCTAssertEqual(app.textFields["native-plugin-field-cron"].value as? String, "0 0 last * *")
    var state = try await pluginState()
    XCTAssertNil((state["counts"] as? [String: Int])?["PUT a/api/v1/plugin/LibraryScraper_copy"])
    let excluded = app.textViews["native-plugin-field-exclude_paths"]
    tap(excluded, app: app)
    excluded.typeText("/media/skip")
    dismissKeyboard(app)
    tap(app.buttons["native-plugin-form-save"], app: app)
    reveal(app.staticTexts["native-plugin-form-saved"], app: app)
    state = try await pluginState()
    let model = try cronModel(state, plugin: "LibraryScraper_copy")
    XCTAssertEqual(model["cron"] as? String, "0 0 last * *")
    XCTAssertEqual(model["exclude_paths"] as? String, "/media/skip")
    XCTAssertEqual(model["err_hosts"] as? String, "")
    XCTAssertEqual((model["future"] as? [String: Any])?["integer"] as? Int64, 9_007_199_254_740_993)
    XCTAssertEqual(
      (state["counts"] as? [String: Int])?["PUT a/api/v1/plugin/LibraryScraper_copy"], 1)
    XCTAssertNil((state["counts"] as? [String: Int])?["PUT a/api/v1/plugin/LibraryScraper"])
    app.navigationBars["媒体库刮削"].buttons.element(boundBy: 0).tap()
    tap(app.buttons["native-plugin-LibraryScraper_copy"], app: app)
    reveal(app.textFields["native-plugin-field-cron"], app: app)
    XCTAssertEqual(app.textFields["native-plugin-field-cron"].value as? String, "0 0 last * *")
    XCTAssertTrue((state["unexpected"] as? [String: Int])?.isEmpty == true)
    XCTAssertEqual(app.webViews.count, 0)
    app.terminate()
  }

  /// 原样应用/取消保留数字、null 和缺失字段；清除/手动编辑才改变父草稿的类型和值。
  func testPluginCronPreservesTypesCancelsAndClearsExplicitly() async throws {
    let app = try await pluginAccount()
    openPlugin("CronCompatibilityFixture", app: app)
    openCron("cron", app: app)
    XCTAssertEqual(app.textFields["native-cron-expression"].value as? String, "6")
    capture("cinematic-cron-plugin-specific-value")
    tap(app.buttons["native-cron-apply"], app: app)
    XCTAssertFalse(app.buttons["native-plugin-form-back"].exists)
    openCron("empty", app: app)
    XCTAssertFalse(app.buttons["native-cron-empty"].exists)
    tap(app.buttons["native-cron-apply"], app: app)
    openCron("missing", app: app)
    tap(app.buttons["native-cron-apply"], app: app)
    XCTAssertFalse(app.buttons["native-plugin-form-back"].exists)
    tap(app.buttons["native-plugin-form-save"], app: app)
    reveal(app.staticTexts["native-plugin-form-saved"], app: app)
    var state = try await pluginState()
    var model = try cronModel(state, plugin: "CronCompatibilityFixture")
    XCTAssertEqual((model["cron"] as? NSNumber)?.intValue, 6)
    XCTAssertFalse(model["cron"] is String)
    XCTAssertTrue(model["empty"] is NSNull)
    XCTAssertNil(model["missing"])
    openCron("cron", app: app)
    chooseCronPreset("weekdays", app: app)
    XCTAssertEqual(app.textFields["native-cron-expression"].value as? String, "0 9 * * mon-fri")
    tap(app.buttons["native-cron-cancel"], app: app)
    XCTAssertEqual(app.textFields["native-plugin-field-cron"].value as? String, "6")
    XCTAssertFalse(app.buttons["native-plugin-form-back"].exists)
    tap(app.buttons["native-plugin-cron-clear-cron"], app: app)
    tap(app.buttons["native-plugin-form-save"], app: app)
    reveal(app.staticTexts["native-plugin-form-saved"], app: app)
    state = try await pluginState()
    model = try cronModel(state, plugin: "CronCompatibilityFixture")
    XCTAssertTrue(model["cron"] is NSNull)
    XCTAssertTrue(model["empty"] is NSNull)
    XCTAssertNil(model["missing"])
    replacePluginInput("cron", with: "6.5", app: app)
    tap(app.buttons["native-plugin-form-save"], app: app)
    reveal(app.staticTexts["native-plugin-form-saved"], app: app)
    state = try await pluginState()
    model = try cronModel(state, plugin: "CronCompatibilityFixture")
    XCTAssertEqual(model["cron"] as? String, "6.5")
    XCTAssertEqual(
      (state["counts"] as? [String: Int])?["PUT a/api/v1/plugin/CronCompatibilityFixture"], 3)
    XCTAssertEqual(app.webViews.count, 0)
    app.terminate()
  }

  /// 原生间隔字段的连续调整不会读旧值；退回取消字段、保存失败与显式重试分别生效。
  func testPluginCronStepEditingCancellationAndSaveRetry() async throws {
    let app = try await pluginAccount()
    openPlugin("LibraryScraper_copy", app: app)
    openCron("cron", app: app)
    chooseCronPreset("quarterHourly", app: app)
    tap(app.buttons["native-cron-unit-minute"], app: app)
    XCTAssertTrue(app.navigationBars["分钟"].waitForExistence(timeout: 5))
    incrementCronStep(app)
    incrementCronStep(app)
    XCTAssertEqual(app.staticTexts["native-cron-field-preview"].label, "*/17")
    capture("cinematic-cron-minute-step")
    app.navigationBars["分钟"].buttons.element(boundBy: 0).tap()
    XCTAssertEqual(app.textFields["native-cron-expression"].value as? String, "*/15 * * * *")
    tap(app.buttons["native-cron-unit-minute"], app: app)
    incrementCronStep(app)
    incrementCronStep(app)
    tap(app.buttons["native-cron-field-apply"], app: app)
    XCTAssertEqual(app.textFields["native-cron-expression"].value as? String, "*/17 * * * *")
    tap(app.buttons["native-cron-apply"], app: app)
    try await configurePlugins(mode: "fail_save_once")
    tap(app.buttons["native-plugin-form-save"], app: app)
    reveal(app.staticTexts["native-plugin-form-error"], app: app)
    reveal(app.textFields["native-plugin-field-cron"], app: app)
    XCTAssertEqual(app.textFields["native-plugin-field-cron"].value as? String, "*/17 * * * *")
    let failed = try await pluginState()
    XCTAssertTrue((failed["receipts"] as? [[String: Any]])?.isEmpty == true)
    tap(app.buttons["native-plugin-form-save"], app: app)
    reveal(app.staticTexts["native-plugin-form-saved"], app: app)
    let state = try await pluginState()
    XCTAssertEqual(
      try cronModel(state, plugin: "LibraryScraper_copy")["cron"] as? String, "*/17 * * * *")
    XCTAssertEqual(
      (state["counts"] as? [String: Int])?["PUT a/api/v1/plugin/LibraryScraper_copy"], 2)
    app.terminate()
  }

  /// 最大字号和横屏下可选星期、纠正空选集、应用并保存，表达式用 sun 明确星期日。
  func testPluginCronLargestTypeLandscapeSelection() async throws {
    let app = try await pluginAccount(extra: [
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
      "-AppleInterfaceStyle", "Light",
    ])
    openPlugin("LibraryScraper_copy", app: app)
    openCron("cron", app: app)
    XCUIDevice.shared.orientation = .landscapeLeft
    chooseCronPreset("weekdays", app: app)
    tap(app.buttons["native-cron-unit-weekday"], app: app)
    XCTAssertTrue(app.navigationBars["星期"].waitForExistence(timeout: 5))
    chooseCronMode("指定值", app: app)
    tap(app.buttons["native-cron-choice-weekday-0"], app: app)
    XCTAssertFalse(app.buttons["native-cron-field-apply"].isEnabled)
    tap(app.buttons["native-cron-choice-weekday-6"], app: app)
    XCTAssertTrue(app.buttons["native-cron-field-apply"].isEnabled)
    capture("cinematic-cron-largest-weekday")
    tap(app.buttons["native-cron-field-apply"], app: app)
    reveal(app.textFields["native-cron-expression"], app: app)
    XCTAssertEqual(app.textFields["native-cron-expression"].value as? String, "0 9 * * sun")
    capture("cinematic-cron-largest-expression")
    tap(app.buttons["native-cron-apply"], app: app)
    tap(app.buttons["native-plugin-form-save"], app: app)
    reveal(app.staticTexts["native-plugin-form-saved"], app: app)
    let state = try await pluginState()
    XCTAssertEqual(
      try cronModel(state, plugin: "LibraryScraper_copy")["cron"] as? String, "0 9 * * sun")
    XCTAssertEqual(app.webViews.count, 0)
    app.terminate()
    XCUIDevice.shared.orientation = .portrait
  }

  /// 小时范围、月份选值和自定义字段分别跳转；整层取消不会泄漏任一字段草稿或发出 PUT。
  func testPluginCronRangeMonthAndCustomCancellation() async throws {
    let app = try await pluginAccount()
    openPlugin("LibraryScraper_copy", app: app)
    openCron("cron", app: app)
    chooseCronPreset("daily", app: app)
    tap(app.buttons["native-cron-unit-hour"], app: app)
    XCTAssertTrue(app.navigationBars["小时"].waitForExistence(timeout: 5))
    chooseCronMode("范围", app: app)
    let start = app.steppers["native-cron-range-start"]
    reveal(start, app: app)
    start.buttons.element(boundBy: 1).tap()
    let end = app.steppers["native-cron-range-end"]
    reveal(end, app: app)
    end.buttons.element(boundBy: 0).tap()
    XCTAssertEqual(app.staticTexts["native-cron-field-preview"].label, "1-22")
    tap(app.buttons["native-cron-field-apply"], app: app)
    tap(app.buttons["native-cron-unit-month"], app: app)
    XCTAssertTrue(app.navigationBars["月份"].waitForExistence(timeout: 5))
    chooseCronMode("指定值", app: app)
    tap(app.buttons["native-cron-choice-month-12"], app: app)
    tap(app.buttons["native-cron-field-apply"], app: app)
    reveal(app.textFields["native-cron-expression"], app: app)
    XCTAssertEqual(app.textFields["native-cron-expression"].value as? String, "0 1-22 * 1,12 *")
    tap(app.buttons["native-cron-unit-month"], app: app)
    chooseCronMode("自定义", app: app)
    let token = app.textFields["native-cron-custom-field"]
    tap(token, app: app)
    token.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "jan-mar")
    dismissKeyboard(app)
    tap(app.buttons["native-cron-field-apply"], app: app)
    reveal(app.textFields["native-cron-expression"], app: app)
    XCTAssertEqual(app.textFields["native-cron-expression"].value as? String, "0 1-22 * jan-mar *")
    capture("cinematic-cron-range-month-custom")
    tap(app.buttons["native-cron-cancel"], app: app)
    XCTAssertEqual(app.textFields["native-plugin-field-cron"].value as? String, "0 0 */7 * *")
    let state = try await pluginState()
    XCTAssertNil((state["counts"] as? [String: Int])?["PUT a/api/v1/plugin/LibraryScraper_copy"])
    XCTAssertFalse(app.buttons["native-plugin-form-back"].exists)
    app.terminate()
  }

  /// 只通过真实 Cron 字段上的原生动作打开计划弹层。
  private func openCron(_ field: String, app: XCUIApplication) {
    tap(app.buttons["native-plugin-cron-edit-" + field], app: app)
    XCTAssertTrue(app.textFields["native-cron-expression"].waitForExistence(timeout: 5))
  }

  /// 使用原生菜单显式选择预设，不从空值自动生成周期。
  private func chooseCronPreset(_ id: String, app: XCUIApplication) {
    tap(app.buttons["native-cron-presets"], app: app)
    let preset = app.buttons["native-cron-preset-" + id]
    XCTAssertTrue(preset.waitForExistence(timeout: 5))
    preset.tap()
  }

  /// 模式通过可滚动原生选择页操作，未实现字段不借测试参数直接赋值。
  private func chooseCronMode(_ title: String, app: XCUIApplication) {
    tap(app.descendants(matching: .any)["native-cron-mode"].firstMatch, app: app)
    XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 5))
    tap(app.buttons[title], app: app)
  }

  /// 标准 Stepper 的右侧增量按钮连续操作，验证绑定读取当前草稿而非渲染快照。
  private func incrementCronStep(_ app: XCUIApplication) {
    let stepper = app.steppers["native-cron-step-interval"]
    reveal(stepper, app: app)
    XCTAssertEqual(stepper.buttons.count, 2)
    stepper.buttons.element(boundBy: 1).tap()
  }

  /// 回执之外独立读取服务端完整模型，验证未来字段/类型与新绑定都在实际载荷中。
  private func cronModel(_ state: [String: Any], plugin: String) throws -> [String: Any] {
    try XCTUnwrap((state["models"] as? [String: [String: Any]])?[plugin])
  }

  /// 真实来源对象预设、取消、重读及自定义字符串都通过原生编辑器操作，不自动发 PUT。
  func testPluginComboboxPresetObjectCustomAndCancel() async throws {
    let app = try await pluginAccount()
    let plugin = "CertManagerCombobox_copy"
    openPlugin(plugin, initialControl: "native-plugin-field-dns_provider", app: app)
    openCombobox("dns_provider", app: app)
    capture("cinematic-combobox-source-object")
    tap(app.buttons["native-combobox-option-2"], app: app)
    tap(app.buttons["native-combobox-cancel"], app: app)
    XCTAssertTrue(app.buttons["native-plugin-field-dns_provider"].label.contains("历史 DNS 预设"))
    var state = try await pluginState()
    XCTAssertTrue((state["receipts"] as? [[String: Any]])?.isEmpty == true)
    openCombobox("dns_provider", app: app)
    tap(app.buttons["native-combobox-option-2"], app: app)
    tap(app.buttons["native-combobox-apply"], app: app)
    tap(app.buttons["native-plugin-form-save"], app: app)
    reveal(app.staticTexts["native-plugin-form-saved"], app: app)
    state = try await pluginState()
    var model = try cronModel(state, plugin: plugin)
    let provider = try XCTUnwrap(model["dns_provider"] as? [String: Any])
    XCTAssertEqual(provider["title"] as? String, "Cloudflare")
    XCTAssertEqual(provider["value"] as? String, "dns_cf")
    XCTAssertEqual(provider.count, 2)
    app.navigationBars.buttons.element(boundBy: 0).tap()
    tap(app.buttons["native-plugin-" + plugin], app: app)
    XCTAssertTrue(app.buttons["native-plugin-field-dns_provider"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["native-plugin-field-dns_provider"].label.contains("Cloudflare"))
    openCombobox("dns_provider", app: app)
    let input = app.textFields["native-combobox-input"]
    tap(input, app: app)
    input.typeText(" dns_custom ")
    capture("cinematic-combobox-custom-input")
    // 不先按加号，应用必须接收尚在输入框的文字，且保留空格。
    tap(app.buttons["native-combobox-apply"], app: app)
    state = try await pluginState()
    XCTAssertEqual((state["receipts"] as? [[String: Any]])?.count, 1)
    tap(app.buttons["native-plugin-form-save"], app: app)
    reveal(app.staticTexts["native-plugin-form-saved"], app: app)
    state = try await pluginState()
    model = try cronModel(state, plugin: plugin)
    XCTAssertEqual(model["dns_provider"] as? String, " dns_custom ")
    XCTAssertEqual((model["future"] as? [String: Any])?["integer"] as? Int64, 9_007_199_254_740_993)
    XCTAssertEqual((state["counts"] as? [String: Int])?["PUT a/api/v1/plugin/" + plugin], 2)
    XCTAssertEqual((state["counts"] as? [String: Int])?["GET a/api/v1/plugin/form/" + plugin], 2)
    XCTAssertTrue((state["unexpected"] as? [String: Int])?.isEmpty == true)
    XCTAssertEqual(app.webViews.count, 0)
    app.terminate()
  }

  /// 无预设多选保留历史对象；失败不自动重试，明确重试、删除和清空才改变完整配置。
  func testPluginComboboxMultipleValuesAndFailedSaveRetainDraft() async throws {
    let app = try await pluginAccount()
    let plugin = "LibraryCombobox_copy"
    openPlugin(plugin, initialControl: "native-plugin-field-libraries", app: app)
    openCombobox("libraries", app: app)
    addComboboxInput("Films", app: app)
    let input = app.textFields["native-combobox-input"]
    tap(input, app: app)
    input.typeText("TV")
    tap(app.buttons["native-combobox-apply"], app: app)
    try await configurePlugins(mode: "fail_save_once")
    tap(app.buttons["native-plugin-form-save"], app: app)
    reveal(app.staticTexts["native-plugin-form-error"], app: app)
    var state = try await pluginState()
    XCTAssertEqual((state["counts"] as? [String: Int])?["PUT a/api/v1/plugin/" + plugin], 1)
    XCTAssertTrue((state["receipts"] as? [[String: Any]])?.isEmpty == true)
    openCombobox("libraries", app: app)
    XCTAssertTrue(app.staticTexts["native-combobox-current-2"].label.contains("Films"))
    XCTAssertTrue(app.staticTexts["native-combobox-current-3"].label.contains("TV"))
    tap(app.buttons["native-combobox-remove-0"], app: app)
    addComboboxInput("Anime", app: app)
    capture("cinematic-combobox-multiple-values")
    tap(app.buttons["native-combobox-apply"], app: app)
    tap(app.buttons["native-plugin-form-save"], app: app)
    reveal(app.staticTexts["native-plugin-form-saved"], app: app)
    state = try await pluginState()
    let model = try cronModel(state, plugin: plugin)
    let values = try XCTUnwrap(model["libraries"] as? [Any])
    XCTAssertEqual(values.count, 4)
    XCTAssertEqual((values.first as? [String: Any])?["future"] as? Int64, 9_007_199_254_740_993)
    XCTAssertEqual(Array(values.dropFirst()) as? [String], ["Films", "TV", "Anime"])
    XCTAssertEqual((model["future"] as? [String: Any])?["integer"] as? Int64, 9_007_199_254_740_993)
    openCombobox("libraries", app: app)
    tap(app.buttons["native-combobox-clear"], app: app)
    tap(app.buttons["native-combobox-cancel"], app: app)
    openCombobox("libraries", app: app)
    XCTAssertTrue(app.staticTexts["native-combobox-current-3"].exists)
    tap(app.buttons["native-combobox-clear"], app: app)
    tap(app.buttons["native-combobox-apply"], app: app)
    tap(app.buttons["native-plugin-form-save"], app: app)
    reveal(app.staticTexts["native-plugin-form-saved"], app: app)
    state = try await pluginState()
    XCTAssertEqual((try cronModel(state, plugin: plugin))["libraries"] as? [String], [])
    XCTAssertEqual((state["counts"] as? [String: Int])?["PUT a/api/v1/plugin/" + plugin], 3)
    XCTAssertEqual((state["receipts"] as? [[String: Any]])?.count, 2)
    XCTAssertTrue((state["unexpected"] as? [String: Int])?.isEmpty == true)
    XCTAssertEqual(app.webViews.count, 0)
    app.terminate()
  }

  /// 原样应用不新增缺失键或改写 null，returnObject=false 的大整数和字符串保持类型。
  func testPluginComboboxScalarNullAndMissingTypes() async throws {
    let app = try await pluginAccount()
    let plugin = "ComboboxModesFixture"
    openPlugin(plugin, initialControl: "native-plugin-field-choice", app: app)
    for key in ["empty", "missing"] {
      openCombobox(key, app: app)
      tap(app.buttons["native-combobox-apply"], app: app)
    }
    tap(app.buttons["native-plugin-form-save"], app: app)
    reveal(app.staticTexts["native-plugin-form-saved"], app: app)
    var state = try await pluginState()
    var model = try cronModel(state, plugin: plugin)
    XCTAssertTrue(model["empty"] is NSNull)
    XCTAssertNil(model["missing"])
    for (index, expected) in [(2, "9007199254740993"), (1, "1")] {
      openCombobox("choice", app: app)
      tap(app.buttons["native-combobox-option-\(index)"], app: app)
      tap(app.buttons["native-combobox-apply"], app: app)
      tap(app.buttons["native-plugin-form-save"], app: app)
      reveal(app.staticTexts["native-plugin-form-saved"], app: app)
      state = try await pluginState()
      model = try cronModel(state, plugin: plugin)
      if index == 2 {
        XCTAssertEqual(model["choice"] as? Int64, 9_007_199_254_740_993)
        XCTAssertFalse(model["choice"] is String)
      } else {
        XCTAssertEqual(model["choice"] as? String, expected)
      }
      XCTAssertTrue(model["empty"] is NSNull)
      XCTAssertNil(model["missing"])
    }
    openCombobox("choice", app: app)
    tap(app.buttons["native-combobox-clear"], app: app)
    tap(app.buttons["native-combobox-apply"], app: app)
    tap(app.buttons["native-plugin-form-save"], app: app)
    reveal(app.staticTexts["native-plugin-form-saved"], app: app)
    state = try await pluginState()
    XCTAssertTrue((try cronModel(state, plugin: plugin))["choice"] is NSNull)
    XCTAssertEqual((state["counts"] as? [String: Int])?["PUT a/api/v1/plugin/" + plugin], 4)
    XCTAssertEqual(app.webViews.count, 0)
    app.terminate()
  }

  /// 最大字号与横屏下候选列表、键盘和应用动作都必须可达，继续使用统一 Cinematic 表面。
  func testPluginComboboxLargestTypeRemainsReachable() async throws {
    let app = try await pluginAccount(extra: [
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ])
    defer {
      app.terminate()
      XCUIDevice.shared.orientation = .portrait
    }
    XCUIDevice.shared.orientation = .landscapeLeft
    openPlugin(
      "CertManagerCombobox_copy", initialControl: "native-plugin-field-dns_provider", app: app)
    openCombobox("dns_provider", app: app)
    tap(app.buttons["native-combobox-option-13"], app: app)
    capture("cinematic-combobox-largest-landscape")
    let input = app.textFields["native-combobox-input"]
    tap(input, app: app)
    input.typeText("dns_custom")
    tap(app.buttons["native-combobox-apply"], app: app)
    tap(app.buttons["native-plugin-form-save"], app: app)
    reveal(app.staticTexts["native-plugin-form-saved"], app: app)
    let state = try await pluginState()
    XCTAssertEqual(
      (try cronModel(state, plugin: "CertManagerCombobox_copy"))["dns_provider"] as? String,
      "dns_custom")
    XCTAssertEqual(app.webViews.count, 0)
  }

  /// 原生弹层从所属字段打开，并等待可输入的实际控件而非依赖固定延迟。
  private func openCombobox(_ key: String, app: XCUIApplication) {
    tap(app.buttons["native-plugin-field-" + key], app: app)
    XCTAssertTrue(app.textFields["native-combobox-input"].waitForExistence(timeout: 5))
  }

  /// 加号与应用中的待输入分别验证，全部字符经真实系统输入控件产生。
  private func addComboboxInput(_ text: String, app: XCUIApplication) {
    let input = app.textFields["native-combobox-input"]
    tap(input, app: app)
    input.typeText(text)
    tap(app.buttons["native-combobox-add"], app: app)
  }

  /// 完整官方表单经真实原生入口修改/保存/重读，未知字段和大整数原样保留。
  func testPluginSourceFormSavesCompletePhysicalConfiguration() async throws {
    let app = try await pluginAccount()
    openPlugin("MediaDirWatcher_copy", app: app)
    capture("cinematic-plugin-form-source-top")
    toggle("native-plugin-field-enabled", to: true, app: app)
    tap(app.buttons["native-plugin-field-media_type"], app: app)
    XCTAssertTrue(app.buttons["native-plugin-option-1"].waitForExistence(timeout: 5))
    capture("cinematic-plugin-form-single-selection")
    tap(app.buttons["native-plugin-option-1"], app: app)
    replacePluginInput("scan_interval", with: "7", app: app)
    let paths = app.textViews["native-plugin-field-monitor_paths"]
    tap(paths, app: app)
    paths.typeText("/media/Films\n/media/TV")
    dismissKeyboard(app)
    capture("cinematic-plugin-form-source-fields")
    tap(app.buttons["native-plugin-form-save"], app: app)
    reveal(app.staticTexts["native-plugin-form-saved"], app: app)
    var state = try await pluginState()
    let receipts = try XCTUnwrap(state["receipts"] as? [[String: Any]])
    XCTAssertEqual(receipts.count, 1)
    XCTAssertEqual(receipts[0]["plugin"] as? String, "MediaDirWatcher_copy")
    let model = try XCTUnwrap(receipts[0]["model"] as? [String: Any])
    XCTAssertEqual(model.count, 10)
    XCTAssertEqual(model["enabled"] as? Bool, true)
    XCTAssertEqual(model["media_type"] as? String, "电影")
    XCTAssertEqual(model["scan_interval"] as? String, "7")
    XCTAssertEqual(model["monitor_paths"] as? String, "/media/Films\n/media/TV")
    XCTAssertEqual(model["notify"] as? Bool, true)
    XCTAssertEqual((model["future"] as? [String: Any])?["integer"] as? Int64, 9_007_199_254_740_993)
    app.navigationBars.buttons.element(boundBy: 0).tap()
    tap(app.buttons["native-plugin-MediaDirWatcher_copy"], app: app)
    reveal(app.textFields["native-plugin-field-scan_interval"], app: app)
    XCTAssertEqual(app.textFields["native-plugin-field-scan_interval"].value as? String, "7")
    state = try await pluginState()
    let counts = try XCTUnwrap(state["counts"] as? [String: Int])
    XCTAssertEqual(counts["PUT a/api/v1/plugin/MediaDirWatcher_copy"], 1)
    XCTAssertEqual(counts["GET a/api/v1/plugin/form/MediaDirWatcher_copy"], 2)
    XCTAssertNil(counts["PUT a/api/v1/plugin/MediaDirWatcher"])
    XCTAssertTrue((state["unexpected"] as? [String: Int])?.isEmpty == true)
    XCTAssertEqual(app.webViews.count, 0)
    app.terminate()
  }

  /// 失败保留输入且没有自动重试；第二次明确保存才允许产生第二次 PUT。
  func testPluginFailedSaveRetainsDraftAndNeedsExplicitRetry() async throws {
    let app = try await pluginAccount()
    openPlugin("MediaDirWatcher_copy", app: app)
    replacePluginInput("notify_user", with: "42", app: app)
    try await configurePlugins(mode: "fail_save_once")
    tap(app.buttons["native-plugin-form-save"], app: app)
    reveal(app.staticTexts["native-plugin-form-error"], app: app)
    capture("cinematic-plugin-form-save-failure")
    var state = try await pluginState()
    XCTAssertEqual(
      (state["counts"] as? [String: Int])?["PUT a/api/v1/plugin/MediaDirWatcher_copy"], 1)
    XCTAssertTrue((state["receipts"] as? [[String: Any]])?.isEmpty == true)
    XCUIDevice.shared.press(.home)
    app.activate()
    reveal(app.textFields["native-plugin-field-notify_user"], app: app)
    XCTAssertEqual(app.textFields["native-plugin-field-notify_user"].value as? String, "42")
    state = try await pluginState()
    XCTAssertEqual(
      (state["counts"] as? [String: Int])?["PUT a/api/v1/plugin/MediaDirWatcher_copy"], 1)
    tap(app.buttons["native-plugin-form-save"], app: app)
    reveal(app.staticTexts["native-plugin-form-saved"], app: app)
    state = try await pluginState()
    XCTAssertEqual(
      (state["counts"] as? [String: Int])?["PUT a/api/v1/plugin/MediaDirWatcher_copy"], 2)
    XCTAssertEqual((state["receipts"] as? [[String: Any]])?.count, 1)
    app.terminate()
  }

  /// 隐藏的未知组件仍禁用保存，放弃修改须经明确操作，不发送缩减配置。
  func testPluginUnsupportedHiddenComponentCannotSave() async throws {
    let app = try await pluginAccount()
    openPlugin("UnsupportedFixture", app: app)
    reveal(app.staticTexts["native-plugin-form-blocked"], app: app)
    XCTAssertFalse(app.buttons["native-plugin-form-save"].isEnabled)
    capture("cinematic-plugin-form-unsupported")
    toggle("native-plugin-field-enabled", to: true, app: app)
    XCTAssertFalse(app.buttons["native-plugin-form-save"].isEnabled)
    tap(app.buttons["native-plugin-form-back"], app: app)
    XCTAssertTrue(app.buttons["放弃修改"].waitForExistence(timeout: 5))
    app.buttons["取消"].tap()
    XCTAssertTrue(app.buttons["native-plugin-form-save"].exists)
    tap(app.buttons["native-plugin-form-back"], app: app)
    app.buttons["放弃修改"].tap()
    XCTAssertTrue(app.buttons["native-plugin-UnsupportedFixture"].waitForExistence(timeout: 5))
    let state = try await pluginState()
    XCTAssertNil((state["counts"] as? [String: Int])?["PUT a/api/v1/plugin/UnsupportedFixture"])
    XCTAssertTrue((state["receipts"] as? [[String: Any]])?.isEmpty == true)
    app.terminate()
  }

  /// 条件、多选值类型、未知旧选项、密码遮盖和数值校验在真实 UI 同时生效。
  func testPluginConditionalMultiSelectAndNumericValidation() async throws {
    let app = try await pluginAccount()
    openPlugin("NativeControlsFixture", app: app)
    XCTAssertFalse(app.textFields["native-plugin-field-path"].exists)
    tap(app.buttons["native-plugin-field-sources"], app: app)
    tap(app.buttons["native-plugin-option-1"], app: app)
    tap(app.buttons["native-plugin-option-2"], app: app)
    tap(app.buttons["native-plugin-option-0"], app: app)
    capture("cinematic-plugin-form-multiple-selection")
    tap(app.buttons["native-plugin-selection-done"], app: app)
    toggle("native-plugin-field-enabled", to: true, app: app)
    reveal(app.textFields["native-plugin-field-path"], app: app)
    XCTAssertEqual(app.textFields["native-plugin-field-path"].value as? String, "/media/preserved")
    reveal(app.secureTextFields["native-plugin-field-secret"], app: app)
    XCTAssertFalse(app.textFields["native-plugin-field-secret"].exists)
    tap(app.buttons["显示密码"], app: app)
    XCTAssertTrue(app.textFields["native-plugin-field-secret"].exists)
    XCUIDevice.shared.press(.home)
    app.activate()
    reveal(app.secureTextFields["native-plugin-field-secret"], app: app)
    XCTAssertFalse(app.textFields["native-plugin-field-secret"].exists)
    replacePluginInput("amount", with: "0", app: app)
    XCTAssertFalse(app.buttons["native-plugin-form-save"].isEnabled)
    replacePluginInput("amount", with: "7", app: app)
    XCTAssertTrue(app.buttons["native-plugin-form-save"].isEnabled)
    capture("cinematic-plugin-form-conditional-controls")
    tap(app.buttons["native-plugin-form-save"], app: app)
    reveal(app.staticTexts["native-plugin-form-saved"], app: app)
    let state = try await pluginState()
    let models = try XCTUnwrap(state["models"] as? [String: [String: Any]])
    let model = try XCTUnwrap(models["NativeControlsFixture"])
    XCTAssertEqual(model["sources"] as? NSArray, ["old", "1", 2] as NSArray)
    XCTAssertEqual(model["amount"] as? String, "7")
    XCTAssertEqual(model["path"] as? String, "/media/preserved")
    XCTAssertEqual(model["secret"] as? String, "fixture-only-private")
    XCTAssertEqual(app.webViews.count, 0)
    app.terminate()
  }

  /// 配置提交收到 401 后整个旧导航退出，旧草稿不能留在下一登录代次中。
  func testPluginExpiredSessionClosesOldNavigation() async throws {
    let app = try await pluginAccount()
    openPlugin("MediaDirWatcher_copy", app: app)
    toggle("native-plugin-field-enabled", to: true, app: app)
    try await configure("a", mode: "expired")
    tap(app.buttons["native-plugin-form-save"], app: app)
    XCTAssertTrue(app.textFields["native-v2-username"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["native-plugin-form-save"].exists)
    XCTAssertFalse(app.switches["native-plugin-field-enabled"].exists)
    let state = try await pluginState()
    XCTAssertEqual(
      (state["counts"] as? [String: Int])?["PUT a/api/v1/plugin/MediaDirWatcher_copy"], 1)
    XCTAssertTrue((state["receipts"] as? [[String: Any]])?.isEmpty == true)
    app.terminate()
  }

  /// 普通账号保持既有权限，没有配置入口或后台插件请求。
  func testPluginConfigurationRequiresAdministrator() async throws {
    let app = try await pluginAccount("b")
    XCTAssertFalse(app.buttons["native-v2-plugins"].exists)
    let state = try await pluginState()
    XCTAssertTrue((state["counts"] as? [String: Int])?.isEmpty == true)
    app.terminate()
  }

  /// 最大辅助字号/横屏仍可选择、输入和保存，透明度/动态辅助设置由设备真实状态提供。
  func testPluginLandscapeLargestTypeRemainsUsable() async throws {
    let app = try await pluginAccount(extra: [
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
      "-AppleInterfaceStyle", "Light",
    ])
    openPlugin("MediaDirWatcher_copy", app: app)
    XCUIDevice.shared.orientation = .landscapeLeft
    tap(app.buttons["native-plugin-field-media_type"], app: app)
    capture("cinematic-plugin-form-landscape-largest-selection")
    tap(app.buttons["native-plugin-option-2"], app: app)
    replacePluginInput("scan_interval", with: "8", app: app)
    capture("cinematic-plugin-form-landscape-largest")
    tap(app.buttons["native-plugin-form-save"], app: app)
    reveal(app.staticTexts["native-plugin-form-saved"], app: app)
    let state = try await pluginState()
    XCTAssertEqual((state["receipts"] as? [[String: Any]])?.count, 1)
    XCTAssertEqual(app.webViews.count, 0)
    app.terminate()
    XCUIDevice.shared.orientation = .portrait
  }

  /// 每个插件用例从真实原生登录开始，不能借 launch 参数注入已认证账号。
  private func pluginAccount(_ name: String = "a", extra: [String] = []) async throws
    -> XCUIApplication
  {
    guard ProcessInfo.processInfo.environment["MOVIEPILOT_NATIVE_V2_E2E"] == "1" else {
      throw XCTSkip("需要显式启动原生插件 API-only 本机夹具。")
    }
    try await configure(name, mode: "ready", reset: true)
    try await configurePlugins(reset: true)
    let app = try cleanPicker(extra: extra)
    connect(name, app: app)
    enterCredentials(name, app: app)
    tap(app.buttons["native-v2-login"], app: app)
    assertAccount(name, app: app)
    return app
  }

  /// 清单和配置加载都经真实按钮；等待各表单确实提供的首控件，而非假定所有插件都有开关。
  private func openPlugin(
    _ id: String, initialControl: String = "native-plugin-field-enabled", app: XCUIApplication
  ) {
    tap(app.buttons["native-v2-plugins"], app: app)
    let row = app.buttons["native-plugin-" + id]
    reveal(row, app: app)
    XCTAssertTrue(row.waitForExistence(timeout: 10))
    capture("cinematic-plugin-installed-list")
    tap(row, app: app)
    XCTAssertTrue(app.buttons["native-plugin-form-save"].waitForExistence(timeout: 10))
    reveal(app.descendants(matching: .any)[initialControl].firstMatch, app: app)
  }

  /// 输入由真实键盘产生；单字符数字测试不依赖粘贴或直接改草稿。
  private func replacePluginInput(_ key: String, with text: String, app: XCUIApplication) {
    let field = app.textFields["native-plugin-field-" + key]
    tap(field, app: app)
    let count = (field.value as? String)?.count ?? 0
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) + text)
    dismissKeyboard(app)
  }

  /// 控制端点仅改变回环合成插件的故障模式，不接触用户后端。
  private func configurePlugins(mode: String = "ready", reset: Bool = false) async throws {
    var request = URLRequest(url: URL(string: base + "__plugins/config")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: ["mode": mode, "reset": reset])
    let (_, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
  }

  /// 独立读取服务端实际 PUT 记录，UI 成功提示本身不能作为完整配置证明。
  private func pluginState() async throws -> [String: Any] {
    let (data, response) = try await URLSession.shared.data(
      from: URL(string: base + "__plugins/state")!)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  /// 浅色系统偏好下仍为 单一深色渐变玻璃风格，玻璃表单中的秘密可检查且暂离后恢复遮盖。
  func testCinematicFormControlsAndSecretConcealment() async throws {
    try await configure("new", mode: "new", reset: true)
    let app = try cleanPicker(extra: ["-AppleInterfaceStyle", "Light"])
    capture("cinematic-entry-connection-system-light")
    connect("new", app: app)
    let key = app.secureTextFields["native-v2-api-key"]
    reveal(key, app: app)
    capture("cinematic-entry-initialization-system-light")
    for identifier in [
      "native-v2-show-api-key", "native-v2-copy-api-key", "native-v2-show-password",
    ] {
      let button = app.buttons[identifier]
      reveal(button, app: app)
      // 像素到逻辑点的换算可能产生 43.99999999999994，仅容许浮点舍入误差。
      XCTAssertGreaterThanOrEqual(button.frame.width, 44 - 0.01)
      XCTAssertGreaterThanOrEqual(button.frame.height, 44 - 0.01)
    }
    tap(app.buttons["native-v2-show-api-key"], app: app)
    XCTAssertTrue(app.textFields["native-v2-api-key"].exists)
    tap(app.buttons["native-v2-show-password"], app: app)
    XCTAssertTrue(app.textFields["native-v2-password"].exists)
    XCUIDevice.shared.press(.home)
    let background = XCTNSPredicateExpectation(
      predicate: NSPredicate(
        format: "state == %d OR state == %d",
        XCUIApplication.State.runningBackground.rawValue,
        XCUIApplication.State.runningBackgroundSuspended.rawValue), object: app)
    XCTAssertEqual(XCTWaiter.wait(for: [background], timeout: 5), .completed)
    app.activate()
    XCTAssertTrue(app.secureTextFields["native-v2-password"].waitForExistence(timeout: 5))
    XCTAssertTrue(key.exists)
    XCTAssertFalse(app.textFields["native-v2-api-key"].exists)
    XCTAssertFalse(app.textFields["native-v2-password"].exists)
    XCTAssertEqual(key.value as? String, "API Key")
    tap(app.buttons["native-v2-regenerate-api-key"], app: app)
    XCTAssertNotEqual(key.value as? String, "API Key")
    XCTAssertEqual(app.webViews.count, 0)
    app.terminate()
  }

  /// 两个部署子路径的身份、可选密码和令牌跨切换/重启隔离，过期不能自动重发密码。
  func testSeparateInstancesRestorationAndExplicitPasswordMemory() async throws {
    try await configure("a", mode: "ready", reset: true)
    try await configure("b", mode: "ready", reset: true)
    let app = try cleanPicker()
    capture("native-v2-01-connection")
    connect("a", app: app)
    capture("native-v2-02-login")
    enterCredentials("a", app: app)
    toggle("native-v2-remember-password", to: true, app: app)
    tap(app.buttons["native-v2-login"], app: app)
    assertAccount("a", app: app)
    capture("native-v2-03-account")
    tap(app.buttons["native-v2-switch"], app: app)
    connect("b", app: app)
    XCTAssertEqual(app.textFields["native-v2-username"].value as? String, "用户名")
    XCTAssertEqual(app.switches["native-v2-remember-password"].value as? String, "0")
    enterCredentials("b", app: app)
    tap(app.buttons["native-v2-login"], app: app)
    assertAccount("b", app: app)
    tap(app.buttons["native-v2-switch"], app: app)
    select("a", app: app)
    assertAccount("a", app: app)
    app.terminate()
    app.launchArguments = arguments
    app.launch()
    assertAccount("a", app: app)
    var counts = try await stats()
    XCTAssertEqual(counts["a"]?["POST api/v1/login/access-token"], 1)
    XCTAssertEqual(counts["b"]?["POST api/v1/login/access-token"], 1)
    try await configure("a", mode: "expired", reset: true)
    tap(app.buttons["native-v2-refresh"], app: app)
    XCTAssertTrue(app.textFields["native-v2-username"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.textFields["native-v2-username"].value as? String, "native-a")
    XCTAssertEqual(app.switches["native-v2-remember-password"].value as? String, "1")
    counts = try await stats()
    XCTAssertNil(counts["a"]?["POST api/v1/login/access-token"])
    try await configure("a", mode: "ready")
    tap(app.buttons["native-v2-login"], app: app)
    assertAccount("a", app: app)
    tap(app.buttons["native-v2-logout"], app: app)
    XCTAssertTrue(app.textFields["native-v2-username"].waitForExistence(timeout: 10))
    toggle("native-v2-remember-password", to: false, app: app)
    tap(app.buttons["native-v2-change-server"], app: app)
    select("a", app: app)
    XCTAssertEqual(app.textFields["native-v2-username"].value as? String, "用户名")
    XCTAssertEqual(app.secureTextFields["native-v2-password"].value as? String, "密码")
    XCTAssertEqual(app.webViews.count, 0)
    counts = try await stats()
    XCTAssertTrue(counts["unexpected", default: [:]].isEmpty)
    app.terminate()
  }

  /// OTP 挑战保留显式提交语义，不保持登录时重启必须重新输入且不能偷偷恢复。
  func testOTPAndSessionNotRemembered() async throws {
    try await configure("a", mode: "otp", reset: true)
    let app = try cleanPicker()
    connect("a", app: app)
    enterCredentials("a", app: app)
    toggle("native-v2-remember-session", to: false, app: app)
    tap(app.buttons["native-v2-login"], app: app)
    let code = app.textFields["native-v2-otp"]
    XCTAssertTrue(code.waitForExistence(timeout: 10))
    capture("native-v2-04-otp")
    code.tap()
    code.typeText("012345")
    dismissKeyboard(app)
    tap(app.buttons["native-v2-login"], app: app)
    assertAccount("a", app: app)
    app.terminate()
    app.launchArguments = arguments
    app.launch()
    XCTAssertTrue(app.textFields["native-v2-username"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.textFields["native-v2-username"].value as? String, "用户名")
    XCTAssertFalse(app.textFields["native-v2-otp"].exists)
    let counts = try await stats()
    XCTAssertEqual(counts["a"]?["POST api/v1/login/access-token"], 2)
    XCTAssertNil(counts["a"]?["GET api/v1/user/current"])
    XCTAssertTrue(counts["unexpected", default: [:]].isEmpty)
    XCTAssertEqual(app.webViews.count, 0)
    app.terminate()
  }

  /// 刷新期间后台只取消该请求；未保持登录的活跃身份不能因暂离而被误注销。
  func testActiveMemorySessionSurvivesBackgroundDuringRefresh() async throws {
    try await configure("a", mode: "ready", reset: true)
    let app = try cleanPicker()
    connect("a", app: app)
    enterCredentials("a", app: app)
    toggle("native-v2-remember-session", to: false, app: app)
    tap(app.buttons["native-v2-login"], app: app)
    assertAccount("a", app: app)
    try await configure("a", mode: "slow")
    tap(app.buttons["native-v2-refresh"], app: app)
    let pending = app.descendants(matching: .any)["native-v2-progress"].firstMatch
    XCTAssertTrue(pending.exists)
    XCUIDevice.shared.press(.home)
    let background = XCTNSPredicateExpectation(
      predicate: NSPredicate(
        format: "state == %d OR state == %d",
        XCUIApplication.State.runningBackground.rawValue,
        XCUIApplication.State.runningBackgroundSuspended.rawValue), object: app)
    XCTAssertEqual(XCTWaiter.wait(for: [background], timeout: 5), .completed)
    try await configure("a", mode: "ready")
    app.activate()
    assertAccount("a", app: app)
    XCTAssertFalse(app.descendants(matching: .any)["native-v2-progress"].firstMatch.exists)
    let counts = try await stats()
    XCTAssertEqual(counts["a"]?["POST api/v1/login/access-token"], 1)
    capture("native-v2-08-background-memory-session")
    app.terminate()
  }

  /// 固定用户名和 API Key 经原生表单提交，创建后只返回登录，不自动登录或重发。
  func testInitializationRequiresSeparateLogin() async throws {
    try await configure("new", mode: "new", reset: true)
    let app = try cleanPicker()
    connect("new", app: app)
    let username = app.textFields["native-v2-username"]
    XCTAssertEqual(username.value as? String, "native-new")
    XCTAssertFalse(username.isEnabled)
    capture("native-v2-05-initialization")
    tap(app.buttons["native-v2-show-password"], app: app)
    let visiblePassword = app.textFields["native-v2-password"]
    visiblePassword.tap()
    visiblePassword.typeText("fixture-new123\n")
    let confirmation = app.textFields["native-v2-confirmation"]
    confirmation.typeText("fixture-new123\n")
    dismissKeyboard(app)
    tap(app.buttons["native-v2-show-password"], app: app)
    capture("native-v2-initialization-filled")
    XCTAssertTrue(app.buttons["native-v2-initialize"].isEnabled)
    tap(app.buttons["native-v2-initialize"], app: app)
    capture("native-v2-initialization-submitted")
    XCTAssertTrue(app.buttons["native-v2-login"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.secureTextFields["native-v2-password"].value as? String, "密码")
    var counts = try await stats()
    XCTAssertEqual(counts["new"]?["POST api/v1/login/initialization"], 1)
    XCTAssertNil(counts["new"]?["POST api/v1/login/access-token"])
    let password = app.secureTextFields["native-v2-password"]
    password.tap()
    password.typeText("fixture-new123")
    dismissKeyboard(app)
    tap(app.buttons["native-v2-login"], app: app)
    assertAccount("new", app: app)
    counts = try await stats()
    XCTAssertEqual(counts["new"]?["POST api/v1/login/access-token"], 1)
    XCTAssertTrue(counts["unexpected", default: [:]].isEmpty)
    app.terminate()
  }

  /// 大字错误页仍可重试/换地址，迟到的旧服务探测不能接管已选择的新服务。
  func testUnavailableRetryCancellationAndLargeText() async throws {
    try await configure("a", mode: "unavailable", reset: true)
    try await configure("slow", mode: "slow", reset: true)
    try await configure("b", mode: "ready", reset: true)
    let app = try cleanPicker(extra: [
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ])
    connect("a", app: app)
    let retry = app.buttons["native-v2-retry"]
    reveal(retry, app: app)
    capture("native-v2-06-large-text-error")
    try await configure("a", mode: "ready")
    tap(retry, app: app)
    reveal(app.textFields["native-v2-username"], app: app)
    let recovered = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: retry)
    XCTAssertEqual(XCTWaiter.wait(for: [recovered], timeout: 10), .completed)
    tap(app.buttons["native-v2-change-server"], app: app)
    connect("slow", app: app, wait: false)
    tap(app.buttons["native-v2-change-server"], app: app)
    connect("b", app: app)
    XCUIDevice.shared.orientation = .landscapeLeft
    enterCredentials("b", app: app)
    capture("native-v2-landscape-before-login")
    tap(app.buttons["native-v2-login"], app: app)
    assertAccount("b", app: app)
    capture("native-v2-07-landscape-large-text")
    let counts = try await stats()
    XCTAssertNil(counts["slow"]?["POST api/v1/login/access-token"])
    XCTAssertEqual(counts["b"]?["POST api/v1/login/access-token"], 1)
    XCTAssertTrue(counts["unexpected", default: [:]].isEmpty)
    XCTAssertEqual(app.webViews.count, 0)
    app.terminate()
    XCUIDevice.shared.orientation = .portrait
  }

  /// 原生三语即时切换；场景恢复不能把后续冷启动锁死在上一次选择的驱动。
  func testStableSceneRoutingAndNativeLanguages() throws {
    let app = try cleanPicker()
    tap(app.buttons["native-v2-language"], app: app)
    app.buttons["English"].tap()
    XCTAssertTrue(app.navigationBars["Connect to server"].exists)
    tap(app.buttons["native-v2-language"], app: app)
    app.buttons["繁體中文"].tap()
    XCTAssertTrue(app.navigationBars["連接服務"].exists)
    tap(app.buttons["native-v2-language"], app: app)
    app.buttons["简体中文"].tap()
    app.terminate()
    app.launchArguments = ["-moviepilot.instance.selected.v1", "", "-AppleLanguages", "(zh-Hans)"]
    app.launch()
    XCTAssertTrue(app.textFields["MoviePilot 服务地址"].waitForExistence(timeout: 15))
    XCTAssertFalse(app.textFields["native-v2-address"].exists)
    app.terminate()
    app.launchArguments = arguments + ["-moviepilot.instance.selected.v1", ""]
    app.launch()
    XCTAssertTrue(app.textFields["native-v2-address"].waitForExistence(timeout: 15))
    XCTAssertEqual(app.webViews.count, 0)
    app.terminate()
  }

  /// 清理仅限定四个合成地址，专用模拟器也不通过全局重置绕过正常忘记流程。
  private func cleanPicker(extra: [String] = []) throws -> XCUIApplication {
    guard ProcessInfo.processInfo.environment["MOVIEPILOT_NATIVE_V2_E2E"] == "1" else {
      throw XCTSkip("需要显式启动原生 API-only 本机夹具。")
    }
    continueAfterFailure = false
    print(
      "NativeEntry accessibility: reduceTransparency=\(UIAccessibility.isReduceTransparencyEnabled), reduceMotion=\(UIAccessibility.isReduceMotionEnabled)"
    )
    XCUIDevice.shared.orientation = .portrait
    let app = XCUIApplication()
    app.launchArguments = arguments + ["-moviepilot.instance.selected.v1", ""] + extra
    app.launch()
    XCTAssertTrue(app.textFields["native-v2-address"].waitForExistence(timeout: 15))
    let fixtureIDs = ["a", "b", "new", "slow"].map { "native-v2-saved-\(base)\($0)/" }
    var previousBottom: String?
    // 大字 Form 延迟创建底部行；从顶部完整遍历，不能把尚未创建的测试地址误认成不存在。
    for _ in 0..<16 {
      if let candidate = app.buttons.matching(NSPredicate(format: "identifier IN %@", fixtureIDs))
        .allElementsBoundByIndex.first
      {
        // 固定原始 ID；删除后不能让 index 0 自动指向下一个实例，误判目标仍存在。
        let row = app.buttons[candidate.identifier]
        reveal(row, app: app)
        row.swipeLeft()
        app.buttons["删除"].tap()
        app.alerts.buttons["删除"].tap()
        let gone = XCTNSPredicateExpectation(
          predicate: NSPredicate(format: "exists == false"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 15), .completed)
        previousBottom = nil
        continue
      }
      let cells = app.collectionViews.firstMatch.cells.allElementsBoundByIndex
      let bottom = "\(cells.count):\(Int((cells.last?.frame.maxY ?? 0).rounded()))"
      if previousBottom == bottom { break }
      previousBottom = bottom
      app.swipeUp()
    }
    XCTAssertEqual(app.webViews.count, 0)
    return app
  }

  /// 输入完整部署子路径，回车只发送初始化探测，不直接发送账号密码。
  private func connect(_ name: String, app: XCUIApplication, wait: Bool = true) {
    let field = app.textFields["native-v2-address"]
    tap(field, app: app)
    if app.buttons["native-v2-clear-address"].exists {
      app.buttons["native-v2-clear-address"].tap()
      tap(field, app: app)
    }
    field.typeText(base + name + "/\n")
    if wait {
      reveal(app.textFields["native-v2-username"], app: app)
      reveal(app.secureTextFields["native-v2-password"], app: app)
      let ready = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "enabled == true"),
        object: app.secureTextFields["native-v2-password"])
      XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
    }
  }

  /// 历史服务使用原列表按钮恢复，不再输入地址或密码。
  private func select(_ name: String, app: XCUIApplication) {
    tap(app.buttons["native-v2-saved-\(base)\(name)/"], app: app)
  }

  /// 合成输入经真正的安全密码框提交；截图不显示明文密码或令牌。
  private func enterCredentials(_ name: String, app: XCUIApplication) {
    let username = app.textFields["native-v2-username"]
    tap(username, app: app)
    username.typeText("native-" + name + "\n")
    let password = app.secureTextFields["native-v2-password"]
    password.typeText("fixture-" + name + "123\n")
    dismissKeyboard(app)
  }

  /// 通过系统键盘工具栏收键盘，后续按钮必须仍可由用户滚动到达。
  private func dismissKeyboard(_ app: XCUIApplication) {
    let done = app.toolbars.buttons["完成"]
    if done.exists { done.tap() }
  }

  /// 大字/横屏通过滚动查找可触控控件，不使用坐标绕过被遮挡的按钮。
  private func tap(_ element: XCUIElement, app: XCUIApplication) {
    reveal(element, app: app)
    element.tap()
  }

  /// Form 延迟创建行且部分 SwiftUI 后代会误报 hittable，必须检查点击中心在可见区域内。
  private func reveal(_ element: XCUIElement, app: XCUIApplication) {
    _ = element.waitForExistence(timeout: 2)
    // 键盘候选栏也是 CollectionView；正文继续取首个 Form，只有已打开选择弹层才取其末个 Form。
    let forms = app.collectionViews.allElementsBoundByIndex
    let cronMode = app.collectionViews["native-cron-mode-form"]
    let cronField = app.collectionViews["native-cron-field-form"]
    let cron = app.collectionViews["native-cron-form"]
    let combobox = app.collectionViews["native-combobox-form"]
    let detailScroll = app.scrollViews.matching(identifier: "native-media-detail-scroll")
      .allElementsBoundByIndex.last(where: { $0.isHittable })
    let personScroll = app.scrollViews.matching(identifier: "native-person-detail-scroll")
      .allElementsBoundByIndex.last(where: { $0.isHittable })
    let workspaceScroll = [
      "native-downloads-scroll", "native-subscriptions-scroll", "native-calendar-scroll",
      "native-resource-search-scroll", "native-history-scroll", "native-sites-scroll",
      "native-messages-scroll", "native-files-scroll", "native-workflows-scroll",
      "native-settings-scroll", "native-users-scroll",
    ].compactMap { identifier in
      app.scrollViews.matching(identifier: identifier).allElementsBoundByIndex.last(where: {
        $0.isHittable
      })
    }.first
    let mediaSearch = app.scrollViews["native-media-search-scroll"]
    let discoverGrid = app.scrollViews["native-discover-grid"]
    let discoverPage = app.scrollViews["native-discover-page"]
    let scroll =
      detailScroll
      ?? personScroll
      ?? workspaceScroll
      ?? (mediaSearch.exists && mediaSearch.isHittable
        ? mediaSearch
        : discoverGrid.exists && discoverGrid.isHittable
          ? discoverGrid
          : discoverPage.exists && discoverPage.isHittable
            ? discoverPage
            : cronMode.exists
              ? cronMode
              : cronField.exists
                ? cronField
                : cron.exists
                  ? cron
                  : combobox.exists
                    ? combobox
                    : (app.buttons["native-plugin-selection-done"].exists
                      ? forms.last : forms.first)
                      ?? app)
    for direction in [true, false] {
      for _ in 0..<12 {
        if visible(element, app: app, scroll: scroll) { return }
        let upward =
          element.exists
          ? element.frame.midY > viewport(app, scroll: scroll).midY : direction
        let area = viewport(app, scroll: scroll)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let x = area.minX + min(32, area.width * 0.1)
        // 矮横屏的长距离惯性滚动会在目标上下反复越过；按差值短拖并停稳，再查询原生命中区域。
        let distance = min(
          area.height * 0.6,
          element.exists ? max(30, abs(element.frame.midY - area.midY)) : area.height * 0.6)
        let upper = origin.withOffset(CGVector(dx: x, dy: area.midY - distance / 2))
        let lower = origin.withOffset(CGVector(dx: x, dy: area.midY + distance / 2))
        if upward {
          lower.press(
            forDuration: 0.05, thenDragTo: upper, withVelocity: .slow, thenHoldForDuration: 0.2)
        } else {
          upper.press(
            forDuration: 0.05, thenDragTo: lower, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
      }
    }
    if !visible(element, app: app, scroll: scroll) {
      capture("native-v2-unreachable-control")
      let details = XCTAttachment(string: app.debugDescription)
      details.name = "native-v2-unreachable-hierarchy"
      details.lifetime = .keepAlways
      add(details)
    }
    XCTAssertTrue(element.exists)
    XCTAssertTrue(element.isHittable)
    XCTAssertTrue(visible(element, app: app, scroll: scroll))
  }

  /// 系统导航、键盘与底部安全区不能被当作表单的有效点击区域。
  private func viewport(_ app: XCUIApplication, scroll: XCUIElement) -> CGRect {
    let window = app.windows.firstMatch.frame
    var rect = scroll.frame.intersection(window).insetBy(dx: 0, dy: 12)
    let bar = app.navigationBars.allElementsBoundByIndex.last ?? app.navigationBars.firstMatch
    if bar.exists, bar.frame.maxY > rect.minY {
      let bottom = rect.maxY
      rect.origin.y = bar.frame.maxY + 6
      rect.size.height = max(0, bottom - rect.minY)
    }
    let keyboard = app.keyboards.firstMatch
    let bottom = keyboard.exists ? min(rect.maxY, keyboard.frame.minY - 6) : rect.maxY - 18
    rect.size.height = max(0, bottom - rect.minY)
    return rect
  }

  /// 以真实元素中心验证命中点，保留普通 isHittable 检查而不使用坐标直接点击控件。
  private func visible(
    _ element: XCUIElement, app: XCUIApplication, scroll: XCUIElement
  ) -> Bool {
    // 被导航栏完全遮挡的 SwiftUI Menu 在查询 isHittable 时会抛出激活点错误，先检查几何范围再查询。
    guard element.exists else { return false }
    if [
      "native-plugin-selection-done", "native-cron-apply", "native-cron-cancel",
      "native-cron-field-apply", "native-combobox-apply", "native-combobox-cancel",
    ].contains(element.identifier) {
      // iPad 原生 sheet 的工具栏 AX 框可能仍用局部坐标；这是导航动作，不属于滚动内容。
      return app.windows.firstMatch.frame.contains(
        CGPoint(x: element.frame.midX, y: element.frame.midY)) && element.isHittable
    }
    if !element.identifier.isEmpty {
      for bar in app.navigationBars.allElementsBoundByIndex
      where bar.buttons.matching(identifier: element.identifier).firstMatch.exists {
        return bar.frame.contains(CGPoint(x: element.frame.midX, y: element.frame.midY))
          && element.isHittable
      }
    }
    if ["发现", "我的", "仪表盘", "搜索"].contains(element.label),
      app.windows.firstMatch.frame.contains(CGPoint(x: element.frame.midX, y: element.frame.midY)),
      element.isHittable
    {
      return true
    }
    for tabBar in app.tabBars.allElementsBoundByIndex {
      let center = CGPoint(x: element.frame.midX, y: element.frame.midY)
      if tabBar.frame.contains(center), element.isHittable {
        return true
      }
    }
    return viewport(app, scroll: scroll).contains(
      CGPoint(x: element.frame.midX, y: element.frame.midY)) && element.isHittable
  }

  /// SwiftUI 的带标题开关包含实际 UISwitch，直接操作该控件并验证真实值。
  private func toggle(_ identifier: String, to enabled: Bool, app: XCUIApplication) {
    let row = app.switches[identifier]
    reveal(row, app: app)
    let control = row.switches.firstMatch
    if control.exists { control.tap() } else { row.tap() }
    XCTAssertEqual(row.value as? String, enabled ? "1" : "0", row.debugDescription)
  }

  /// 已认证账号标签必须属于本次服务，同时检查运行中的可访问性树没有 WebView。
  private func assertAccount(_ name: String, app: XCUIApplication) {
    let accountTab = tabButton("我的", app: app)
    if !app.descendants(matching: .any)["native-v2-account"].firstMatch.exists,
      accountTab.exists
    {
      tap(accountTab, app: app)
    }
    let account = app.descendants(matching: .any)["native-v2-account"].firstMatch
    reveal(account, app: app)
    XCTAssertTrue(account.waitForExistence(timeout: 15))
    XCTAssertTrue(account.label.contains("native-" + name))
    XCTAssertEqual(app.webViews.count, 0)
    XCTAssertFalse(app.textFields["native-v2-username"].exists)
  }

  /// 测试控制只允许固定回环服务；启用标记避免连接不存在的夹具后冒报执行成功。
  private func configure(_ profile: String, mode: String, reset: Bool = false) async throws {
    guard ProcessInfo.processInfo.environment["MOVIEPILOT_NATIVE_V2_E2E"] == "1" else {
      throw XCTSkip("需要原生 API-only 本机夹具。")
    }
    var request = URLRequest(url: URL(string: base + "__native/config")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "profile": profile, "mode": mode, "reset": reset,
    ])
    let (_, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
  }

  /// 路径计数证明没有前端请求、额外登录或初始化后的隐式登录。
  private func stats() async throws -> [String: [String: Int]] {
    let (data, _) = try await URLSession.shared.data(
      from: URL(string: base + "__native/stats")!)
    return try JSONDecoder().decode([String: [String: Int]].self, from: data)
  }

  /// 画面只保留合成实例，明确作为运行验收而非尚未实现业务页的设计图。
  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
