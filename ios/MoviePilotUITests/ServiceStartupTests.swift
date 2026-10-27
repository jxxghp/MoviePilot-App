import XCTest

/// 使用独立回环服务验证启动等待、真实生命周期和认证边界，不访问用户实例。
@MainActor
final class ServiceStartupTests: XCTestCase {
  private let base = URL(string: "http://127.0.0.1:5244")!
  private let initialization = "/api/v1/login/initialization"
  private let login = "/api/v1/login/access-token"

  /// 多次 HTTP 故障和连接中断后自动进入登录，等待过程没有表单、网页或密码提交。
  func testAutomaticServiceRecovery() async throws {
    try await configure("unavailable", reset: true)
    let app = try launch("automatic")
    assertWaiting(app)
    capture("服务等待")
    try await waitForRequests(initialization, atLeast: 2)
    try await configure("unavailable", status: 502)
    let count = try await stats()[initialization, default: 0]
    try await waitForRequests(initialization, atLeast: count + 1)
    try await configure("disconnected")
    try await waitForRequests(initialization, atLeast: count + 2)
    assertWaiting(app)
    try await configure("ready")
    XCTAssertTrue(app.textFields["用户名"].waitForExistence(timeout: 15), app.debugDescription)
    XCTAssertFalse(app.otherElements["native-service-status"].exists)
    XCTAssertFalse(app.webViews.firstMatch.exists)
    let requests = try await stats()
    XCTAssertEqual(requests[login, default: 0], 0)
    capture("服务等待-自动恢复登录")
  }

  /// 手动重试不叠加循环，更改地址后旧实例不再发出探测或迟到跳转。
  func testRetryAndChangeAddressCancelOldProbe() async throws {
    try await configure("unavailable", reset: true)
    let app = try launch("cancel")
    assertWaiting(app)
    let before = try await stats()[initialization, default: 0]
    app.buttons["native-service-retry"].tap()
    try await waitForRequests(initialization, atLeast: before + 1)
    assertWaiting(app)
    app.buttons["native-service-change-address"].tap()
    XCTAssertTrue(app.textFields["MoviePilot 服务地址"].waitForExistence(timeout: 10))
    try await Task.sleep(for: .milliseconds(300))
    let stopped = try await stats()[initialization, default: 0]
    try await configure("ready")
    try await Task.sleep(for: .seconds(2))
    let requests = try await stats()
    XCTAssertEqual(requests[initialization, default: 0], stopped)
    XCTAssertEqual(requests[login, default: 0], 0)
    XCTAssertTrue(app.textFields["MoviePilot 服务地址"].isHittable)
  }

  /// 真正进入后台后停止轮询，回到前台继续检测并自动恢复登录。
  func testBackgroundPausesServiceProbe() async throws {
    try await configure("unavailable", reset: true)
    let app = try launch("background")
    assertWaiting(app)
    XCUIDevice.shared.press(.home)
    try await Task.sleep(for: .seconds(1))
    let paused = try await stats()[initialization, default: 0]
    try await Task.sleep(for: .seconds(2))
    let background = try await stats()
    XCTAssertEqual(background[initialization, default: 0], paused)
    app.activate()
    try await waitForRequests(initialization, atLeast: paused + 1)
    assertWaiting(app)
    try await configure("ready")
    XCTAssertTrue(app.textFields["用户名"].waitForExistence(timeout: 15))
  }

  /// 初始化查询成功但令牌校验暂不可用时保留会话，就绪后直达实际前端首页，401 才重新登录。
  func testSavedSessionSurvivesServiceRestart() async throws {
    try await configure("expired", reset: true)
    let app = try launch("saved")
    XCTAssertTrue(app.textFields["用户名"].waitForExistence(timeout: 15))
    try await configure("ready")
    app.textFields["用户名"].tap()
    app.textFields["用户名"].typeText("startup-fixture")
    app.secureTextFields["密码"].tap()
    app.secureTextFields["密码"].typeText("fixture-only\n")
    XCTAssertFalse(app.alerts["已登录"].waitForExistence(timeout: 1), "模拟器必须能保存 Keychain")
    XCTAssertTrue(
      app.tabBars["native-root-navigation"].waitForExistence(timeout: 45), app.debugDescription)
    app.terminate()
    try await configure("restore-unavailable", reset: true)
    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    app.launch()
    assertWaiting(app)
    try await waitForRequests("/api/v1/user/current", atLeast: 2)
    try await configure("ready")
    XCTAssertTrue(
      app.tabBars["native-root-navigation"].waitForExistence(timeout: 45), app.debugDescription)
    XCTAssertFalse(app.textFields["用户名"].exists)
    let requests = try await stats()
    XCTAssertEqual(requests[login, default: 0], 0)
    capture("服务等待-会话恢复首页")
    app.terminate()
    try await configure("expired")
    app.launch()
    XCTAssertTrue(app.textFields["用户名"].waitForExistence(timeout: 15))
  }

