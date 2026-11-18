import XCTest

/// 使用回环合成服务验证正式原生桥、清单客户端、Range 媒体和播放器操作。
@MainActor
final class MediaPlaybackTests: XCTestCase {
  private let base = URL(string: "http://127.0.0.1:5317")!
  private var statsBase = URL(string: "http://127.0.0.1:5317")!
  private var app: XCUIApplication!

  /// 本地视频、STRM 视频和本地音乐均在 App 原生播放器中推进进度并请求 Range 与 LRC。
  func testLocalAndSTRMStreamsPlayInNativeController() async throws {
    do {
      _ = try await fixtureStats()
    } catch {
      throw XCTSkip("需要先启动 scripts/media-playback-fixture.py 本机隔离服务。")
    }
    continueAfterFailure = false
    app = launch()
    try await authenticate()
    let local = app.webViews.buttons["播放本地剧集"]
    let strm = app.webViews.buttons["播放 STRM 剧集"]
    let music = app.webViews.buttons["播放音乐单曲"]
    XCTAssertTrue(local.waitForExistence(timeout: 30), app.debugDescription)
    attachScreenshot(named: "播放入口页面")

    try await verifyPlayback(local, item: "local")
    try await verifyPlayback(strm, item: "strm")
    try await verifyMusicPlayback(music)
    let stats = try await fixtureStats()
    XCTAssertGreaterThan(stats["local_range_requests"] ?? 0, 0)
    XCTAssertGreaterThan(stats["strm_range_requests"] ?? 0, 0)
    XCTAssertGreaterThan(stats["upstream_range_requests"] ?? 0, 0)
    XCTAssertGreaterThan(stats["subtitle_requests"] ?? 0, 0)
    XCTAssertGreaterThan(stats["audio_range_requests"] ?? 0, 0)
    XCTAssertGreaterThan(stats["lyrics_requests"] ?? 0, 0)
  }

