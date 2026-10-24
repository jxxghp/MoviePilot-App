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
  /// 同时验证原生初始化请求与真实 WKWebView 加载，不能用宿主进程请求代替 App 网络。
  func testLocalNetworkTransports() async throws {
    let fixtures = try await networkFixtures()
    XCTAssertGreaterThanOrEqual(fixtures.servers.count, 4, "需覆盖 IPv4、IPv6、私网及本地名称")
    for (index, server) in fixtures.servers.enumerated() {
      let app = try launchLogin(server: server)
      XCTAssertTrue(app.buttons["在网页初始化"].waitForExistence(timeout: 25), "原生请求须收到夹具的未初始化状态")
      app.buttons["使用网页登录"].tap()
      XCTAssertTrue(app.webViews.staticTexts["网络连接验收就绪"].waitForExistence(timeout: 20))
      attachScreen("网络-原生请求与网页加载-\(index + 1)", app: app)
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
      XCTAssertTrue(app.buttons["使用网页登录"].isEnabled)
      attachScreen("网络-原生失败提示-\(index + 1)", app: app)
      if index < 2 {
        app.buttons["使用网页登录"].tap()
        XCTAssertTrue(app.staticTexts[scenario.1].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["重新打开"].isEnabled)
        app.buttons["更改服务地址"].tap()
        XCTAssertTrue(app.textFields["MoviePilot 服务地址"].waitForExistence(timeout: 10))
        attachScreen("网络-失败后更改地址-\(index + 1)", app: app)
      }
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

  /// 受控首屏资源门关闭时只显示静态原生启动页，释放后才交接到可访问的真实 WebView。
  func testStaticStartupWaitsForContent() async throws {
    guard let address = ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_STARTUP_FIXTURE"],
      let server = URL(string: address)
    else { throw XCTSkip("仅在显式配置的本机启动资源夹具中执行。") }
    _ = try await URLSession.shared.data(from: server.appendingPathComponent("__reset"))
    let app = try launchLogin()
    app.buttons["使用网页登录"].tap()
    let startup = app.otherElements["native-startup-screen"]
    XCTAssertTrue(startup.waitForExistence(timeout: 10))
    XCTAssertFalse(app.webViews.firstMatch.exists, "资源门未完成时不能提前访问网页")
    XCTAssertFalse(app.navigationBars.firstMatch.exists, "静态启动页不露出中间态导航")
    attachScreen("交互-静态启动画面", app: app)
    _ = try await URLSession.shared.data(from: server.appendingPathComponent("__release"))
    XCTAssertTrue(app.webViews.staticTexts["网页资源已就绪"].waitForExistence(timeout: 10))
    XCTAssertFalse(startup.exists)
    attachScreen("验收-资源完成后显示受控网页", app: app)
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
    let search = app.descendants(matching: .any)["more-menu-search"]
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
      let search = app.descendants(matching: .any)["more-menu-search"]
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

  /// 页面标题栏筛选也使用原生列表，选择继续更新已有 Vue 筛选条件。
  func testNativePageHeaderActions() throws {
    let app = try signIn()
    app.tabBars["native-root-navigation"].buttons["更多"].tap()
    let menu = app.tables["more-menu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 10))
    let search = app.descendants(matching: .any)["more-menu-search"]
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
    let search = app.descendants(matching: .any)["more-menu-search"]
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
    let search = app.descendants(matching: .any)["more-menu-search"]
    search.tap()
    search.typeText("设定")
    menu.cells.containing(.staticText, identifier: "设定").firstMatch.tap()
    XCTAssertTrue(app.buttons["设定，页内分类"].waitForExistence(timeout: 15))
    settlePage(app)
    XCTAssertFalse(app.webViews.staticTexts["API Token不得低于16位"].exists)
    attachScreen("页面-设定", app: app)
    attachScreen("页面-设定 · 系统", app: app)
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
    let search = app.descendants(matching: .any)["more-menu-search"]
    search.tap()
    search.typeText("插件")
    menu.cells.containing(.staticText, identifier: "插件").firstMatch.tap()
    XCTAssertTrue(app.buttons["插件，页内分类"].waitForExistence(timeout: 15))
    app.buttons["操作菜单"].tap()
    app.buttons["用户菜单"].firstMatch.tap()
    let panel = app.tables["native-quick-panel"]
    XCTAssertTrue(panel.waitForExistence(timeout: 8), "用户入口必须使用 UIKit 列表")
    XCTAssertGreaterThan(panel.frame.minY, app.navigationBars.firstMatch.frame.minY)
    if !panel.cells["native-panel-item-glass"].exists {
      // 主题偏好跨启动保留，测试经真实设置入口恢复前置条件，不依赖前一个用例。
      panel.cells["native-panel-item-customizer"].tap()
      XCTAssertTrue(app.navigationBars["主题定制"].waitForExistence(timeout: 10))
      let glass = app.webViews.staticTexts["玻璃"].firstMatch
      XCTAssertTrue(glass.waitForExistence(timeout: 8))
      glass.tap()
      settlePage(app)
      dismissOverlays(app)
      app.buttons["操作菜单"].tap()
      XCTAssertTrue(app.buttons["用户菜单"].firstMatch.waitForExistence(timeout: 5))
      app.buttons["用户菜单"].firstMatch.tap()
      XCTAssertTrue(panel.waitForExistence(timeout: 8))
    }
    attachScreen("交互-原生用户菜单", app: app)
    XCTAssertTrue(panel.cells["native-panel-item-glass"].waitForExistence(timeout: 5))
    XCTAssertFalse(panel.cells["native-panel-item-theme"].exists, "三个主题入口不再另开二级浮层")
    attachScreen("交互-用户菜单内主题分组", app: app)
    panel.cells["native-panel-item-glass"].tap()
    XCTAssertFalse(panel.waitForExistence(timeout: 1), "打开业务弹窗前关闭系统面板")
    XCTAssertTrue(app.navigationBars["玻璃设置"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["native-sheet-close"].exists)
    XCTAssertFalse(app.webViews.staticTexts["玻璃设置"].exists, "HTML 标题由原生栏接管")
    settlePage(app)
    attachScreen("交互-HTML全屏设置与模糊背景", app: app)
    XCTAssertFalse(app.tabBars["native-root-navigation"].exists, "只有全屏弹窗隐藏底栏")
    dismissOverlays(app)
    app.buttons["操作菜单"].tap()
    app.buttons["用户菜单"].firstMatch.tap()
    XCTAssertTrue(panel.waitForExistence(timeout: 8))
    panel.cells["native-panel-item-customizer"].tap()
    XCTAssertTrue(app.navigationBars["主题定制"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["native-sheet-close"].exists)
    XCTAssertTrue(app.webViews.staticTexts["色调"].firstMatch.waitForExistence(timeout: 10))
    XCTAssertFalse(app.tabBars["native-root-navigation"].exists, "自定义全屏设置也隐藏底栏")
    attachScreen("交互-主题定制安全区", app: app)
    dismissOverlays(app)
    app.tabBars["native-root-navigation"].buttons["更多"].tap()
    XCTAssertTrue(menu.waitForExistence(timeout: 10), "从业务页点击更多必须立即回到原生目录")
    XCTAssertFalse(app.buttons["返回"].exists, "回到目录后不能残留业务返回栈")
  }

  /// 通过原主题控件切换明暗，验证系统浮层与 HTML Sheet 的自适应材质。
  func testNativeMaterialsInLightAndDarkThemes() throws {
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
    for theme in ["浅色", "深色", "玻璃"] {
      app.buttons["操作菜单"].tap()
      app.buttons["用户菜单"].firstMatch.tap()
      let panel = app.tables["native-quick-panel"]
      XCTAssertTrue(panel.waitForExistence(timeout: 8))
      panel.cells["native-panel-item-customizer"].tap()
      XCTAssertTrue(app.navigationBars["主题定制"].waitForExistence(timeout: 10))
      let choice = app.webViews.staticTexts[theme].firstMatch
      XCTAssertTrue(choice.waitForExistence(timeout: 8))
      choice.tap()
      settlePage(app)
      attachScreen("交互-\(theme)主题系统磨砂 Sheet", app: app)
      app.buttons["native-sheet-close"].tap()
      XCTAssertFalse(app.buttons["native-sheet-close"].waitForExistence(timeout: 1))
      settlePage(app)
      if theme == "玻璃" { continue }
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
      XCTAssertLessThan(panel.frame.maxY, app.frame.height - 75, "普通面板为底栏保留显示区域")
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
    app.buttons["用户菜单"].firstMatch.tap()
    let userPanel = app.tables["native-quick-panel"]
    XCTAssertTrue(userPanel.waitForExistence(timeout: 8))
    settlePage(app)
    let medals = userPanel.cells["native-panel-item-medals"]
    if medals.waitForExistence(timeout: 3) {
      if !medals.isHittable {
        // 系统浮层的表格框包含导航栏，用内容区中的明确触点执行真实滚动。
        userPanel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).press(
          forDuration: 0.05,
          thenDragTo: userPanel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
      }
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
      app.buttons["native-panel-close"].tap()
    }
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
    let run = panel.cells["native-panel-item-run-media"]
    XCTAssertTrue(run.waitForExistence(timeout: 5))
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
    panel.cells["native-panel-item-nameTest"].tap()
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

  /// 显式启用受控勋章夹具时，关闭按钮必须位于弹窗内部右上角且可以完成关闭。
  func testCommunityMedalClosePlacement() throws {
    guard ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_MEDALS"] == "1" else {
      throw XCTSkip("勋章位置验收需要启用受控社区资料夹具。")
    }
    let app = try signIn()
    app.buttons["操作菜单"].tap()
    app.buttons["用户菜单"].firstMatch.tap()
    let panel = app.tables["native-quick-panel"]
    XCTAssertTrue(panel.waitForExistence(timeout: 8))
    let medals = panel.cells["native-panel-item-medals"]
    settlePage(app)
    for _ in 0..<5 {
      if medals.exists && medals.isHittable { break }
      panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).press(
        forDuration: 0.05,
        thenDragTo: panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
    }
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

  /// 输入框避让只处理尺寸和焦点变化；用户仍能手动滚到下方操作并打开原网页。
  func testAccountKeyboardAllowsManualScroll() async throws {
    let fixtures = try await networkFixtures()
    let server = try XCTUnwrap(fixtures.servers.first, "网络夹具至少提供一个可连接地址")
    let app = try launchLogin(server: server)
    app.secureTextFields["密码"].tap()
    XCUIDevice.shared.orientation = .landscapeLeft
    settlePage(app)
    let scroll = app.scrollViews.firstMatch
    let webLogin = app.buttons["使用网页登录"]
    for _ in 0..<6 {
      if webLogin.isHittable { break }
      scroll.swipeUp()
    }
    attachScreen("框架-横屏手动滚到登录操作", app: app)
    XCTAssertTrue(webLogin.isHittable, "手动滚动不能被输入框自动定位拉回")
    webLogin.tap()
    XCTAssertTrue(app.webViews.staticTexts["网络连接验收就绪"].waitForExistence(timeout: 20))
    XCUIDevice.shared.orientation = .portrait
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
  private func launchLogin(server: String? = nil) throws -> XCUIApplication {
    guard let server = server ?? ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_SERVER"],
      !server.isEmpty
    else { throw XCTSkip("需要指定私有验收实例。") }
    let app = launchConnection(server: server)
    let account = app.textFields["用户名"]
    XCTAssertTrue(account.waitForExistence(timeout: 15))
    XCTAssertTrue(app.secureTextFields["密码"].exists)
    attachScreen("框架-登录", app: app)
    return app
  }

  /// 启动空白选择并通过真实地址输入提交连接，供成功路径与地址校验失败共用。
  private func launchConnection(server: String) -> XCUIApplication {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    let app = XCUIApplication()
    app.launchArguments = [
      "-moviepilot.instance.selected.v1", "", "-AppleLanguages", "(zh-Hans)",
      "-AppleLocale", "zh_CN",
    ]
    app.launch()
    let address = app.textFields["MoviePilot 服务地址"]
    XCTAssertTrue(address.waitForExistence(timeout: 10))
    attachScreen("框架-连接", app: app)
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

  /// 从任意业务页重置更多目录，再按原目录标题打开页面，不直接操纵 Web 路由。
  private func openMorePage(_ title: String, app: XCUIApplication) {
    app.tabBars["native-root-navigation"].buttons["更多"].tap()
    let menu = app.tables["more-menu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 10))
    let search = app.descendants(matching: .any)["more-menu-search"]
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