  /// 损坏响应不能被当作服务启动无限重试，尚未初始化则继续使用既有准备说明和重新检查。
  func testInvalidAndUninitializedResponsesKeepExplicitRecovery() async throws {
    try await configure("invalid", reset: true)
    let app = try launch("response")
    XCTAssertTrue(app.staticTexts["认证接口返回了不支持的数据，请更新实例或检查服务后重试。"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.otherElements["native-service-status"].exists)
    try await Task.sleep(for: .seconds(2))
    let requests = try await stats()
    XCTAssertEqual(requests[initialization, default: 0], 1)
    app.terminate()
    try await configure("uninitialized")
    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    app.launch()
    XCTAssertTrue(app.buttons["重新检查"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.otherElements["native-service-status"].exists)
    try await configure("legacy")
    app.buttons["重新检查"].tap()
    XCTAssertTrue(app.buttons["登录"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["重新检查"].exists)
  }

  /// 密码提交收到503后只显示原来的错误，不进入自动等待或重放包含凭据的请求。
  func testPasswordSubmissionIsNeverAutomaticallyRetried() async throws {
    try await configure("ready", reset: true)
    let app = try launch("submit")
    XCTAssertTrue(app.textFields["用户名"].waitForExistence(timeout: 15))
    try await configure("login-unavailable")
    app.textFields["用户名"].tap()
    app.textFields["用户名"].typeText("startup-fixture")
    app.secureTextFields["密码"].tap()
    app.secureTextFields["密码"].typeText("fixture-only\n")
    XCTAssertTrue(app.staticTexts["无法连接此实例，请检查地址、网络和服务状态。"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.otherElements["native-service-status"].exists)
    try await Task.sleep(for: .seconds(2))
    let requests = try await stats()
    XCTAssertEqual(requests[login, default: 0], 1)
    XCTAssertTrue(app.buttons["登录"].isEnabled)
  }

  /// 横屏和最大辅助功能字号保留可滚动的状态及操作，深色资源不依赖网络。
  func testServiceWaitingLayout() async throws {
    try await configure("unavailable", reset: true)
    let app = try launch("layout", largeText: true)
    XCTAssertTrue(app.otherElements["native-service-status"].waitForExistence(timeout: 10))
    XCUIDevice.shared.orientation = .landscapeLeft
    defer { XCUIDevice.shared.orientation = .portrait }
    let rotated = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed, "必须完成实际横屏布局")
    app.swipeUp()
    XCTAssertTrue(app.buttons["native-service-change-address"].isHittable, app.debugDescription)
    capture("服务等待-横屏大字号")
    app.buttons["native-service-change-address"].tap()
    XCTAssertTrue(app.textFields["MoviePilot 服务地址"].waitForExistence(timeout: 10))
  }

  /// 各用例只通过真实地址输入连接独立实例，不向产品注入网络或认证状态。
  private func launch(_ scenario: String, largeText: Bool = false) throws -> XCUIApplication {
    guard ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_SERVICE_WAIT"] == "1" else {
      throw XCTSkip("需要显式启动 scripts/service-startup-fixture.py 本机隔离服务。")
    }
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    let app = XCUIApplication()
    app.launchArguments = [
      "-moviepilot.instance.selected.v1", "", "-AppleLanguages", "(zh-Hans)", "-AppleLocale",
      "zh_CN",
    ]
    if largeText {
      app.launchArguments += [
        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
      ]
    }
    app.launch()
    let field = app.textFields["MoviePilot 服务地址"]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    field.tap()
    let clear = field.buttons.firstMatch
    if clear.exists { clear.tap() }
    field.typeText(base.appendingPathComponent(scenario, isDirectory: true).absoluteString + "\n")
    return app
  }

  /// 等待页必须真正遮住登录与网页，两个恢复出口都保持可交互。
  private func assertWaiting(_ app: XCUIApplication) {
    XCTAssertTrue(
      app.otherElements["native-service-status"].waitForExistence(timeout: 15), app.debugDescription
    )
    XCTAssertFalse(app.textFields["用户名"].isHittable)
    XCTAssertFalse(app.navigationBars["登录"].exists)
    XCTAssertFalse(app.webViews.firstMatch.exists)
    XCTAssertTrue(app.buttons["native-service-retry"].isHittable)
    XCTAssertTrue(app.buttons["native-service-change-address"].isHittable)
  }

  /// 控制端只改变合成服务状态，不修改 App、真实后端或用户配置。
  private func configure(_ mode: String, reset: Bool = false, status: Int = 503) async throws {
    guard ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_SERVICE_WAIT"] == "1" else {
      throw XCTSkip("需要显式启动本机隔离服务。")
    }
    var request = URLRequest(url: base.appendingPathComponent("__service/config"))
    request.httpMethod = "POST"
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "mode": mode, "reset": reset, "status": status,
    ])
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let (_, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
  }

  /// 请求统计只含接口路径及次数，不读取或输出令牌、密码及请求正文。
  private func stats() async throws -> [String: Int] {
    let (data, _) = try await URLSession.shared.data(
      from: base.appendingPathComponent("__service/stats"))
    return try JSONDecoder().decode([String: Int].self, from: data)
  }

  /// 在有限时间内观察真实 HTTP 请求，避免仅凭等待页仍可见判断轮询成功。
  private func waitForRequests(_ path: String, atLeast count: Int) async throws {
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline {
      if try await stats()[path, default: 0] >= count { return }
      try await Task.sleep(for: .milliseconds(100))
    }
    XCTFail("未观察到预期的只读探测次数")
  }

  /// 采集整块屏幕以保留真实旋转几何，截图不包含真实实例地址或账号。
  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