  /// 控制条自动隐藏后反复点击画面只切换可见性，播放进度应持续增长。
  func testVideoSurfaceTapsOnlyToggleControls() async throws {
    _ = try await fixtureStats()
    continueAfterFailure = false
    app = launch()
    try await authenticate()
    app.webViews.buttons["播放本地剧集"].tap()
    let slider = app.sliders["playback-progress"]
    XCTAssertTrue(slider.waitForExistence(timeout: 15), app.debugDescription)
    let restart = app.alerts.buttons["从头开始"]
    if restart.waitForExistence(timeout: 2) { restart.tap() }
    try await waitForPlaybackProgress(slider)
    attachScreenshot(named: "全屏播放器-自适应玻璃按钮")
    let close = app.buttons["关闭播放器"]
    let hidden = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "hittable == false"), object: close)
    await fulfillment(of: [hidden], timeout: 12)
    let surface = app.otherElements["视频画面"].coordinate(
      withNormalizedOffset: CGVector(dx: 0.08, dy: 0.38))
    for _ in 0..<3 {
      surface.tap()
      XCTAssertTrue(close.isHittable, app.debugDescription)
      XCTAssertTrue(app.buttons["暂停"].isHittable, "画面点击不能改变播放状态")
      let position = String(describing: slider.value ?? "")
      try await waitForPlaybackProgress(slider, after: position)
      surface.tap()
      XCTAssertFalse(close.isHittable)
    }
    surface.tap()
    app.buttons["暂停"].tap()
    XCTAssertTrue(app.buttons["播放"].waitForExistence(timeout: 5))
    close.tap()
  }

  /// AVKit 确认画中画接管后隐藏 App 播放层，切到桌面仍由系统窗口播放。
  func testSystemPictureInPictureContinuesOnHomeScreen() async throws {
    _ = try await fixtureStats()
    continueAfterFailure = false
    app = launch()
    defer { app.terminate() }
    try await authenticate()
    let entry = app.webViews.buttons["播放本地剧集"]
    entry.tap()
    let progress = app.sliders["playback-progress"]
    XCTAssertTrue(progress.waitForExistence(timeout: 15), app.debugDescription)
    let resume = app.alerts.buttons["继续播放"]
    if resume.waitForExistence(timeout: 2) { resume.tap() }
    try await waitForPlaybackProgress(progress)
    let pictureInPicture = app.buttons["小窗播放"]
    revealVideoControls()
    attachScreenshot(named: "全屏播放器-系统圆形按钮")
    for _ in 0..<60 where !pictureInPicture.isEnabled {
      try await Task.sleep(for: .milliseconds(250))
    }
    guard pictureInPicture.isEnabled else {
      throw XCTSkip("当前运行环境没有提供可启动的系统画中画。")
    }
    pictureInPicture.tap()
    let started = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "hittable == true"), object: entry)
    await fulfillment(of: [started], timeout: 10)
    XCTAssertFalse(app.staticTexts["mini-playback-title"].exists, "系统画中画不应创建 App 内悬浮层")
    XCUIDevice.shared.press(.home)
    XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = "iOS 系统桌面画中画"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// 产品 Vue 搜索页经原生分类搜索媒体库，并按单集或单曲打开实际播放器。
  func testMediaLibrarySearchUsesProductPageAndPlaysResults() async throws {
    continueAfterFailure = false
    app = launch(address: URL(string: "http://127.0.0.1:5181")!)
    try await authenticate(ready: app.buttons["搜索"])
    let search = app.buttons["搜索"]
    XCTAssertTrue(search.waitForExistence(timeout: 30), app.debugDescription)
    search.tap()
    let category = app.buttons["native-search-type-media-library"]
    XCTAssertTrue(category.waitForExistence(timeout: 20), app.debugDescription)
    category.tap()
    attachScreenshot(named: "媒体库全局搜索入口")
    let field = app.searchFields["native-search-field"]
    XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
    replaceText(field, with: "媒体库")
    field.typeText("\n")

    let series = app.webViews.buttons["星际穿越, 电视剧"]
    let track = app.webViews.buttons["晴天, 音乐"]
    XCTAssertTrue(series.waitForExistence(timeout: 30), app.debugDescription)
    XCTAssertTrue(track.exists, app.debugDescription)
    attachScreenshot(named: "媒体库海报搜索结果")
    series.tap()
    let episode = app.webViews.buttons["S01E02"]
    XCTAssertTrue(episode.waitForExistence(timeout: 10), app.debugDescription)
    attachScreenshot(named: "媒体库搜索剧集选择")
    episode.tap()
    let videoTitle = app.staticTexts["星际穿越 · S01E02"]
    XCTAssertTrue(videoTitle.waitForExistence(timeout: 15), app.debugDescription)
    try await waitForPlaybackProgress(app.sliders["playback-progress"])
    app.buttons["关闭播放器"].tap()
    XCTAssertTrue(videoTitle.waitForNonExistence(timeout: 10))
    try await verifyMusicPlayback(track)
  }

  /// 正式 Vue 影片和音乐详情入口均签发对应资源并切入原生播放器。
  func testProductMediaDetailPlayback() async throws {
    continueAfterFailure = false
    for entry in ["产品影片详情", "产品音乐详情"] {
      app = launch()
      try await authenticate()
      let link = app.webViews.links[entry]
      XCTAssertTrue(link.waitForExistence(timeout: 20), app.debugDescription)
      link.tap()
      let play: XCUIElement
      if entry == "产品音乐详情" {
        let actions = app.buttons["native-top-actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 20), app.debugDescription)
        actions.tap()
        play = app.buttons["播放"]
      } else {
        play =
          app.webViews.buttons.matching(NSPredicate(format: "label CONTAINS %@", "播放"))
          .firstMatch
      }
      XCTAssertTrue(play.waitForExistence(timeout: 20), app.debugDescription)
      attachScreenshot(named: entry)
      play.tap()
      if entry == "产品影片详情" {
        let episode = app.webViews.staticTexts["S01E01"]
        XCTAssertTrue(episode.waitForExistence(timeout: 10), app.debugDescription)
        attachScreenshot(named: "影片详情选集入口")
        episode.tap()
      }
      let progress = app.sliders["playback-progress"]
      XCTAssertTrue(progress.waitForExistence(timeout: 20), app.debugDescription)
      let resume = app.alerts.buttons["继续播放"]
      if resume.waitForExistence(timeout: 2) { resume.tap() }
      try await waitForPlaybackProgress(progress)
      app.buttons["关闭播放器"].tap()
      XCTAssertTrue(progress.waitForNonExistence(timeout: 10), app.debugDescription)
    }
  }

  /// 文件详情和整理历史长按都只播放当前选中的那一条本地记录。
  func testProductFileAndHistoryPlaybackEntrances() async throws {
    continueAfterFailure = false
    for entry in ["产品文件管理", "产品整理历史"] {
      app = launch()
      try await authenticate()
      let link = app.webViews.links[entry]
      XCTAssertTrue(link.waitForExistence(timeout: 20), app.debugDescription)
      link.tap()
      if entry == "产品文件管理" {
        let file = app.webViews.staticTexts["moviepilot-playback.mp4"].firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 60), app.debugDescription)
        file.tap()
      } else {
        let record = app.webViews.staticTexts.matching(
          NSPredicate(format: "label CONTAINS %@", "星际穿越")
        ).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 60), app.debugDescription)
        record.press(forDuration: 1.2)
      }
      let play = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "播放")).firstMatch
      XCTAssertTrue(play.waitForExistence(timeout: 60), app.debugDescription)
      attachScreenshot(named: entry)
      play.tap()
      let progress = app.sliders["playback-progress"]
      XCTAssertTrue(progress.waitForExistence(timeout: 20), app.debugDescription)
      let resume = app.alerts.buttons["继续播放"]
      if resume.waitForExistence(timeout: 2) { resume.tap() }
      try await waitForPlaybackProgress(progress)
      app.buttons["关闭播放器"].tap()
      XCTAssertTrue(progress.waitForNonExistence(timeout: 10), app.debugDescription)
    }
  }

  /// 每个媒体来源都必须出现原生控制器，进度随解码时间增长且播放器支持暂停与跳转。
  private func verifyPlayback(_ launchButton: XCUIElement, item: String) async throws {
    XCTAssertTrue(launchButton.isHittable)
    launchButton.tap()
    let videoSurface = app.otherElements["视频画面"]
    XCTAssertTrue(videoSurface.waitForExistence(timeout: 15), app.debugDescription)
    let initialResume = app.alerts.buttons["继续播放"]
    if initialResume.waitForExistence(timeout: 2) { initialResume.tap() }
    revealVideoControls()
    let slider = app.sliders["playback-progress"]
    XCTAssertTrue(slider.waitForExistence(timeout: 10), app.debugDescription)
    XCTAssertTrue(app.buttons["后退 10 秒"].exists)
    XCTAssertTrue(app.buttons["前进 10 秒"].exists)
    let startingProgress = String(describing: slider.value ?? "")
    try await waitForPlaybackProgress(slider, after: startingProgress)
    let pause = app.buttons["暂停"]
    revealVideoControls()
    XCTAssertTrue(pause.exists, app.debugDescription)
    pause.tap()
    let play = app.buttons["播放"]
    XCTAssertTrue(play.waitForExistence(timeout: 5), app.debugDescription)
    try await Task.sleep(for: .milliseconds(4500))
    XCTAssertTrue(play.isHittable, "暂停后的控制层应持续可操作")
    try await waitForRangeRequest(item)
    // 暂停状态断言结束后继续播放，再验证拖动和跳转改变实际解码位置。
    let pausedProgress = String(describing: slider.value ?? "")
    play.tap()
    XCTAssertTrue(app.buttons["暂停"].waitForExistence(timeout: 5), app.debugDescription)
    if item == "local" { attachScreenshot(named: "原生视频播放器") }

    if item == "local" {
      let audioOptions = app.buttons["选择音轨"]
      XCTAssertTrue(audioOptions.waitForExistence(timeout: 10), app.debugDescription)
      audioOptions.tap()
      let embeddedAudio = app.buttons["Track 1"]
      XCTAssertTrue(embeddedAudio.waitForExistence(timeout: 5), app.debugDescription)
      embeddedAudio.tap()
      let subtitle = app.buttons["选择字幕"]
      XCTAssertTrue(subtitle.waitForExistence(timeout: 10), app.debugDescription)
      subtitle.tap()
      let embedded = app.buttons.matching(
        NSPredicate(format: "label BEGINSWITH %@", "内嵌 ·")
      ).firstMatch
      XCTAssertTrue(embedded.waitForExistence(timeout: 10), app.debugDescription)
      embedded.tap()
      if !subtitle.exists {
        app.otherElements["视频画面"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      }
      subtitle.tap()
      let external = app.buttons["zh-CN · zh CN"]
      XCTAssertTrue(external.waitForExistence(timeout: 5), app.debugDescription)
      external.tap()
      try await waitForCounter("subtitle_requests", minimum: 1)

      if !app.sliders["playback-progress"].isHittable {
        app.otherElements["视频画面"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      }
      slider.adjust(toNormalizedSliderPosition: 0.55)
      try await waitForPlaybackProgress(slider, minimum: 0.5)
      app.buttons["后退 10 秒"].tap()
      // 120 秒合成视频从 55% 回退 10 秒后约为 47%。
      try await waitForPlaybackProgress(slider, minimum: 0.4, maximum: 0.51)
      app.buttons["前进 10 秒"].tap()
      try await waitForPlaybackProgress(slider, minimum: 0.5)
      app.buttons["关闭播放器"].tap()
      XCTAssertTrue(videoSurface.waitForNonExistence(timeout: 10))
      launchButton.tap()
      let resume = app.alerts.buttons["继续播放"]
      XCTAssertTrue(resume.waitForExistence(timeout: 15), app.debugDescription)
      attachScreenshot(named: "原生视频续播选择")
      resume.tap()
      try await waitForPlaybackProgress(slider, minimum: 0.45)
    } else {
      try await waitForPlaybackProgress(slider, minimum: 0.03, after: pausedProgress)
    }

    let close = app.buttons["关闭播放器"]
    XCTAssertTrue(close.exists, app.debugDescription)
    close.tap()
    XCTAssertTrue(videoSurface.waitForNonExistence(timeout: 10), app.debugDescription)
  }

  /// 音乐单曲在原生音频布局中播放，并随解码时间自动高亮滚动本地 LRC 歌词。
  private func verifyMusicPlayback(_ launchButton: XCUIElement) async throws {
    XCTAssertTrue(launchButton.waitForExistence(timeout: 10), app.debugDescription)
    launchButton.tap()
    let title = app.staticTexts["music-playback-title"]
    XCTAssertTrue(title.waitForExistence(timeout: 15), app.debugDescription)
    XCTAssertTrue(["测试音乐歌曲", "晴天"].contains(title.label))
    XCTAssertTrue(app.staticTexts["周杰伦"].exists)
    let artwork = app.otherElements["music-playback-artwork"]
    let lyrics = app.descendants(matching: .any)["music-playback-lyrics"]
    XCTAssertTrue(artwork.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertTrue(lyrics.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertLessThanOrEqual(abs(artwork.frame.midX - app.frame.midX), 3)
    XCTAssertLessThanOrEqual(abs(lyrics.frame.midX - app.frame.midX), 3)
    let firstLyric = app.buttons["playback-lyric-line-0"]
    let chorusLyric = app.buttons["playback-lyric-line-1"]
    XCTAssertTrue(firstLyric.waitForExistence(timeout: 10), app.debugDescription)
    XCTAssertTrue(chorusLyric.waitForExistence(timeout: 10), app.debugDescription)
    let progress = app.sliders["playback-progress"]
    try await waitForPlaybackProgress(progress)
    try await waitForCounter("lyrics_requests", minimum: 1)
    try await waitForLyricsHighlight(chorusLyric)
    attachScreenshot(named: "音乐播放器与实时歌词")

    let pause = app.buttons["暂停"]
    XCTAssertTrue(pause.waitForExistence(timeout: 5), app.debugDescription)
    pause.tap()
    XCTAssertTrue(app.buttons["播放"].waitForExistence(timeout: 5), app.debugDescription)
    app.buttons["关闭播放器"].tap()
    XCTAssertTrue(title.waitForNonExistence(timeout: 10), app.debugDescription)
  }

  /// 等待指定 LRC 行成为当前播放行，验证高亮状态来自实际播放器时间。
  private func waitForLyricsHighlight(_ line: XCUIElement) async throws {
    for _ in 0..<40 {
      if line.value as? String == "当前播放" { return }
      try await Task.sleep(for: .milliseconds(250))
    }
    XCTFail("播放时间推进后没有高亮对应歌词")
  }

  /// 将屏幕状态附加到 xcresult，后续导出为用户可查看的模拟器截图。
  private func attachScreenshot(named name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// 用合成账号走 App 登录表单，不向产品注入会话或认证状态。
  private func authenticate(ready: XCUIElement? = nil) async throws {
    let username = app.textFields["用户名"]
    let readyElement = ready ?? app.webViews.buttons["播放本地剧集"]
    for _ in 0..<120 {
      if readyElement.exists { return }
      if username.exists { break }
      try await Task.sleep(for: .milliseconds(500))
    }
    XCTAssertTrue(username.exists, app.debugDescription)
    replaceText(username, with: "playback-fixture")
    let password = app.secureTextFields["密码"]
    replaceText(password, with: "fixture-only")
    password.typeText("\n")
  }

  /// 控制层淡出后用一次画面点击恢复，不用尚未启用的进度滑块判断控制层是否可见。
  private func revealVideoControls() {
    let surface = app.otherElements["视频画面"].coordinate(
      withNormalizedOffset: CGVector(dx: 0.08, dy: 0.38))
    if !app.buttons["关闭播放器"].isHittable { surface.tap() }
  }

  /// 使用空的实例选择状态启动 App，通过真实地址表单连接本机夹具。
  private func launch(address baseAddress: URL? = nil) -> XCUIApplication {
    statsBase =
      baseAddress?.port == 5181
      ? URL(string: "http://127.0.0.1:5318")! : baseAddress ?? base
    let application = XCUIApplication()
    application.launchArguments = [
      "-moviepilot.instance.selected.v1", "", "-AppleLanguages", "(zh-Hans)", "-AppleLocale",
      "zh_CN",
    ]
    application.launch()
    let address = application.textFields["MoviePilot 服务地址"]
    XCTAssertTrue(address.waitForExistence(timeout: 10), application.debugDescription)
    replaceText(address, with: (baseAddress ?? base).absoluteString)
    application.buttons["连接"].tap()
    return application
  }

  /// 清除模拟器上一次运行遗留的文本后再填入固定夹具值。
  private func replaceText(_ field: XCUIElement, with value: String) {
    field.tap()
    field.typeKey("a", modifierFlags: .command)
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 128))
    field.typeText(value)
  }

  /// 等待 VLC 的当前播放时间超过首帧，防止只验证控制器已显示。
  private func waitForPlaybackProgress(
    _ slider: XCUIElement, minimum: Double = 0.02, maximum: Double = 0.99,
    after previous: String? = nil
  ) async throws {
    for _ in 0..<40 {
      revealVideoControls()
      let value = String(describing: slider.value ?? "")
      if let percentage = Double(value.replacingOccurrences(of: "%", with: "")),
        percentage / 100 >= minimum, percentage / 100 <= maximum,
        previous == nil || value != previous
      {
        return
      }
      try await Task.sleep(for: .milliseconds(250))
    }
    XCTFail("原生播放器没有推进播放进度")
  }

  /// 轮询本机夹具的无敏感计数，不读取视频 URL、Cookie 或授权头。
  private func waitForRangeRequest(_ item: String) async throws {
    try await waitForCounter("\(item)_range_requests", minimum: 1)
  }

  /// 在固定期限内等待夹具观测到播放器的 Range 或字幕请求。
  private func waitForCounter(_ key: String, minimum: Int) async throws {
    for _ in 0..<80 {
      if try await fixtureStats()[key, default: 0] >= minimum { return }
      try await Task.sleep(for: .milliseconds(250))
    }
    XCTFail("未观察到预期的媒体请求")
  }

  /// 读取仅监听回环地址的夹具计数，不保存任何会话信息。
  private func fixtureStats() async throws -> [String: Int] {
    let url = statsBase.appending(path: "__playback/stats")
    let (data, response) = try await URLSession.shared.data(from: url)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    return try JSONDecoder().decode([String: Int].self, from: data)
  }
}
