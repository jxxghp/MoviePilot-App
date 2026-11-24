import UIKit
import XCTest

/// API-only 服务通过真实按钮验收原生入口，不启动前端或借用网页登录结果。
@MainActor
final class NativeV2EntryTests: XCTestCase {
  private let base = "http://127.0.0.1:5330/"
  private let arguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]

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
    address.typeText(try XCTUnwrap(input?.backendURL) + "\n")
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
    if environment["MOVIEPILOT_NATIVE_V2_LIVE_SCOPE"] == "medals" {
      tap(tabButton("我的", app: app), app: app)
      let medalsWidget = app.descendants(matching: .any)["native-dashboard-community-medals"]
        .firstMatch
      XCTAssertTrue(medalsWidget.waitForExistence(timeout: 20))
      try await Task.sleep(nanoseconds: 1_500_000_000)
      capture("native-v2-live-medals-widget")

      let codeMedal = app.buttons["native-community-medal-code"]
      XCTAssertTrue(codeMedal.waitForExistence(timeout: 10))
      tap(codeMedal, app: app)
      let stage = app.descendants(matching: .any)["native-medal-3d-stage"].firstMatch
      XCTAssertTrue(stage.waitForExistence(timeout: 10))
      try await Task.sleep(nanoseconds: 2_000_000_000)
      capture("native-v2-live-medal-3d-front")

      // 轻点 3D 舞台翻面查看背面凹雕铭文
      stage.tap()
      try await Task.sleep(nanoseconds: 1_500_000_000)
      capture("native-v2-live-medal-3d-back")

      // 切换到主创勋章并打开详情弹窗
      let maintainerSwitch = app.buttons["native-medal-switch-maintainer"]
      if maintainerSwitch.waitForExistence(timeout: 6) {
        tap(maintainerSwitch, app: app)
        try await Task.sleep(nanoseconds: 1_800_000_000)
        capture("native-v2-live-medal-3d-maintainer")
      }
      let menuBtn = app.buttons["native-medal-showcase-menu"]
      if menuBtn.waitForExistence(timeout: 6) {
        menuBtn.tap()
        let detailsItem = app.buttons["勋章详情"]
        if detailsItem.waitForExistence(timeout: 6) {
          detailsItem.tap()
          try await Task.sleep(nanoseconds: 1_200_000_000)
          capture("native-v2-live-medal-detail-sheet")
        }
      }
      XCTAssertEqual(app.webViews.count, 0)
      return
    }
    if environment["MOVIEPILOT_NATIVE_V2_LIVE_SCOPE"] == "subscriptions" {
      tap(tabButton("订阅", app: app), app: app)
      let subScroll = app.scrollViews["native-subscriptions-scroll"]
      XCTAssertTrue(subScroll.waitForExistence(timeout: 15))
      try await Task.sleep(nanoseconds: 2_500_000_000)
      capture("native-v2-live-subscriptions-all")
      let tvFilter = app.buttons["native-subscriptions-filter-电视剧"]
      if tvFilter.waitForExistence(timeout: 8) {
        tap(tvFilter, app: app)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        capture("native-v2-live-subscriptions-tv-top")
        // 按完成进度排序，直接展示不同集数刻度（部分进度、缺集漏集、大集数聚合等）
        let filterMenu = app.buttons["native-subscriptions-filter-menu"]
        if filterMenu.waitForExistence(timeout: 6) {
          tap(filterMenu, app: app)
          let progressSort = app.buttons["完成进度"]
          if progressSort.waitForExistence(timeout: 6) {
            progressSort.tap()
            try await Task.sleep(nanoseconds: 1_500_000_000)
            capture("native-v2-live-subscriptions-tv-progress")
            subScroll.swipeUp()
            try await Task.sleep(nanoseconds: 1_000_000_000)
            capture("native-v2-live-subscriptions-tv-gaps")
          }
        }
      }
      openOverflowItem("native-workspace-downloads", app: app)
      if app.scrollViews["native-downloads-scroll"].waitForExistence(timeout: 12) {
        try await Task.sleep(nanoseconds: 2_000_000_000)
        capture("native-v2-live-downloads-card")
      }
      XCTAssertEqual(app.webViews.count, 0)
      return
    }
    if environment["MOVIEPILOT_NATIVE_V2_LIVE_SCOPE"] != "search" {
      // 等待实际后端图片代理完成首屏解码，不用合成海报代替线上媒体素材。
      try await Task.sleep(nanoseconds: 4_000_000_000)
      try await Task.sleep(nanoseconds: 2_500_000_000)
      let discoverScroll = app.scrollViews["native-discover-page"]
      let win = app.windows.firstMatch.frame
      let winOrigin = app.coordinate(withNormalizedOffset: .zero)
      capture("native-v2-live-discover-phase-1")
      winOrigin.withOffset(CGVector(dx: win.midX, dy: win.height * 0.78)).press(
        forDuration: 0.05,
        thenDragTo: winOrigin.withOffset(CGVector(dx: win.midX, dy: win.height * 0.18)),
        withVelocity: .slow, thenHoldForDuration: 0.25)
      try await Task.sleep(nanoseconds: 1_500_000_000)
      capture("native-v2-live-discover-phase-2")

      for _ in 0..<2 {
        winOrigin.withOffset(CGVector(dx: win.midX, dy: win.height * 0.78)).press(
          forDuration: 0.05,
          thenDragTo: winOrigin.withOffset(CGVector(dx: win.midX, dy: win.height * 0.20)),
          withVelocity: .slow, thenHoldForDuration: 0.2)
      }
      try await Task.sleep(nanoseconds: 2_000_000_000)
      capture("native-v2-live-discover-phase-3")

      let manageModulesBtn = app.buttons["native-discover-manage-modules"]
      for _ in 0..<8
      where !manageModulesBtn.exists || !visible(manageModulesBtn, app: app, scroll: discoverScroll)
      {
        discoverScroll.swipeUp()
      }
      try await Task.sleep(nanoseconds: 2_000_000_000)
      capture("native-v2-live-discover-phase-4")
      if manageModulesBtn.waitForExistence(timeout: 5) {
        tap(manageModulesBtn, app: app)
        if app.buttons["native-modules-cancel"].waitForExistence(timeout: 8) {
          try await Task.sleep(nanoseconds: 600_000_000)
          capture("native-v2-live-modules")
          app.buttons["native-modules-cancel"].tap()
        }
      }
      for _ in 0..<10 where !more.isHittable {
        discoverScroll.swipeDown()
      }
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
      // 返回「发现」根页面，通过「分类浏览」卡片进入多来源片库探索
      tap(tabButton("发现", app: app), app: app)
      for _ in 0..<4 where !app.scrollViews["native-discover-page"].exists {
        if app.navigationBars.buttons.firstMatch.exists {
          app.navigationBars.buttons.firstMatch.tap()
        }
      }
      let tmdbCategory = app.buttons["native-discover-category-tmdb_movies"]
      reveal(tmdbCategory, app: app)
      XCTAssertTrue(tmdbCategory.waitForExistence(timeout: 10))
      tap(tmdbCategory, app: app)
      XCTAssertTrue(app.scrollViews["native-explore-scroll"].waitForExistence(timeout: 15))
      try await Task.sleep(nanoseconds: 2_500_000_000)
      capture("native-v2-live-explore")
      let doubanTab = app.buttons["native-explore-source-douban_movies"]
      if doubanTab.exists {
        tap(doubanTab, app: app)
        try await Task.sleep(nanoseconds: 2_500_000_000)
        capture("native-v2-live-explore-douban")
        let firstDoubanPoster = app.buttons.matching(
          NSPredicate(format: "identifier BEGINSWITH 'native-explore-poster-douban|'")
        ).firstMatch
        if firstDoubanPoster.waitForExistence(timeout: 8) {
          tap(firstDoubanPoster, app: app)
          if app.staticTexts["native-media-detail-title"].waitForExistence(timeout: 15) {
            try await Task.sleep(nanoseconds: 2_500_000_000)
            capture("native-v2-live-douban-detail")
            let doubanDetailScroll = app.scrollViews["native-media-detail-scroll"]
            if doubanDetailScroll.exists {
              doubanDetailScroll.swipeUp()
              try await Task.sleep(nanoseconds: 1_200_000_000)
              capture("native-v2-live-douban-detail-cast")
            }
          }
          app.navigationBars.buttons.firstMatch.tap()
          try await Task.sleep(nanoseconds: 600_000_000)
        }
      }
      // 从「探索」来源栏横向滚动并切换到「音乐」并进入专辑详情
      let sourceBar = app.scrollViews["native-explore-source-bar"]
      let musicTab = app.buttons["native-explore-source-music"]
      if sourceBar.exists, musicTab.exists {
        for _ in 0..<5 where musicTab.frame.midX > app.frame.width - 24 {
          sourceBar.swipeLeft()
          try await Task.sleep(nanoseconds: 350_000_000)
        }
      }
      if musicTab.exists, !musicTab.frame.isEmpty,
        musicTab.frame.midX >= 16, musicTab.frame.midX <= app.frame.width - 16
      {
        tap(musicTab, app: app)
        let firstAlbum = app.buttons.matching(
          NSPredicate(format: "identifier BEGINSWITH 'native-music-card-'")
        ).firstMatch
        if firstAlbum.waitForExistence(timeout: 15) {
          try await Task.sleep(nanoseconds: 2_500_000_000)
          capture("native-v2-live-music")
          if !firstAlbum.frame.isEmpty {
            tap(firstAlbum, app: app)
            if app.scrollViews["native-music-album-scroll"].waitForExistence(timeout: 12) {
              try await Task.sleep(nanoseconds: 2_000_000_000)
              capture("native-v2-live-music-album")
              app.navigationBars.buttons.firstMatch.tap()
              try await Task.sleep(nanoseconds: 500_000_000)
            }
          }
        }
        let tmdbTab = app.buttons["native-explore-source-tmdb_movies"]
        if sourceBar.exists, tmdbTab.exists {
          for _ in 0..<5 where tmdbTab.frame.midX < 24 {
            sourceBar.swipeRight()
            try await Task.sleep(nanoseconds: 350_000_000)
          }
        }
        if tmdbTab.exists, !tmdbTab.frame.isEmpty,
          tmdbTab.frame.midX >= 16, tmdbTab.frame.midX <= app.frame.width - 16
        {
          tap(tmdbTab, app: app)
        }
      }
      // 切换到「更多」主标签验证四大分组全功能枢纽，并采集更多页顶部与底部截图
      tap(tabButton("更多", app: app), app: app)
      let moreScroll = app.scrollViews["native-more-scroll"]
      if moreScroll.waitForExistence(timeout: 8) {
        try await Task.sleep(nanoseconds: 800_000_000)
        capture("native-v2-live-more")
        moreScroll.swipeUp()
        try await Task.sleep(nanoseconds: 800_000_000)
        capture("native-v2-live-more-bottom")
      }

      // 切换到「订阅」旗舰主标签验收追剧全景卡、规则编辑与内联订阅广场
      tap(tabButton("订阅", app: app), app: app)
      XCTAssertTrue(app.scrollViews["native-subscriptions-scroll"].waitForExistence(timeout: 15))
      try await Task.sleep(nanoseconds: 2_500_000_000)
      capture("native-v2-live-subscriptions")
      let inlineEditRuleBtn = app.buttons.matching(
        NSPredicate(format: "identifier BEGINSWITH 'native-subscribe-edit-'")
      ).firstMatch
      if inlineEditRuleBtn.waitForExistence(timeout: 5) {
        tap(inlineEditRuleBtn, app: app)
        if app.scrollViews["native-subscribe-editor-scroll"].waitForExistence(timeout: 10) {
          try await Task.sleep(nanoseconds: 1_000_000_000)
          capture("native-v2-live-subscribe-editor")
          app.buttons["native-subscribe-editor-cancel"].tap()
        }
      }
      let communityBtn = app.buttons["native-subscriptions-community"]
      if communityBtn.waitForExistence(timeout: 5) {
        tap(communityBtn, app: app)
        if app.scrollViews["native-community-scroll"].waitForExistence(timeout: 12) {
          try await Task.sleep(nanoseconds: 2_500_000_000)
          capture("native-v2-live-community-popular")
          let sharesTab = app.buttons["native-community-tab-社区分享"]
          if sharesTab.exists {
            tap(sharesTab, app: app)
            try await Task.sleep(nanoseconds: 2_000_000_000)
            capture("native-v2-live-community-shares")
          }
          app.navigationBars.buttons.firstMatch.tap()
        }
      }

      openOverflowItem("native-workspace-resources", app: app)
      XCTAssertTrue(app.scrollViews["native-resource-search-scroll"].waitForExistence(timeout: 15))
      try await Task.sleep(nanoseconds: 2_000_000_000)
      capture("native-v2-live-resources")
      app.navigationBars.buttons.firstMatch.tap()

      openOverflowItem("native-workspace-downloads", app: app)
      XCTAssertTrue(app.scrollViews["native-downloads-scroll"].waitForExistence(timeout: 15))
      try await Task.sleep(nanoseconds: 2_000_000_000)
      capture("native-v2-live-downloads")
      app.navigationBars.buttons.firstMatch.tap()

      openOverflowItem("native-workspace-calendar", app: app)
      XCTAssertTrue(app.scrollViews["native-calendar-scroll"].waitForExistence(timeout: 15))
      try await Task.sleep(nanoseconds: 2_000_000_000)
      capture("native-v2-live-calendar")
      app.navigationBars.buttons.firstMatch.tap()

      openOverflowItem("native-workspace-history", app: app)
      XCTAssertTrue(app.scrollViews["native-history-scroll"].waitForExistence(timeout: 15))
      try await Task.sleep(nanoseconds: 2_000_000_000)
      capture("native-v2-live-history")
      let queueBtn = app.buttons["native-history-queue"]
      if queueBtn.waitForExistence(timeout: 6) {
        queueBtn.tap()
        if app.scrollViews["native-transfer-queue-scroll"].waitForExistence(timeout: 10) {
          try await Task.sleep(nanoseconds: 1_000_000_000)
          capture("native-v2-live-transfer-queue")
          app.buttons["native-transfer-queue-close"].tap()
        }
      }
      app.navigationBars.buttons.firstMatch.tap()

      openOverflowItem("native-workspace-files", app: app)
      XCTAssertTrue(app.scrollViews["native-files-scroll"].waitForExistence(timeout: 15))
      try await Task.sleep(nanoseconds: 1_500_000_000)
      capture("native-v2-live-files")
      app.navigationBars.buttons.firstMatch.tap()

      openOverflowItem("native-workspace-workflows", app: app)
      XCTAssertTrue(app.scrollViews["native-workflows-scroll"].waitForExistence(timeout: 15))
      try await Task.sleep(nanoseconds: 1_500_000_000)
      capture("native-v2-live-workflows")
      let firstWorkflowCard = app.descendants(matching: .any).matching(
        NSPredicate(format: "identifier BEGINSWITH 'native-workflow-card-'")
      ).firstMatch
      if firstWorkflowCard.waitForExistence(timeout: 5) {
        firstWorkflowCard.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)).tap()
        if app.descendants(matching: .any)["native-workflow-canvas-area"].firstMatch
          .waitForExistence(timeout: 15)
        {
          try await Task.sleep(nanoseconds: 1_500_000_000)
          capture("native-v2-live-workflow-canvas")
          app.navigationBars.buttons.firstMatch.tap()
          try await Task.sleep(nanoseconds: 500_000_000)
        }
      }
      let switchWorkflowMode = app.buttons["native-workflows-switch-mode"]
      if switchWorkflowMode.waitForExistence(timeout: 5) {
        switchWorkflowMode.tap()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        capture("native-v2-live-workflow-shares")
      }
      app.navigationBars.buttons.firstMatch.tap()

      openOverflowItem("native-overflow-plugin-market", app: app)
      if app.scrollViews["native-plugin-market-scroll"].waitForExistence(timeout: 15) {
        try await Task.sleep(nanoseconds: 1_800_000_000)
        capture("native-v2-live-plugin-installed")
        let statCard = app.descendants(matching: .any)["native-installed-card-SiteStatistic"]
          .firstMatch
        if statCard.waitForExistence(timeout: 5) {
          reveal(statCard, app: app)
          if !statCard.frame.isEmpty, app.frame.intersects(statCard.frame) {
            tap(statCard, app: app)
            if app.scrollViews["native-plugin-page-scroll"].waitForExistence(timeout: 15) {
              try await Task.sleep(nanoseconds: 2_000_000_000)
              capture("native-v2-live-plugin-page-statistic")
              app.navigationBars.buttons.firstMatch.tap()
              try await Task.sleep(nanoseconds: 500_000_000)
            }
          }
        }
        let maoyanCard = app.descendants(matching: .any)["native-installed-card-MaoyanRank"]
          .firstMatch
        if maoyanCard.waitForExistence(timeout: 5) {
          reveal(maoyanCard, app: app)
          if !maoyanCard.frame.isEmpty, app.frame.intersects(maoyanCard.frame) {
            tap(maoyanCard, app: app)
            if app.scrollViews["native-plugin-page-scroll"].waitForExistence(timeout: 15) {
              try await Task.sleep(nanoseconds: 2_000_000_000)
              capture("native-v2-live-plugin-page-maoyan")
              app.navigationBars.buttons.firstMatch.tap()
              try await Task.sleep(nanoseconds: 500_000_000)
            }
          }
        }
        let openStoreBtn = app.buttons["native-plugin-open-store"]
        if openStoreBtn.waitForExistence(timeout: 5) {
          openStoreBtn.tap()
          let firstMarketCard = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'native-market-card-'")
          ).firstMatch
          _ = firstMarketCard.waitForExistence(timeout: 12)
          try await Task.sleep(nanoseconds: 800_000_000)
          capture("native-v2-live-plugin-market")
          app.navigationBars.buttons.firstMatch.tap()
          try await Task.sleep(nanoseconds: 500_000_000)
        }
        app.navigationBars.buttons.firstMatch.tap()
        try await Task.sleep(nanoseconds: 500_000_000)
      }

      // 「我的」对应仪表盘（顶部用户身份卡 + 插件扩展图表），右上角仅保留消息中心入口
      tap(tabButton("我的", app: app), app: app)
      XCTAssertTrue(
        app.descendants(matching: .any)["native-dashboard-storage"].firstMatch.waitForExistence(
          timeout: 15))
      try await Task.sleep(nanoseconds: 1_500_000_000)
      capture("native-v2-live-dashboard")
      let dashScroll = app.scrollViews["native-dashboard-scroll"]
      if dashScroll.exists {
        dashScroll.swipeUp()
        dashScroll.swipeUp()
        try await Task.sleep(nanoseconds: 1_200_000_000)
        capture("native-v2-live-dashboard-plugins")
        dashScroll.swipeDown()
        dashScroll.swipeDown()
        try await Task.sleep(nanoseconds: 400_000_000)
      }

      let messagesBtn = app.buttons["native-dashboard-messages-btn"]
      if messagesBtn.waitForExistence(timeout: 8) {
        messagesBtn.tap()
        if app.scrollViews["native-messages-scroll"].waitForExistence(timeout: 15) {
          try await Task.sleep(nanoseconds: 2_000_000_000)
          capture("native-v2-live-messages")
        }
        let closeMsg = app.buttons["native-messages-sheet-close"]
        if closeMsg.exists { closeMsg.tap() }
        try await Task.sleep(nanoseconds: 500_000_000)
      }

      // 从「更多」页快捷工具与系统诊断分组进入各诊断工具
      for (shortcutID, snapName) in [
        ("native-shortcut-词表", "native-v2-live-diag-words"),
        ("native-shortcut-定时服务", "native-v2-live-diag-schedulers"),
        ("native-shortcut-实时日志", "native-v2-live-diag-logs"),
      ] {
        openOverflowItem(shortcutID, app: app)
        if app.scrollViews["native-diag-scroll"].waitForExistence(timeout: 12) {
          try await Task.sleep(nanoseconds: 1_200_000_000)
          capture(snapName)
          app.navigationBars.buttons.firstMatch.tap()
          try await Task.sleep(nanoseconds: 400_000_000)
        }
      }

      let mascotBtn = app.buttons["native-agent-floating-mascot"]
      if mascotBtn.waitForExistence(timeout: 6) {
        mascotBtn.tap()
        if app.scrollViews["native-agent-scroll"].waitForExistence(timeout: 15) {
          try await Task.sleep(nanoseconds: 1_500_000_000)
          capture("native-v2-live-agent")
        }
        let closeAgent = app.buttons["native-agent-sheet-close"]
        if closeAgent.exists { closeAgent.tap() }
        try await Task.sleep(nanoseconds: 500_000_000)
      }

      // 通过「更多 -> 右上角设置」进入多样化设置中心（存储概览 + 站点/用户/渠道三卡 + 原生分组列表）
      openSettingsHub(app: app)
      XCTAssertTrue(app.buttons["native-workspace-sites"].waitForExistence(timeout: 12))
      try await Task.sleep(nanoseconds: 1_500_000_000)
      capture("native-v2-live-settings-hub")

      let sitesCard = app.buttons["native-workspace-sites"]
      if sitesCard.waitForExistence(timeout: 6) {
        tap(sitesCard, app: app)
        XCTAssertTrue(app.scrollViews["native-sites-scroll"].waitForExistence(timeout: 15))
        try await Task.sleep(nanoseconds: 2_000_000_000)
        capture("native-v2-live-sites")
        let firstSiteCard = app.descendants(matching: .any).matching(
          NSPredicate(format: "identifier BEGINSWITH 'native-site-card-'")
        ).firstMatch
        if firstSiteCard.waitForExistence(timeout: 6) {
          firstSiteCard.coordinate(withNormalizedOffset: CGVector(dx: 0.32, dy: 0.5)).tap()
          if app.scrollViews["native-site-data-scroll"].waitForExistence(timeout: 12) {
            try await Task.sleep(nanoseconds: 1_500_000_000)
            capture("native-v2-live-site-data")
            let closeSiteData = app.buttons["native-site-data-close"]
            if closeSiteData.exists { closeSiteData.tap() }
            try await Task.sleep(nanoseconds: 400_000_000)
          }
        }
        app.navigationBars.buttons.firstMatch.tap()
        try await Task.sleep(nanoseconds: 500_000_000)
      }
      let usersEntry = app.buttons["native-workspace-users"]
      if usersEntry.waitForExistence(timeout: 8) {
        tap(usersEntry, app: app)
        XCTAssertTrue(app.scrollViews["native-users-scroll"].waitForExistence(timeout: 15))
        try await Task.sleep(nanoseconds: 1_500_000_000)
        capture("native-v2-live-users")
        app.navigationBars.buttons.firstMatch.tap()
        try await Task.sleep(nanoseconds: 400_000_000)
      }
      let channelAuthEntry = app.buttons["native-workspace-channel-auth"]
      if channelAuthEntry.waitForExistence(timeout: 8) {
        tap(channelAuthEntry, app: app)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        capture("native-v2-live-channel-auth")
        app.navigationBars.buttons.firstMatch.tap()
        try await Task.sleep(nanoseconds: 400_000_000)
      }
      let subSearchEntry = app.buttons["native-settings-subscribe-search"]
      reveal(subSearchEntry, app: app)
      if subSearchEntry.waitForExistence(timeout: 6) {
        tap(subSearchEntry, app: app)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        capture("native-v2-live-sysmod-site-scope")
        app.navigationBars.buttons.firstMatch.tap()
        try await Task.sleep(nanoseconds: 400_000_000)
      }
      let mediaSourcesEntry = app.buttons["native-settings-media-sources"]
      reveal(mediaSourcesEntry, app: app)
      if mediaSourcesEntry.waitForExistence(timeout: 6) {
        tap(mediaSourcesEntry, app: app)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        capture("native-v2-live-settings")
        app.navigationBars.buttons.firstMatch.tap()
        try await Task.sleep(nanoseconds: 400_000_000)
      }
      let downloadersEntry = app.buttons["native-settings-downloaders"]
      reveal(downloadersEntry, app: app)
      if downloadersEntry.waitForExistence(timeout: 6) {
        tap(downloadersEntry, app: app)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        capture("native-v2-live-sysmod-services")
        app.navigationBars.buttons.firstMatch.tap()
        try await Task.sleep(nanoseconds: 400_000_000)
      }
      let mediaServersEntry = app.buttons["native-settings-mediaservers"]
      reveal(mediaServersEntry, app: app)
      if mediaServersEntry.waitForExistence(timeout: 6) {
        tap(mediaServersEntry, app: app)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        capture("native-v2-live-mediaservers")
        app.navigationBars.buttons.firstMatch.tap()
        try await Task.sleep(nanoseconds: 400_000_000)
      }
      let dirsTile = app.buttons["native-settings-hub-directories"]
      reveal(dirsTile, app: app)
      if dirsTile.waitForExistence(timeout: 6) {
        tap(dirsTile, app: app)
        if app.scrollViews["native-sysmod-scroll"].waitForExistence(timeout: 15) {
          try await Task.sleep(nanoseconds: 1_500_000_000)
          capture("native-v2-live-sysmod-directories")
        }
        app.navigationBars.buttons.firstMatch.tap()
        try await Task.sleep(nanoseconds: 400_000_000)
      }
      let notifyTile = app.buttons["native-settings-hub-notifications"]
      reveal(notifyTile, app: app)
      if notifyTile.waitForExistence(timeout: 6) {
        tap(notifyTile, app: app)
        if app.scrollViews["native-sysmod-scroll"].waitForExistence(timeout: 15) {
          try await Task.sleep(nanoseconds: 1_500_000_000)
          capture("native-v2-live-sysmod-notifications")
        }
        app.navigationBars.buttons.firstMatch.tap()
        try await Task.sleep(nanoseconds: 400_000_000)
      }
      let appearanceTile = app.buttons["native-settings-hub-appearance"]
      reveal(appearanceTile, app: app)
      if appearanceTile.waitForExistence(timeout: 6) {
        tap(appearanceTile, app: app)
        if app.scrollViews["native-appearance-scroll"].waitForExistence(timeout: 12) {
          try await Task.sleep(nanoseconds: 1_200_000_000)
          capture("native-v2-live-appearance")
        }
        app.navigationBars.buttons.firstMatch.tap()
        try await Task.sleep(nanoseconds: 400_000_000)
      }
    }
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
        try await Task.sleep(nanoseconds: 1_500_000_000)
        capture("native-v2-live-tv-detail")
        let tvScroll = app.scrollViews["native-media-detail-scroll"]
        if tvScroll.exists {
          tvScroll.swipeUp()
          try await Task.sleep(nanoseconds: 900_000_000)
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
    let backendURL: String
  }

  /// 用真实 UIKit 导航加载两个原生配置和 Vue 联邦插件，并避免保存用户数据截图。
  func testLivePluginFormsAndVueSheetTakeover() async throws {
    let input = try await readLiveBackendInput()
    let backend = try XCTUnwrap(URLComponents(string: input.backendURL))
    XCTAssertEqual(backend.scheme, "http")
    XCTAssertEqual(backend.host, "127.0.0.1")
    XCTAssertEqual(backend.path, "/")
    XCTAssertNil(backend.user)
    XCTAssertNil(backend.password)

    let app = XCUIApplication()
    defer { app.terminate() }
    app.launchArguments = arguments + ["-moviepilot.instance.selected.v1", ""]
    app.launch()
    let address = app.textFields["native-v2-address"]
    XCTAssertTrue(address.waitForExistence(timeout: 15))
    tap(address, app: app)
    let clear = app.buttons["native-v2-clear-address"]
    if clear.exists { clear.tap() }
    address.typeText(input.backendURL + "\n")

    let username = app.textFields["native-v2-username"]
    XCTAssertTrue(username.waitForExistence(timeout: 15))
    tap(username, app: app)
    username.typeText(input.username + "\n")
    app.secureTextFields["native-v2-password"].typeText(input.password + "\n")
    dismissKeyboard(app)
    if app.switches["native-v2-remember-session"].value as? String == "1" {
      toggle("native-v2-remember-session", to: false, app: app)
    }
    tap(app.buttons["native-v2-login"], app: app)
    XCTAssertTrue(tabButton("更多", app: app).waitForExistence(timeout: 20))
    XCTAssertEqual(app.webViews.count, 0)

    openOverflowItem("native-overflow-plugin-market", app: app)
    XCTAssertTrue(app.scrollViews["native-plugin-market-scroll"].waitForExistence(timeout: 15))

    let signInCard = app.descendants(matching: .any)[
      "native-installed-card-AutoSignIn"
    ].firstMatch
    reveal(signInCard, app: app)
    XCTAssertTrue(signInCard.waitForExistence(timeout: 12))
    tap(signInCard, app: app)
    XCTAssertTrue(app.scrollViews["native-plugin-page-scroll"].waitForExistence(timeout: 15))
    let tables = app.descendants(matching: .any).matching(identifier: "native-plugin-json-table")
    XCTAssertTrue(tables.firstMatch.waitForExistence(timeout: 20))
    XCTAssertEqual(tables.count, 2, "自动签到页应完整呈现后端两张站点状态表。")
    XCTAssertEqual(app.webViews.count, 0)
    app.navigationBars.buttons.firstMatch.tap()

    // 打开原生表单后核对实际 Cron 与多选站点控件；不写入服务端配置。
    reveal(signInCard, app: app)
    signInCard.press(forDuration: 1)
    let signInSettings = app.buttons["设置"].firstMatch
    XCTAssertTrue(signInSettings.waitForExistence(timeout: 8))
    tap(signInSettings, app: app)
    XCTAssertTrue(app.textFields["native-plugin-field-cron"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.buttons["native-plugin-cron-edit-cron"].exists)
    XCTAssertTrue(
      app.descendants(matching: .any)["native-plugin-field-sign_sites"].exists)
    // 登录站点字段位于表单下方，需先滚动到可见区域再断言。
    let loginSites = app.descendants(matching: .any)["native-plugin-field-login_sites"]
    reveal(loginSites, app: app)
    XCTAssertTrue(loginSites.exists)
    XCTAssertTrue(app.buttons["native-plugin-form-save"].isEnabled)
    XCTAssertEqual(app.webViews.count, 0)
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(app.scrollViews["native-plugin-market-scroll"].waitForExistence(timeout: 10))

    let refreshCard = app.descendants(matching: .any)[
      "native-installed-card-MediaServerRefresh"
    ].firstMatch
    reveal(refreshCard, app: app)
    XCTAssertTrue(refreshCard.waitForExistence(timeout: 12))
    tap(refreshCard, app: app)
    XCTAssertTrue(
      app.descendants(matching: .any)["native-plugin-field-enabled"].firstMatch
        .waitForExistence(timeout: 12))
    XCTAssertTrue(app.textFields["native-plugin-field-delay"].exists)
    XCTAssertTrue(
      app.descendants(matching: .any)["native-plugin-field-mediaservers"].exists)
    XCTAssertTrue(app.buttons["native-plugin-form-save"].isEnabled)
    app.navigationBars.buttons.firstMatch.tap()

    // 联邦插件通过当前服务 Cookie 与主题外观注入后，原生栏进入协议协商完成态。
    let vuePlugin = app.descendants(matching: .any)[
      "native-installed-card-SubscribeAssistantEnhanced"
    ].firstMatch
    reveal(vuePlugin, app: app)
    XCTAssertTrue(vuePlugin.waitForExistence(timeout: 12))
    tap(vuePlugin, app: app)
    XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 25))
    XCTAssertTrue(
      app.descendants(matching: .any)["native-vue-plugin-sheet-ready"].waitForExistence(
        timeout: 25),
      "前端必须确认只接管插件弹窗内容后，原生 Sheet 才能结束加载。")
    XCTAssertTrue(app.buttons["native-vue-plugin-sheet-close"].exists)
    // WKWebView 会向辅助功能树暴露多个网页区域，只确认兼容宿主仍在当前 Sheet 中。
    XCTAssertTrue(app.webViews.firstMatch.exists)
    app.buttons["native-vue-plugin-sheet-close"].tap()
    XCTAssertTrue(app.scrollViews["native-plugin-market-scroll"].waitForExistence(timeout: 12))
  }

  /// 从隔离的一次性输入通道接收真实凭据，只保存在当前 UI 测试进程的内存。
  private func readLiveBackendInput() async throws -> LiveBackendInput {
    let environment = ProcessInfo.processInfo.environment
    guard let port = environment["MOVIEPILOT_NATIVE_V2_LIVE_INPUT_PORT"],
      let number = Int(port), (1024...65535).contains(number),
      let nonce = environment["MOVIEPILOT_NATIVE_V2_LIVE_NONCE"], nonce.count >= 32
    else { throw XCTSkip("仅由交互式本机验收脚本运行，不从文件或测试源码获取真实凭据。") }
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(number)/session-input")!)
    request.setValue(nonce, forHTTPHeaderField: "X-MoviePilot-Live-Test")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw XCTSkip("一次性本机输入已由另一项验收消费。")
    }
    return try JSONDecoder().decode(LiveBackendInput.self, from: data)
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

    openOverflowItem("native-workspace-subscriptions", viaTab: "发现", app: app)
    XCTAssertTrue(app.scrollViews["native-subscriptions-scroll"].waitForExistence(timeout: 10))
    let subTicks = app.descendants(matching: .any)["native-subscribe-ticks-702"].firstMatch
    XCTAssertTrue(subTicks.waitForExistence(timeout: 10))
    let subToggle = app.buttons["native-subscribe-toggle-702"]
    XCTAssertTrue(subToggle.waitForExistence(timeout: 10))
    tap(subToggle, app: app)
    XCTAssertTrue(
      app.descendants(matching: .any)["native-subscriptions-feedback"].firstMatch
        .waitForExistence(timeout: 8))
    let subCard = app.descendants(matching: .any)["native-subscribe-card-701"].firstMatch
    XCTAssertTrue(subCard.waitForExistence(timeout: 8))
    subCard.press(forDuration: 1.0)
    let subDeleteMenu = app.buttons["取消订阅"]
    XCTAssertTrue(subDeleteMenu.waitForExistence(timeout: 8))
    subDeleteMenu.tap()
    let confirmSubDelete = app.alerts["取消订阅"].buttons["取消订阅"]
    XCTAssertTrue(confirmSubDelete.waitForExistence(timeout: 8))
    confirmSubDelete.tap()

    openOverflowItem("native-workspace-downloads", app: app)
    XCTAssertTrue(app.scrollViews["native-downloads-scroll"].waitForExistence(timeout: 10))
    let dlToggle = app.buttons["native-download-toggle-abc123def456"]
    XCTAssertTrue(dlToggle.waitForExistence(timeout: 10))
    let dlDeleteBtn = app.buttons["native-download-delete-abc123def456"]
    XCTAssertTrue(dlDeleteBtn.waitForExistence(timeout: 8))
    capture("native-v2-fixture-downloads")
    tap(dlToggle, app: app)
    XCTAssertTrue(
      app.descendants(matching: .any)["native-downloads-feedback"].firstMatch
        .waitForExistence(timeout: 8))
    let dlCard = app.descendants(matching: .any)["native-download-card-abc123def456"].firstMatch
    XCTAssertTrue(dlCard.waitForExistence(timeout: 8))
    dlCard.press(forDuration: 1.0)
    let dlDeleteMenu = app.buttons["删除任务"]
    XCTAssertTrue(dlDeleteMenu.waitForExistence(timeout: 8))
    dlDeleteMenu.tap()
    let confirmDlDelete = app.alerts["删除下载任务"].buttons["删除任务与文件"]
    XCTAssertTrue(confirmDlDelete.waitForExistence(timeout: 8))
    confirmDlDelete.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["native-downloads-empty"].firstMatch
        .waitForExistence(timeout: 10))
    app.navigationBars.buttons.firstMatch.tap()

    openOverflowItem("native-workspace-calendar", viaTab: "发现", app: app)
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

    openOverflowItem("native-workspace-history", viaTab: "发现", app: app)
    XCTAssertTrue(app.scrollViews["native-history-scroll"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.textFields["native-history-search-field"].waitForExistence(timeout: 8))
    let queueBtn = app.buttons["native-history-queue"]
    XCTAssertTrue(queueBtn.waitForExistence(timeout: 8))
    queueBtn.tap()
    XCTAssertTrue(app.scrollViews["native-transfer-queue-scroll"].waitForExistence(timeout: 10))
    app.buttons["native-transfer-queue-close"].tap()
    let expandBtn = app.buttons["native-history-expand-801"]
    XCTAssertTrue(expandBtn.waitForExistence(timeout: 10))
    tap(expandBtn, app: app)
    XCTAssertFalse(app.buttons["native-history-delete-801"].exists)
    expandBtn.press(forDuration: 1.0)
    let deleteMenu = app.buttons["删除整理记录"]
    XCTAssertTrue(deleteMenu.waitForExistence(timeout: 8))
    deleteMenu.tap()
    let confirmDelete = app.alerts["删除整理记录"].buttons["仅删除记录"]
    XCTAssertTrue(confirmDelete.waitForExistence(timeout: 8))
    confirmDelete.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["native-history-feedback"].firstMatch
        .waitForExistence(timeout: 8))
    app.navigationBars.buttons.firstMatch.tap()

    // 站点管理位于「更多 -> 设置」中心
    openSettingsHub(app: app)
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

    // 消息中心位于「我的」仪表盘右上角
    tap(tabButton("我的", app: app), app: app)
    let msgEntry = app.buttons["native-dashboard-messages-btn"]
    XCTAssertTrue(msgEntry.waitForExistence(timeout: 10))
    msgEntry.tap()
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

    openOverflowItem("native-workspace-files", viaTab: "发现", app: app)
    XCTAssertTrue(app.scrollViews["native-files-scroll"].waitForExistence(timeout: 10))
    let mediaFolder = app.buttons["native-file-open-media"]
    XCTAssertTrue(mediaFolder.waitForExistence(timeout: 10))
    tap(mediaFolder, app: app)
    let upBtn = app.buttons["native-files-up"]
    XCTAssertTrue(upBtn.waitForExistence(timeout: 10))
    tap(upBtn, app: app)
    let sampleFile = app.buttons["native-file-open-samplemkv"]
    XCTAssertTrue(sampleFile.waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["native-file-delete-samplemkv"].exists)
    sampleFile.press(forDuration: 1.0)
    let delMenu = app.buttons["删除"]
    XCTAssertTrue(delMenu.waitForExistence(timeout: 8))
    delMenu.tap()
    let confirmDel = app.alerts["删除项目"].buttons["确认删除"]
    XCTAssertTrue(confirmDel.waitForExistence(timeout: 8))
    confirmDel.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["native-files-feedback"].firstMatch
        .waitForExistence(timeout: 8))
    app.navigationBars.buttons.firstMatch.tap()

    openOverflowItem("native-workspace-workflows", viaTab: "发现", app: app)
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
    openSettingsHub(app: app)

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
    let usersScroll = app.scrollViews["native-users-scroll"]
    XCTAssertTrue(usersScroll.waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["native-a"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["native-b"].exists)
    XCTAssertTrue(app.buttons["native-users-add"].exists)
    usersScroll.swipeDown()
    XCTAssertEqual(app.webViews.count, 0)

    let counts = try await stats()
    XCTAssertGreaterThanOrEqual(counts["a"]?["GET api/v1/system/env"] ?? 0, 1)
    XCTAssertEqual(counts["a"]?["POST api/v1/system/env"], 1)
    XCTAssertGreaterThanOrEqual(counts["a"]?["GET api/v1/user"] ?? 0, 1)
    XCTAssertEqual(counts["unexpected"], [:])
  }

  /// P3.2b：验证多来源片库探索筛选切换与发现页模块编排开关持久化，零 WebView。
  func testNativeExploreSourcesAndModuleArrangement() async throws {
    let app = try await signInToNativeBusiness()
    defer { app.terminate() }

    let manageBtn = app.buttons["native-discover-manage-modules"]
    let discoverScroll = app.scrollViews["native-discover-page"]
    XCTAssertTrue(discoverScroll.waitForExistence(timeout: 12))
    for _ in 0..<8 where !manageBtn.exists { discoverScroll.swipeUp() }
    XCTAssertTrue(manageBtn.waitForExistence(timeout: 8))
    tap(manageBtn, app: app)
    XCTAssertTrue(app.buttons["native-modules-save"].waitForExistence(timeout: 8))
    toggle("native-module-toggle-doubanShowing", to: true, app: app)
    tap(app.buttons["native-modules-save"], app: app)
    XCTAssertTrue(app.buttons["native-discover-more-豆瓣热映"].waitForExistence(timeout: 12))

    let tmdbCategory = app.buttons["native-discover-category-tmdb_movies"]
    reveal(tmdbCategory, app: app)
    XCTAssertTrue(tmdbCategory.waitForExistence(timeout: 10))
    tap(tmdbCategory, app: app)
    XCTAssertTrue(app.scrollViews["native-explore-scroll"].waitForExistence(timeout: 10))
    let doubanBtn = app.buttons["native-explore-source-douban_movies"]
    XCTAssertTrue(doubanBtn.waitForExistence(timeout: 10))
    tap(doubanBtn, app: app)
    XCTAssertTrue(
      app.buttons["native-explore-poster-themoviedb|131|电影"].waitForExistence(timeout: 10))
    let sourceBar = app.scrollViews["native-explore-source-bar"]
    let bgmBtn = app.buttons["native-explore-source-bangumi"]
    XCTAssertTrue(bgmBtn.waitForExistence(timeout: 8))
    if sourceBar.exists && bgmBtn.frame.maxX > app.windows.firstMatch.frame.maxX - 8 {
      sourceBar.swipeLeft()
    }
    bgmBtn.tap()
    XCTAssertTrue(
      app.buttons["native-explore-poster-themoviedb|141|电视剧"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.webViews.count, 0)

    let counts = try await stats()
    XCTAssertEqual(counts["a"]?["POST api/v1/user/config/NativeDiscoverModules"], 1)
    XCTAssertEqual(counts["a"]?["GET api/v1/recommend/douban_showing"], 1)
    XCTAssertGreaterThanOrEqual(counts["a"]?["GET api/v1/discover/douban_movies"] ?? 0, 1)
    XCTAssertGreaterThanOrEqual(counts["a"]?["GET api/v1/discover/bangumi"] ?? 0, 1)
    XCTAssertEqual(counts["unexpected"], [:])
  }

  /// P4.2 / P4.3：验证订阅高级规则编辑单次 PUT、热门订阅浏览与社区分享确认复用，零 WebView。
  func testNativeSubscribeEditorAndCommunityForkFlows() async throws {
    let app = try await signInToNativeBusiness()
    defer { app.terminate() }

    openOverflowItem("native-workspace-subscriptions", app: app)
    XCTAssertTrue(app.scrollViews["native-subscriptions-scroll"].waitForExistence(timeout: 10))
    XCTAssertTrue(
      app.descendants(matching: .any)["native-subscriptions-overview"].firstMatch
        .waitForExistence(timeout: 8))

    let editCard = app.descendants(matching: .any)["native-subscribe-card-702"].firstMatch
    XCTAssertTrue(editCard.waitForExistence(timeout: 10))
    editCard.press(forDuration: 1.0)
    let editMenu = app.buttons["编辑订阅规则"]
    XCTAssertTrue(editMenu.waitForExistence(timeout: 8))
    editMenu.tap()
    XCTAssertTrue(app.scrollViews["native-subscribe-editor-scroll"].waitForExistence(timeout: 10))
    let saveBtn = app.buttons["native-subscribe-editor-save"]
    XCTAssertTrue(saveBtn.waitForExistence(timeout: 8))
    XCTAssertFalse(saveBtn.isEnabled)
    toggle("native-subscribe-editor-best-version", to: true, app: app)
    XCTAssertTrue(saveBtn.isEnabled)
    tap(saveBtn, app: app)
    XCTAssertTrue(
      app.descendants(matching: .any)["native-subscriptions-feedback"].firstMatch
        .waitForExistence(timeout: 10))

    let communityBtn = app.buttons["native-subscriptions-community"]
    XCTAssertTrue(communityBtn.waitForExistence(timeout: 8))
    tap(communityBtn, app: app)
    XCTAssertTrue(app.scrollViews["native-community-scroll"].waitForExistence(timeout: 10))
    XCTAssertTrue(
      app.buttons["native-community-popular-themoviedb|101|电影"].waitForExistence(timeout: 10))
    let sharesTab = app.buttons["native-community-tab-社区分享"]
    tap(sharesTab, app: app)
    let forkBtn = app.buttons["native-share-fork-601"]
    XCTAssertTrue(forkBtn.waitForExistence(timeout: 10))
    tap(forkBtn, app: app)
    let confirmFork = app.alerts["复用订阅"].buttons["确认复用"]
    XCTAssertTrue(confirmFork.waitForExistence(timeout: 8))
    confirmFork.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["native-community-feedback"].firstMatch
        .waitForExistence(timeout: 10))
    XCTAssertEqual(app.webViews.count, 0)

    let counts = try await stats()
    XCTAssertEqual(counts["a"]?["GET api/v1/subscribe/702"], 1)
    XCTAssertEqual(counts["a"]?["PUT api/v1/subscribe/"], 1)
    XCTAssertEqual(counts["a"]?["GET api/v1/subscribe/popular"], 1)
    XCTAssertEqual(counts["a"]?["GET api/v1/subscribe/shares"], 1)
    XCTAssertEqual(counts["a"]?["POST api/v1/subscribe/fork"], 1)
    XCTAssertEqual(counts["unexpected"], [:])
  }

  /// P3.5：验证原生音乐探索、专辑曲目详情、音乐订阅与艺术家详情跳转，零 WebView。
  func testNativeMusicDiscoveryAlbumArtistAndSubscribe() async throws {
    let app = try await signInToNativeBusiness()
    defer { app.terminate() }

    tap(tabButton("发现", app: app), app: app)
    let musicCategory = app.buttons["native-discover-category-music"]
    reveal(musicCategory, app: app)
    XCTAssertTrue(musicCategory.waitForExistence(timeout: 10))
    tap(musicCategory, app: app)
    XCTAssertTrue(app.scrollViews["native-music-scroll"].waitForExistence(timeout: 10))

    let chartTab = app.buttons["native-music-feed-热门专辑"]
    XCTAssertTrue(chartTab.waitForExistence(timeout: 10))
    tap(chartTab, app: app)
    let albumCard = app.buttons["native-music-card-musicbrainz|alb-201"]
    XCTAssertTrue(albumCard.waitForExistence(timeout: 10))
    tap(albumCard, app: app)
    XCTAssertTrue(app.scrollViews["native-music-album-scroll"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["序曲：星尘启航"].waitForExistence(timeout: 10))

    let subBtn = app.buttons["native-music-album-subscribe"]
    XCTAssertTrue(subBtn.waitForExistence(timeout: 8))
    tap(subBtn, app: app)
    XCTAssertTrue(
      app.descendants(matching: .any)["native-music-album-feedback"].firstMatch
        .waitForExistence(timeout: 10))

    let artistBtn = app.buttons["native-music-album-artist"]
    XCTAssertTrue(artistBtn.waitForExistence(timeout: 8))
    tap(artistBtn, app: app)
    XCTAssertTrue(app.scrollViews["native-music-artist-scroll"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["native-music-artist-name"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.webViews.count, 0)

    let counts = try await stats()
    XCTAssertEqual(counts["a"]?["GET api/v1/recommend/music_douban"], 1)
    XCTAssertEqual(counts["a"]?["GET api/v1/music/explore"], 1)
    XCTAssertEqual(counts["a"]?["GET api/v1/music/album/alb-201"], 1)
    XCTAssertEqual(counts["a"]?["POST api/v1/subscribe/"], 1)
    XCTAssertEqual(counts["a"]?["GET api/v1/music/artist/art-301"], 1)
    XCTAssertEqual(counts["a"]?["GET api/v1/music/artist/art-301/albums"], 1)
    XCTAssertEqual(counts["unexpected"], [:])
  }

  /// P7.1：验证管理员插件市场安装确认、已安装管理重置与卸载确认单次提交，零 WebView。
  func testNativePluginMarketInstallResetAndUninstall() async throws {
    let app = try await signInToNativeBusiness()
    defer { app.terminate() }
    openOverflowItem("native-overflow-plugin-market", app: app)
    XCTAssertTrue(app.scrollViews["native-plugin-market-scroll"].waitForExistence(timeout: 10))

    let openStoreBtn = app.buttons["native-plugin-open-store"]
    XCTAssertTrue(openStoreBtn.waitForExistence(timeout: 8))
    openStoreBtn.tap()

    let marketCard = app.descendants(matching: .any)["native-market-card-AutoSignIn"].firstMatch
    XCTAssertTrue(marketCard.waitForExistence(timeout: 10))
    tap(marketCard, app: app)
    let confirmInstall = app.alerts["安装插件"].buttons["确认安装"]
    XCTAssertTrue(confirmInstall.waitForExistence(timeout: 8))
    confirmInstall.tap()
    app.navigationBars.buttons.firstMatch.tap()

    let demoCard = app.descendants(matching: .any)["native-installed-card-DemoPlugin"].firstMatch
    XCTAssertTrue(demoCard.waitForExistence(timeout: 10))
    demoCard.press(forDuration: 1.0)
    let resetMenu = app.buttons["重置插件"]
    XCTAssertTrue(resetMenu.waitForExistence(timeout: 8))
    resetMenu.tap()
    let confirmReset = app.alerts["重置插件"].buttons["确认重置"]
    XCTAssertTrue(confirmReset.waitForExistence(timeout: 8))
    confirmReset.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["native-plugin-market-feedback"].firstMatch
        .waitForExistence(timeout: 10))

    XCTAssertTrue(demoCard.waitForExistence(timeout: 8))
    demoCard.press(forDuration: 1.0)
    let uninstallMenu = app.buttons["卸载插件"]
    XCTAssertTrue(uninstallMenu.waitForExistence(timeout: 8))
    uninstallMenu.tap()
    let confirmUninstall = app.alerts["卸载插件"].buttons["确认卸载"]
    XCTAssertTrue(confirmUninstall.waitForExistence(timeout: 8))
    confirmUninstall.tap()
    XCTAssertEqual(app.webViews.count, 0)

    let counts = try await stats()
    XCTAssertEqual(counts["a"]?["GET api/v1/plugin/install/AutoSignIn"], 1)
    XCTAssertEqual(counts["a"]?["GET api/v1/plugin/reset/DemoPlugin"], 1)
    XCTAssertEqual(counts["a"]?["DELETE api/v1/plugin/DemoPlugin"], 1)
    XCTAssertEqual(counts["unexpected"], [:])
  }

  /// P6.5：验证原生智能助手 SSE 流式回复解析、工具调用摘要与历史会话读取，零 WebView。
  func testNativeAgentChatStreamAndSessionHistory() async throws {
    let app = try await signInToNativeBusiness()
    defer { app.terminate() }

    let mascotBtn = app.buttons["native-agent-floating-mascot"]
    XCTAssertTrue(mascotBtn.waitForExistence(timeout: 8))
    mascotBtn.tap()
    XCTAssertTrue(app.scrollViews["native-agent-scroll"].waitForExistence(timeout: 10))

    let input = app.textFields["native-agent-input"]
    XCTAssertTrue(input.waitForExistence(timeout: 10))
    input.tap()
    input.typeText("推荐电影")
    let sendBtn = app.buttons["native-agent-send"]
    XCTAssertTrue(sendBtn.waitForExistence(timeout: 8))
    sendBtn.tap()
    XCTAssertTrue(app.staticTexts["已检索本地媒体库与订阅"].waitForExistence(timeout: 10))

    let sessionsBtn = app.buttons["native-agent-sessions"]
    XCTAssertTrue(sessionsBtn.waitForExistence(timeout: 8))
    tap(sessionsBtn, app: app)
    let firstSession = app.buttons["native-agent-session-sess-1"]
    XCTAssertTrue(firstSession.waitForExistence(timeout: 10))
    firstSession.tap()
    XCTAssertTrue(app.staticTexts["已检索 TMDB 评分"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.webViews.count, 0)

    let counts = try await stats()
    XCTAssertEqual(counts["a"]?["POST api/v1/agent/stream"], 1)
    XCTAssertEqual(counts["a"]?["GET api/v1/agent/sessions/sess-1"], 1)
    XCTAssertEqual(counts["unexpected"], [:])
  }

  /// P2.3/P2.4：验证插件 Vuetify JSON 数据页原生图表/表格、Vue 远程插件门禁与仪表板插件卡片零 WebView。
  func testNativePluginDataPageChartsAndVueCompatGate() async throws {
    let app = try await signInToNativeBusiness()
    defer { app.terminate() }

    tap(tabButton("我的", app: app), app: app)
    XCTAssertTrue(app.staticTexts["近 7 日任务分布"].waitForExistence(timeout: 12))
    XCTAssertEqual(app.webViews.count, 0)

    openOverflowItem("native-overflow-plugin-market", app: app)
    XCTAssertTrue(app.scrollViews["native-plugin-market-scroll"].waitForExistence(timeout: 10))

    let demoPageBtn = app.descendants(matching: .any)["native-installed-card-DemoPlugin"]
      .firstMatch
    XCTAssertTrue(demoPageBtn.waitForExistence(timeout: 10))
    tap(demoPageBtn, app: app)
    XCTAssertTrue(app.scrollViews["native-plugin-page-scroll"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["今日站点上传占比 (GB)"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["合成站 A"].waitForExistence(timeout: 8))
    XCTAssertEqual(app.webViews.count, 0)
    app.navigationBars.buttons.firstMatch.tap()

    let vuePageBtn = app.descendants(matching: .any)["native-installed-card-VueCompatDemo"]
      .firstMatch
    reveal(vuePageBtn, app: app)
    XCTAssertTrue(vuePageBtn.waitForExistence(timeout: 10))
    tap(vuePageBtn, app: app)
    XCTAssertTrue(app.buttons["native-plugin-open-compat"].waitForExistence(timeout: 10))
    // 门禁要求：未点击显式打开按钮前，不能提前创建任何 WebView。
    XCTAssertEqual(app.webViews.count, 0)

    let counts = try await stats()
    XCTAssertEqual(counts["a"]?["GET api/v1/plugin/dashboard/meta"], 1)
    XCTAssertEqual(counts["a"]?["GET api/v1/plugin/dashboard/DemoPlugin"], 1)
    XCTAssertEqual(counts["a"]?["GET api/v1/plugin/page/DemoPlugin"], 1)
    XCTAssertEqual(counts["a"]?["GET api/v1/plugin/page/VueCompatDemo"], 1)
    XCTAssertEqual(counts["unexpected"], [:])
  }

  /// P5.5：验证纯原生工作流节点画布、添加节点、参数编辑与单次保存，及社区工作流分享复用，零 WebView。
  func testNativeWorkflowCanvasEditSaveAndCommunityFork() async throws {
    let app = try await signInToNativeBusiness()
    defer { app.terminate() }

    openOverflowItem("native-workspace-workflows", viaTab: "发现", app: app)
    XCTAssertTrue(app.scrollViews["native-workflows-scroll"].waitForExistence(timeout: 10))

    let canvasBtn = app.buttons["native-workflow-canvas-31"]
    XCTAssertTrue(canvasBtn.waitForExistence(timeout: 10))
    tap(canvasBtn, app: app)
    XCTAssertTrue(
      app.descendants(matching: .any)["native-workflow-canvas-area"].firstMatch.waitForExistence(
        timeout: 10))
    XCTAssertTrue(app.buttons["native-workflow-node-act-scan"].waitForExistence(timeout: 10))

    let addBtn = app.buttons["native-workflow-add-node"]
    XCTAssertTrue(addBtn.waitForExistence(timeout: 8))
    addBtn.tap()
    let notifyAction = app.buttons["native-workflow-catalog-SendMessageAction"]
    XCTAssertTrue(notifyAction.waitForExistence(timeout: 10))
    notifyAction.tap()

    let editBtn = app.buttons["native-workflow-edit-node"]
    XCTAssertTrue(editBtn.waitForExistence(timeout: 10))
    editBtn.tap()
    let applyBtn = app.buttons["native-workflow-node-editor-apply"]
    XCTAssertTrue(applyBtn.waitForExistence(timeout: 10))
    applyBtn.tap()

    let saveBtn = app.buttons["native-workflow-canvas-save"]
    XCTAssertTrue(saveBtn.waitForExistence(timeout: 8))
    saveBtn.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["native-workflow-canvas-feedback"].firstMatch
        .waitForExistence(timeout: 10))
    XCTAssertEqual(app.webViews.count, 0)

    app.navigationBars.buttons.firstMatch.tap()
    let sharesTab = app.buttons["native-workflow-mode-社区分享"]
    XCTAssertTrue(sharesTab.waitForExistence(timeout: 10))
    tap(sharesTab, app: app)
    let forkBtn = app.buttons["native-workflow-fork-901"]
    XCTAssertTrue(forkBtn.waitForExistence(timeout: 10))
    tap(forkBtn, app: app)
    let confirmFork = app.alerts["复用工作流"].buttons["确认复用"]
    XCTAssertTrue(confirmFork.waitForExistence(timeout: 8))
    confirmFork.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["native-workflows-feedback"].firstMatch.waitForExistence(
        timeout: 10))
    XCTAssertEqual(app.webViews.count, 0)

    let counts = try await stats()
    XCTAssertEqual(counts["a"]?["GET api/v1/workflow/31"], 1)
    XCTAssertEqual(counts["a"]?["GET api/v1/workflow/actions"], 1)
    XCTAssertEqual(counts["a"]?["PUT api/v1/workflow/31"], 1)
    XCTAssertEqual(counts["a"]?["GET api/v1/workflow/shares"], 1)
    XCTAssertEqual(counts["a"]?["POST api/v1/workflow/fork"], 1)
    XCTAssertEqual(counts["unexpected"], [:])
  }

  /// P6.2b / P6.3b + 4+1 导航：验证统一 4+1 底栏（发现 / 订阅 / 我的 / 更多 + 全局搜索）、取消重复点击溢出菜单、更多总枢纽与右上角设置中心专项配置及用户编辑，零 WebView。
  func testNativeFourPlusOneNavOverflowDynamicActionAndSettingsHub() async throws {
    let app = try await signInToNativeBusiness()
    defer { app.terminate() }

    // 验证统一 4+1 底栏：发现 / 订阅 / 我的 / 更多 + 全局搜索（无独立探索与设置主标签）
    XCTAssertTrue(tabButton("发现", app: app).waitForExistence(timeout: 10))
    XCTAssertTrue(tabButton("订阅", app: app).exists)
    XCTAssertTrue(tabButton("我的", app: app).exists)
    XCTAssertTrue(tabButton("更多", app: app).exists)
    XCTAssertTrue(tabButton("搜索", app: app).exists)
    XCTAssertFalse(tabButton("探索", app: app).exists)
    XCTAssertFalse(tabButton("设置", app: app).exists)

    // 切到「更多」总枢纽，验证四大分组磁贴存在，且再次点击底栏不会弹出旧式溢出菜单
    tap(tabButton("更多", app: app), app: app)
    XCTAssertTrue(app.scrollViews["native-more-scroll"].waitForExistence(timeout: 8))
    XCTAssertTrue(app.buttons["native-workspace-resources"].exists)
    XCTAssertTrue(app.buttons["native-more-sites"].exists)
    XCTAssertTrue(app.buttons["native-workspace-downloads"].exists)
    XCTAssertTrue(app.buttons["native-workspace-files"].exists)
    XCTAssertTrue(app.buttons["native-workspace-history"].exists)
    XCTAssertFalse(app.buttons["native-workspace-music"].exists)
    XCTAssertFalse(app.buttons["native-workspace-agent"].exists)
    XCTAssertTrue(app.buttons["native-overflow-plugin-market"].exists)
    XCTAssertTrue(app.buttons["native-workspace-workflows"].exists)
    tap(tabButton("更多", app: app), app: app)
    XCTAssertFalse(app.descendants(matching: .any)["native-overflow-user-header"].exists)

    // 通过「更多」右上角齿轮按钮推入「设置」中心，验证站点/用户双卡、站点范围、目录/刮削保存/网络诊断
    openSettingsHub(app: app)
    XCTAssertTrue(app.buttons["native-workspace-sites"].waitForExistence(timeout: 10))
    let usersEntry = app.buttons["native-workspace-users"]
    XCTAssertTrue(usersEntry.exists)

    // 验证浮动智能助手形象存在
    XCTAssertTrue(app.buttons["native-agent-floating-mascot"].waitForExistence(timeout: 8))

    // 先进入顶部的「用户管理」验证右上角已有新增按钮时右下角统一保持「搜索」，并通过长按菜单编辑用户权限
    tap(usersEntry, app: app)
    XCTAssertTrue(app.scrollViews["native-users-scroll"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["native-users-add"].waitForExistence(timeout: 8))
    XCTAssertFalse(app.tabBars.buttons["新增用户"].exists)
    XCTAssertTrue(app.buttons["native-v2-search-tab-item"].waitForExistence(timeout: 5))
    let userCard = app.descendants(matching: .any)["native-user-card-20"].firstMatch
    reveal(userCard, app: app)
    XCTAssertTrue(userCard.waitForExistence(timeout: 8))
    userCard.press(forDuration: 1.0)
    let editUserMenu = app.buttons["编辑用户"]
    XCTAssertTrue(editUserMenu.waitForExistence(timeout: 8))
    editUserMenu.tap()
    let userSave = app.buttons["native-user-editor-save"]
    XCTAssertTrue(userSave.waitForExistence(timeout: 10))
    userSave.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["native-users-feedback"].firstMatch.waitForExistence(
        timeout: 10))
    app.navigationBars.buttons.firstMatch.tap()

    // 进入「常用配置 -> 站点范围」验证订阅与搜索站点范围可视化切换及保存
    let siteScopeTile = app.buttons["native-settings-hub-site-scope"]
    reveal(siteScopeTile, app: app)
    XCTAssertTrue(siteScopeTile.waitForExistence(timeout: 10))
    tap(siteScopeTile, app: app)
    XCTAssertTrue(app.scrollViews["native-sysmod-scroll"].waitForExistence(timeout: 10))
    let clearScope = app.buttons["native-sysmod-sitescope-clear"]
    XCTAssertTrue(clearScope.waitForExistence(timeout: 8))
    clearScope.tap()
    let scopeSave = app.buttons["native-sysmod-sitescope-save"]
    XCTAssertTrue(scopeSave.waitForExistence(timeout: 8))
    scopeSave.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["native-sysmod-feedback"].firstMatch.waitForExistence(
        timeout: 10))
    app.navigationBars.buttons.firstMatch.tap()

    // 再滚动进入原生分组列表中的「目录与存储映射」验证目录/刮削保存/网络诊断
    let dirsTile = app.buttons["native-settings-hub-directories"]
    reveal(dirsTile, app: app)
    XCTAssertTrue(dirsTile.waitForExistence(timeout: 10))
    tap(dirsTile, app: app)
    XCTAssertTrue(app.scrollViews["native-sysmod-scroll"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["默认电影目录"].waitForExistence(timeout: 10))

    let scrapingTab = app.buttons["native-sysmod-tab-刮削开关"]
    let sysBar = app.scrollViews["native-sysmod-bar"]
    if sysBar.exists && scrapingTab.frame.maxX > app.windows.firstMatch.frame.maxX - 8 {
      sysBar.swipeLeft()
    }
    scrapingTab.tap()
    toggle("native-sysmod-scrape-movie_nfo", to: false, app: app)
    let scrapeSave = app.buttons["native-sysmod-scraping-save"]
    XCTAssertTrue(scrapeSave.waitForExistence(timeout: 8))
    scrapeSave.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["native-sysmod-feedback"].firstMatch.waitForExistence(
        timeout: 10))

    let netTab = app.buttons["native-sysmod-tab-网络诊断"]
    if sysBar.exists && netTab.frame.maxX > app.windows.firstMatch.frame.maxX - 8 {
      sysBar.swipeLeft()
    }
    netTab.tap()
    let tmdbTest = app.buttons["native-sysmod-nettest-tmdb"]
    XCTAssertTrue(tmdbTest.waitForExistence(timeout: 10))
    tap(tmdbTest, app: app)
    XCTAssertTrue(app.staticTexts["连通正常 · 42 ms"].waitForExistence(timeout: 10))
    app.navigationBars.buttons.firstMatch.tap()

    // P7.2：验证脱离 WebCoordinator 的原生系统推送与桌面小组件设置弹窗
    let pushRow = app.buttons["native-settings-hub-push"]
    reveal(pushRow, app: app)
    XCTAssertTrue(pushRow.waitForExistence(timeout: 10))
    tap(pushRow, app: app)
    XCTAssertTrue(
      app.scrollViews["native-notification-settings-scroll"].waitForExistence(timeout: 10))
    app.buttons["native-notification-settings-close"].tap()

    let widgetRow = app.buttons["native-settings-hub-widgets"]
    reveal(widgetRow, app: app)
    XCTAssertTrue(widgetRow.waitForExistence(timeout: 10))
    tap(widgetRow, app: app)
    XCTAssertTrue(app.scrollViews["native-widget-settings-scroll"].waitForExistence(timeout: 10))
    app.buttons["native-widget-settings-close"].tap()

    // 切回「发现」确认右侧 +1 按钮自动回退为「搜索」
    tap(tabButton("发现", app: app), app: app)
    XCTAssertTrue(tabButton("搜索", app: app).waitForExistence(timeout: 8))
    XCTAssertEqual(app.webViews.count, 0)

    let counts = try await stats()
    XCTAssertEqual(counts["a"]?["GET api/v1/system/setting/Directories"], 1)
    XCTAssertEqual(counts["a"]?["POST api/v1/system/setting/ScrapingSwitchs"], 1)
    XCTAssertEqual(counts["a"]?["GET api/v1/system/nettest"], 1)
    XCTAssertEqual(counts["a"]?["PUT api/v1/user/"], 1)
    XCTAssertEqual(counts["unexpected"], [:])
  }

  /// 验证「更多」页快捷工具与系统诊断集合：系统检查、网络测试、名称识别/规则测试、实时日志与定时服务，零 WebView。
  func testNativeDiagnosticsAndShortcutsTools() async throws {
    let app = try await signInToNativeBusiness()
    defer { app.terminate() }

    openOverflowItem("native-shortcut-系统检查", app: app)
    XCTAssertTrue(app.scrollViews["native-diag-scroll"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["TMDB 元数据"].waitForExistence(timeout: 10))

    let ruleTab = app.buttons["native-diag-tab-识别与规则"]
    XCTAssertTrue(ruleTab.waitForExistence(timeout: 8))
    ruleTab.tap()
    let titleField = app.textFields["native-diag-test-title"]
    XCTAssertTrue(titleField.waitForExistence(timeout: 8))
    titleField.tap()
    titleField.typeText("The.Matrix.1999.2160p")
    let runBtn = app.buttons["native-diag-test-run"]
    XCTAssertTrue(runBtn.waitForExistence(timeout: 8))
    runBtn.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["native-diag-test-result"].firstMatch.waitForExistence(
        timeout: 10))

    let logTab = app.buttons["native-diag-tab-实时日志"]
    XCTAssertTrue(logTab.waitForExistence(timeout: 8))
    logTab.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["native-diag-log-output"].firstMatch.waitForExistence(
        timeout: 10))
    XCTAssertEqual(app.webViews.count, 0)

    let counts = try await stats()
    XCTAssertEqual(counts["a"]?["GET api/v1/system/modulelist"], 1)
    XCTAssertEqual(counts["a"]?["GET api/v1/media/recognize"], 1)
    XCTAssertGreaterThanOrEqual(counts["a"]?["GET api/v1/system/logging"] ?? 0, 1)
    XCTAssertEqual(counts["unexpected"], [:])
  }

  /// 验证外部 `moviepilot://` 路径联动深链：依次直达订阅分类、诊断词表、文件管理、整理历史、正在下载与关键词搜索，无效路径展示安全提示。
  func testNativeDeepLinkPathRouting() async throws {
    guard #available(iOS 16.4, *) else {
      throw XCTSkip("XCUIApplication.open(_:) 需要 iOS 16.4 及以上系统")
    }
    let app = try await signInToNativeBusiness()
    defer { app.terminate() }
    // 移除 cleanPicker 的重置参数，避免 `app.open(_:)` 触发重连时清空已保存的当前实例。
    app.launchArguments = arguments

    app.open(URL(string: "moviepilot://subscribe/movie")!)
    XCTAssertTrue(app.scrollViews["native-subscriptions-scroll"].waitForExistence(timeout: 15))

    app.open(URL(string: "moviepilot://diagnostics/words")!)
    XCTAssertTrue(app.scrollViews["native-diag-scroll"].waitForExistence(timeout: 15))

    app.open(URL(string: "moviepilot://files?storage=local&path=/")!)
    XCTAssertTrue(app.scrollViews["native-files-scroll"].waitForExistence(timeout: 15))

    app.open(URL(string: "moviepilot://history?search=Matrix")!)
    XCTAssertTrue(app.scrollViews["native-history-scroll"].waitForExistence(timeout: 15))

    app.open(URL(string: "moviepilot://open?path=/downloading")!)
    XCTAssertTrue(app.scrollViews["native-downloads-scroll"].waitForExistence(timeout: 15))

    app.open(URL(string: "moviepilot://search?q=Matrix")!)
    XCTAssertTrue(app.scrollViews["native-media-search-scroll"].waitForExistence(timeout: 15))

    app.open(URL(string: "moviepilot://shortcuts")!)
    XCTAssertTrue(app.scrollViews["native-more-scroll"].waitForExistence(timeout: 15))
    capture("sheet-preview-shortcuts")

    app.open(URL(string: "moviepilot://messages")!)
    XCTAssertTrue(app.scrollViews["native-messages-scroll"].waitForExistence(timeout: 15))
    capture("sheet-preview-messages")

    app.open(URL(string: "moviepilot://unknown/not-real")!)
    XCTAssertTrue(
      app.staticTexts["无法识别该 MoviePilot 链接路径，请检查链接格式。"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.webViews.count, 0)
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
    tap(tabButton("我的", app: app), app: app)
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
    let scheduleLabel = app.staticTexts["合成媒体库扫描"]
    reveal(scheduleLabel, app: app)
    XCTAssertTrue(scheduleLabel.waitForExistence(timeout: 8))
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
    XCTAssertFalse(tabButton("订阅", app: app).exists)
    XCTAssertFalse(tabButton("探索", app: app).exists)
    XCTAssertFalse(tabButton("搜索", app: app).exists)
    XCTAssertTrue(tabButton("更多", app: app).exists)
    let counts = try await stats()
    XCTAssertTrue(
      counts["b"]?.keys.allSatisfy {
        !$0.contains("/discover/") && !$0.contains("/media/") && !$0.contains("/dashboard/")
      } == true)
    XCTAssertEqual(counts["unexpected"], [:])
  }

  /// 从真实连接与登录进入当前会话，等待业务壳出现但保留它的默认选项。
  /// 验证深色「星夜紫玫」玻璃主题渲染层次与「播放偏好 -> STRM 直链播放」默认开启开关。
  func testNativeSettingsCinematicThemeAndStrmPlaybackToggle() async throws {
    let app = try await signInToNativeBusiness(
      extra: [
        "-nativeV2.appearance.mode", "dark",
        "-nativeV2.appearance.bgPreset", "cinematic",
        "-nativeV2.appearance.accentPreset", "violet",
      ])
    defer { app.terminate() }
    openSettingsHub(app: app)
    XCTAssertTrue(app.buttons["native-workspace-sites"].waitForExistence(timeout: 10))
    try await Task.sleep(nanoseconds: 1_500_000_000)
    capture("native-settings-cinematic-top")

    let scroll = app.scrollViews["native-settings-scroll"]
    scroll.swipeUp()
    try await Task.sleep(nanoseconds: 800_000_000)
    capture("native-settings-cinematic-bottom")

    scroll.swipeDown()
    let playbackRow = app.buttons["native-settings-playback"]
    reveal(playbackRow, app: app)
    XCTAssertTrue(playbackRow.waitForExistence(timeout: 10))
    tap(playbackRow, app: app)
    let strmToggle = app.switches["native-playback-strm-direct"]
    XCTAssertTrue(strmToggle.waitForExistence(timeout: 10))
    XCTAssertEqual(strmToggle.value as? String, "1")
  }

  private func signInToNativeBusiness(
    _ profile: String = "a", mode: String = "ready", extra: [String] = []
  )
    async throws -> XCUIApplication
  {
    try await configure(profile, mode: mode, reset: true)
    let app = try cleanPicker(extra: extra)
    connect(profile, app: app)
    enterCredentials(profile, app: app)
    tap(app.buttons["native-v2-login"], app: app)
    XCTAssertTrue(tabButton("我的", app: app).waitForExistence(timeout: 15))
    return app
  }

  /// 通过主标签「订阅」或「更多」总枢纽直达指定功能页面。
  private func openOverflowItem(
    _ identifier: String, viaTab tab: String = "更多", app: XCUIApplication
  ) {
    if identifier == "native-workspace-subscriptions" {
      let subTab = tabButton("订阅", app: app)
      XCTAssertTrue(subTab.waitForExistence(timeout: 10))
      tap(subTab, app: app)
      return
    }
    let moreTab = tabButton("更多", app: app)
    XCTAssertTrue(moreTab.waitForExistence(timeout: 10))
    tap(moreTab, app: app)
    if !app.scrollViews["native-more-scroll"].waitForExistence(timeout: 2.5) {
      tap(moreTab, app: app)
    }
    XCTAssertTrue(app.scrollViews["native-more-scroll"].waitForExistence(timeout: 8))
    let item = app.buttons[identifier]
    if !item.waitForExistence(timeout: 4) || !item.isHittable {
      reveal(item, app: app)
    }
    XCTAssertTrue(item.waitForExistence(timeout: 6))
    tap(item, app: app)
  }

  /// 通过「更多」主标签右上角齿轮按钮进入原生设置中心。
  private func openSettingsHub(app: XCUIApplication) {
    if app.scrollViews["native-settings-scroll"].exists
      && app.scrollViews["native-settings-scroll"].isHittable
    {
      return
    }
    let moreTab = tabButton("更多", app: app)
    XCTAssertTrue(moreTab.waitForExistence(timeout: 10))
    tap(moreTab, app: app)
    if !app.scrollViews["native-more-scroll"].waitForExistence(timeout: 2.5) {
      tap(moreTab, app: app)
    }
    let gearBtn = app.buttons["native-more-settings-btn"]
    XCTAssertTrue(gearBtn.waitForExistence(timeout: 8))
    gearBtn.tap()
    XCTAssertTrue(app.scrollViews["native-settings-scroll"].waitForExistence(timeout: 10))
  }

  /// iPhone 底栏、iPad 顶部浮动标签栏与 iPhone Duo 竖向侧边操作区结构不同，统一解析当前平台的原生入口按钮。
  private func tabButton(_ label: String, app: XCUIApplication) -> XCUIElement {
    let tabBarButton = app.tabBars.buttons[label]
    if tabBarButton.exists { return tabBarButton }
    let toolbarButton = app.toolbars.buttons["native-v2-tab-\(label)"].firstMatch
    if toolbarButton.exists { return toolbarButton }
    let identified = app.buttons["native-v2-tab-\(label)"].firstMatch
    if identified.exists { return identified }
    return app.buttons[label].firstMatch
  }

  /// 在已登录状态下优先匹配 iPad 展开侧边栏中的列表项，否则回退到通用标签/侧栏按钮。
  private func sidebarOrTabElement(_ label: String, app: XCUIApplication) -> XCUIElement {
    let cellText = app.cells.staticTexts[label].firstMatch
    if cellText.exists && cellText.isHittable { return cellText }
    return tabButton(label, app: app)
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
    tap(tabButton("更多", app: app), app: app)
    XCTAssertTrue(app.scrollViews["native-more-scroll"].waitForExistence(timeout: 8))
    XCTAssertFalse(app.buttons["native-overflow-plugin-market"].exists)
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
    openOverflowItem("native-overflow-plugin-market", app: app)
    let row = app.descendants(matching: .any)["native-installed-card-" + id].firstMatch
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
    openSettingsHub(app: app)
    tap(app.buttons["native-v2-switch"], app: app)
    XCTAssertTrue(app.textFields["native-v2-address"].waitForExistence(timeout: 10))
    capture("native-v2-01b-connection-saved")
    connect("b", app: app)
    XCTAssertEqual(app.textFields["native-v2-username"].value as? String, "用户名")
    XCTAssertEqual(app.switches["native-v2-remember-password"].value as? String, "0")
    enterCredentials("b", app: app)
    tap(app.buttons["native-v2-login"], app: app)
    assertAccount("b", app: app)
    openSettingsHub(app: app)
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
    openSettingsHub(app: app)
    tap(app.buttons["native-v2-logout"], app: app)
    if app.alerts["退出登录"].buttons["退出登录"].waitForExistence(timeout: 3) {
      app.alerts["退出登录"].buttons["退出登录"].tap()
    }
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

  /// 媒体服务器原生浏览、三层详情（剧/季/集）、播前音轨/字幕选择与最近入库入口端到端验证。
  func testMediaServerBrowseAndThreeLevelDetail() async throws {
    try await configure("a", mode: "mediaserver", reset: true)
    let app = try cleanPicker()
    connect("a", app: app)
    enterCredentials("a", app: app)
    tap(app.buttons["native-v2-login"], app: app)
    XCTAssertTrue(tabButton("我的", app: app).waitForExistence(timeout: 15))

    // 1. 发现页展示「媒体库」与「最新入库」卡片
    let providerCard = app.descendants(matching: .any)["native-discover-provider-library|lib-tv"]
      .firstMatch
    reveal(providerCard, app: app)
    XCTAssertTrue(providerCard.waitForExistence(timeout: 15))
    capture("native-v2-ms-01-discover")

    // 2. 点击媒体库卡片进入原生媒体库浏览页（含筛选与排序栏）
    tap(providerCard, app: app)
    let seriesCard = app.descendants(matching: .any)["native-mediaserver-item-series-100"]
      .firstMatch
    XCTAssertTrue(seriesCard.waitForExistence(timeout: 15))
    XCTAssertTrue(
      app.descendants(matching: .any)["native-mediaserver-filter-sort"].firstMatch.exists)
    XCTAssertTrue(
      app.descendants(matching: .any)["native-mediaserver-filter-played"].firstMatch.exists)
    capture("native-v2-ms-02-library")

    // 3. 点击剧集进入 Series 详情页（播放/订阅/搜索按钮 + 分季列表）
    tap(seriesCard, app: app)
    let detailTitle = app.staticTexts["native-mediaserver-detail-title"].firstMatch
    XCTAssertTrue(detailTitle.waitForExistence(timeout: 15))
    XCTAssertTrue(app.buttons["native-mediaserver-detail-play"].firstMatch.exists)
    XCTAssertTrue(app.buttons["native-mediaserver-detail-subscribe"].firstMatch.exists)
    capture("native-v2-ms-03-series")

    // 4. 点击第 1 季进入 Season 详情页（完整分集列表）
    let seasonCard = app.descendants(matching: .any)["native-mediaserver-season-season-1"]
      .firstMatch
    reveal(seasonCard, app: app)
    XCTAssertTrue(seasonCard.waitForExistence(timeout: 10))
    tap(seasonCard, app: app)
    let ep1Row = app.descendants(matching: .any)["native-mediaserver-episode-row-ep-101"].firstMatch
    reveal(ep1Row, app: app)
    XCTAssertTrue(ep1Row.waitForExistence(timeout: 15))
    capture("native-v2-ms-04-season")

    // 5. 点击第 1 集进入 Episode 详情页（播前版本/音轨/字幕选择器 + 剧/季面包屑）
    tap(ep1Row, app: app)
    let preplayCard = app.descendants(matching: .any)["native-mediaserver-preplay-selector"]
      .firstMatch
    reveal(preplayCard, app: app)
    XCTAssertTrue(preplayCard.waitForExistence(timeout: 15))
    XCTAssertTrue(
      app.descendants(matching: .any)["native-mediaserver-preplay-audio"].firstMatch.exists)
    XCTAssertTrue(
      app.descendants(matching: .any)["native-mediaserver-preplay-subtitle"].firstMatch.exists)
    capture("native-v2-ms-05-episode-tracks")

    let counts = try await stats()
    XCTAssertGreaterThanOrEqual(counts["a"]?["GET api/v1/mediaserver/library"] ?? 0, 1)
    XCTAssertGreaterThanOrEqual(counts["a"]?["GET api/v1/mediaserver/browse"] ?? 0, 1)
    XCTAssertGreaterThanOrEqual(counts["a"]?["GET api/v1/mediaserver/detail"] ?? 0, 3)
    XCTAssertGreaterThanOrEqual(counts["a"]?["GET api/v1/mediaserver/seasons"] ?? 0, 1)
    XCTAssertGreaterThanOrEqual(counts["a"]?["GET api/v1/mediaserver/season-episodes"] ?? 0, 1)
    XCTAssertTrue(
      counts["unexpected", default: [:]].isEmpty,
      "Unexpected requests: \(counts["unexpected"] ?? [:])")
    app.terminate()
  }

  /// 原生三语即时切换；P8 默认切换后无须调试参数即可直接进入原生入口，且零 WebView。
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
    // 默认冷启动（无任何 --native-v2 启动参数）直接进入原生 v2 入口
    app.launchArguments = ["-moviepilot.instance.selected.v1", "", "-AppleLanguages", "(zh-Hans)"]
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
    let modulesList = app.collectionViews["native-modules-list"]
    let detailScroll = app.scrollViews.matching(identifier: "native-media-detail-scroll")
      .allElementsBoundByIndex.last(where: { $0.isHittable })
    let personScroll = app.scrollViews.matching(identifier: "native-person-detail-scroll")
      .allElementsBoundByIndex.last(where: { $0.isHittable })
    let workspaceScroll = [
      "native-more-scroll", "native-diag-scroll", "native-appearance-scroll",
      "native-notification-settings-scroll", "native-widget-settings-scroll",
      "native-sysmod-scroll",
      "native-plugin-page-scroll", "native-dashboard-scroll",
      "native-agent-scroll", "native-plugin-market-scroll", "native-music-artist-scroll",
      "native-music-album-scroll", "native-music-scroll", "native-subscribe-editor-scroll",
      "native-community-scroll",
      "native-explore-scroll",
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
      (modulesList.exists ? modulesList : nil)
      ?? detailScroll
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
      "native-modules-save", "native-modules-cancel",
      "native-subscribe-editor-save", "native-subscribe-editor-cancel",
      "native-agent-sessions-close",
      "native-workflow-node-editor-apply", "native-workflow-node-editor-cancel",
      "native-workflow-catalog-close",
      "native-user-editor-save", "native-user-editor-cancel",
      "native-more-settings-btn",
      "native-subscriptions-community", "native-subscriptions-calendar",
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
    if [
      "发现", "订阅", "我的", "更多", "探索", "设置", "搜索", "保存", "添加节点", "新建目录", "新增用户", "新建对话",
    ].contains(element.label),
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

  /// 已认证账号标签必须属于本次服务（「我的」顶部身份卡），同时检查运行中的可访问性树没有 WebView。
  private func assertAccount(_ name: String, app: XCUIApplication) {
    let mineTab = tabButton("我的", app: app)
    if !app.descendants(matching: .any)["native-v2-account"].firstMatch.exists,
      mineTab.exists
    {
      tap(mineTab, app: app)
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

  /// 全面验收 iPad（横竖屏 + 侧栏工作台 + Bento 双列 + 多列网格）与 iPhone Duo（系统竖向侧边操作区替代传统底栏）的导航与页面布局，并采集实机截图供视觉核对。
  func testAdaptiveIPadAndDuoNavigationShowcase() async throws {
    continueAfterFailure = false
    let app = try await signInToNativeBusiness("a", mode: "ready")
    defer {
      XCUIDevice.shared.orientation = .portrait
      app.terminate()
    }
    let isPad = UIDevice.current.userInterfaceIdiom == .pad
    let isDuo = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4"

    if isDuo {
      // iPhone Duo 必须使用系统竖向侧边操作区，不再渲染传统底部 UITabBar。
      XCTAssertEqual(app.tabBars.count, 0, "iPhone Duo 应使用侧边操作区而非底部标签栏。")
      let laterBtn = app.buttons["以后"].firstMatch
      if laterBtn.waitForExistence(timeout: 2.5) {
        laterBtn.tap()
      }
      let discoverMore = app.buttons["native-discover-more-热门电影"]
      XCTAssertTrue(discoverMore.waitForExistence(timeout: 15))
      try await waitForArtwork("a", minimum: 2)
      capture("duo-01-discover")

      let tmdbCat = app.buttons["native-discover-category-tmdb_movies"]
      reveal(tmdbCat, app: app)
      XCTAssertTrue(tmdbCat.waitForExistence(timeout: 8))
      tap(tmdbCat, app: app)
      XCTAssertTrue(app.scrollViews["native-explore-scroll"].waitForExistence(timeout: 12))
      try await Task.sleep(nanoseconds: 1_200_000_000)
      capture("duo-02-explore")
      if app.navigationBars.buttons.element(boundBy: 0).exists {
        app.navigationBars.buttons.element(boundBy: 0).tap()
      }

      let subsBtn = tabButton("订阅", app: app)
      XCTAssertTrue(subsBtn.waitForExistence(timeout: 8))
      subsBtn.tap()
      XCTAssertTrue(app.scrollViews["native-subscriptions-scroll"].waitForExistence(timeout: 12))
      try await Task.sleep(nanoseconds: 1_000_000_000)
      capture("duo-06-subscriptions")

      let mineBtn = tabButton("我的", app: app)
      XCTAssertTrue(mineBtn.waitForExistence(timeout: 8))
      mineBtn.tap()
      XCTAssertTrue(app.scrollViews["native-dashboard-scroll"].waitForExistence(timeout: 12))
      try await Task.sleep(nanoseconds: 1_200_000_000)
      capture("duo-03-dashboard")

      let moreBtn = tabButton("更多", app: app)
      XCTAssertTrue(moreBtn.waitForExistence(timeout: 8), "iPhone Duo 侧边操作区应提供「更多」主入口。")
      moreBtn.tap()
      XCTAssertTrue(app.scrollViews["native-more-scroll"].waitForExistence(timeout: 12))
      try await Task.sleep(nanoseconds: 600_000_000)
      capture("duo-05-more")

      let settingsGear = app.buttons["native-more-settings-btn"]
      XCTAssertTrue(settingsGear.waitForExistence(timeout: 8))
      settingsGear.tap()
      XCTAssertTrue(app.scrollViews["native-settings-scroll"].waitForExistence(timeout: 12))
      try await Task.sleep(nanoseconds: 800_000_000)
      capture("duo-04-settings")

      // 返回更多根页并验证侧边操作区的搜索与智能助手入口
      let backCandidates = [
        app.buttons["返回"].firstMatch,
        app.buttons["Back"].firstMatch,
        app.buttons["更多"].firstMatch,
        app.navigationBars.buttons.element(boundBy: 0),
      ]
      if let backBtn = backCandidates.first(where: { $0.exists && $0.isHittable }) {
        backBtn.tap()
        try await Task.sleep(nanoseconds: 800_000_000)
      }
      let searchBtn = app.buttons["native-v2-search-tab-item"].firstMatch
      if searchBtn.waitForExistence(timeout: 6) {
        searchBtn.tap()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        capture("duo-07-search")
      }
      let agentBtn = app.buttons["native-duo-agent"].firstMatch
      if agentBtn.waitForExistence(timeout: 6) {
        agentBtn.tap()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        capture("duo-08-agent")
      }
      return
    }

    if isPad {
      XCUIDevice.shared.orientation = .portrait
      let discoverMore = app.buttons["native-discover-more-热门电影"]
      XCTAssertTrue(discoverMore.waitForExistence(timeout: 15))
      try await waitForArtwork("a", minimum: 2)
      capture("ipad-portrait-01-discover")

      let tmdbCat = app.buttons["native-discover-category-tmdb_movies"]
      reveal(tmdbCat, app: app)
      if tmdbCat.waitForExistence(timeout: 8) {
        tap(tmdbCat, app: app)
        try await Task.sleep(nanoseconds: 1_200_000_000)
        capture("ipad-portrait-02-explore")
        if app.navigationBars.buttons.firstMatch.exists {
          app.navigationBars.buttons.firstMatch.tap()
        }
      }

      tabButton("订阅", app: app).tap()
      XCTAssertTrue(app.scrollViews["native-subscriptions-scroll"].waitForExistence(timeout: 12))
      try await Task.sleep(nanoseconds: 1_000_000_000)
      capture("ipad-portrait-02b-subscriptions")

      tabButton("我的", app: app).tap()
      XCTAssertTrue(app.scrollViews["native-dashboard-scroll"].waitForExistence(timeout: 12))
      try await Task.sleep(nanoseconds: 1_200_000_000)
      capture("ipad-portrait-03-dashboard")

      tabButton("更多", app: app).tap()
      XCTAssertTrue(app.scrollViews["native-more-scroll"].waitForExistence(timeout: 12))
      try await Task.sleep(nanoseconds: 600_000_000)
      capture("ipad-portrait-04-more")

      let settingsGear = app.buttons["native-more-settings-btn"]
      if settingsGear.waitForExistence(timeout: 6) {
        settingsGear.tap()
        XCTAssertTrue(app.scrollViews["native-settings-scroll"].waitForExistence(timeout: 12))
        try await Task.sleep(nanoseconds: 800_000_000)
        capture("ipad-portrait-04b-settings")
        app.navigationBars.buttons.firstMatch.tap()
      }

      // 切换横屏验收 iPadOS 原生侧边栏工作台（「我的订阅」双列、「下载」、发现页、仪表盘 Bento 双列与更多总枢纽）
      XCUIDevice.shared.orientation = .landscapeLeft
      try await Task.sleep(nanoseconds: 1_200_000_000)

      let subsCell = app.cells.staticTexts["我的订阅"].firstMatch
      if subsCell.waitForExistence(timeout: 6) {
        subsCell.tap()
        XCTAssertTrue(app.scrollViews["native-subscriptions-scroll"].waitForExistence(timeout: 12))
        try await Task.sleep(nanoseconds: 1_000_000_000)
        capture("ipad-landscape-01-sidebar-subscriptions")
      }

      sidebarOrTabElement("发现", app: app).tap()
      try await Task.sleep(nanoseconds: 1_200_000_000)
      capture("ipad-landscape-02-discover")

      sidebarOrTabElement("我的", app: app).tap()
      XCTAssertTrue(app.scrollViews["native-dashboard-scroll"].waitForExistence(timeout: 12))
      try await Task.sleep(nanoseconds: 1_200_000_000)
      capture("ipad-landscape-03-dashboard")

      sidebarOrTabElement("更多", app: app).tap()
      XCTAssertTrue(app.scrollViews["native-more-scroll"].waitForExistence(timeout: 12))
      try await Task.sleep(nanoseconds: 800_000_000)
      capture("ipad-landscape-04-more")

      let downloadsCell = app.cells.staticTexts["下载"].firstMatch
      if downloadsCell.waitForExistence(timeout: 5) {
        downloadsCell.tap()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        capture("ipad-landscape-05-downloads")
      }
      return
    }
  }

  /// 画面只保留合成实例，明确作为运行验收而非尚未实现业务页的设计图。
  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
