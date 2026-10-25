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

  /// 实际订阅卡片进入批量选择并更新计数，再打开原编辑表单；不保存或删除订阅。
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

  /// 文件操作打开原详情组件，只有系统标题及关闭按钮，返回后目录保持原位。
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
