import XCTest

/// 两个独立回环服务通过真实表单、Keychain 和 WebKit 验证多服务切换，不访问生产实例。
@MainActor
final class ServerProfileTests: XCTestCase {
  private let servers = ["http://127.0.0.1:5294/", "http://127.0.0.1:5295/"]
  private let language = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]

  /// 地址列表和各自令牌跨切换、重启保留，过期后只回填对应账号而不自动发送密码。
  func testSwitchesSavedServersAndRestoresSeparateAccounts() async throws {
    try await configure(0, mode: "ready", reset: true)
    try await configure(1, mode: "ready", reset: true)
    let app = try launchCleanPicker()
    connect(0, app: app)
    authenticate("a", app: app)
    openPicker(app)
    connect(1, app: app)
    XCTAssertNotEqual(app.textFields["用户名"].value as? String, "server-a")
    XCTAssertEqual(app.switches["native-remember-credentials"].value as? String, "0")
    authenticate("b", app: app)
    openPicker(app)
    XCTAssertFalse(app.buttons["删除"].exists)
    capture("多服务-已保存地址")
    _ = revealDelete(0, app: app)
    capture("多服务-左滑删除")
    saved(0, app: app).swipeRight()
    XCTAssertFalse(app.buttons["删除"].exists)
    selectSaved(0, app: app)
    assertHome(app)
    XCTAssertFalse(app.textFields["用户名"].exists)
    app.terminate()
    app.launchArguments = language
    app.launch()
    assertHome(app)
    let first = try await stats(0)
    let second = try await stats(1)
    XCTAssertEqual(first["/api/v1/login/access-token", default: 0], 1)
    XCTAssertEqual(second["/api/v1/login/access-token", default: 0], 1)

    app.terminate()
    try await configure(0, mode: "expired", reset: true)
    try await configure(1, mode: "expired", reset: true)
    app.launch()
    assertCredentials("a", app: app)
    capture("多服务-当前服务回填")
    app.buttons["更改地址"].tap()
    selectSaved(1, app: app)
    assertCredentials("b", app: app)
    let expiredFirst = try await stats(0)
    let expiredSecond = try await stats(1)
    XCTAssertEqual(expiredFirst["/api/v1/login/access-token", default: 0], 0)
    XCTAssertEqual(expiredSecond["/api/v1/login/access-token", default: 0], 0)
    // 不重新输入，直接验证回填后的密码可成功登录当前服务。
    try await configure(1, mode: "ready")
    app.buttons["登录"].tap()
    assertHome(app)
    openPicker(app)
    try await configure(1, mode: "expired")
    selectSaved(1, app: app)
    assertCredentials("b", app: app)
    app.switches["native-remember-credentials"].tap()
    app.buttons["更改地址"].tap()
    selectSaved(1, app: app)
    assertNoCredentials(app)
    app.terminate()
  }

  /// OTP 挑战和错误密码不会覆盖已保存账号，关闭记忆与删除服务立即清除本机凭据。
  func testOTPFailedLoginAndForgettingCredentials() async throws {
    try await configure(0, mode: "otp", reset: true)
    let app = try launchCleanPicker()
    connect(0, app: app)
    enterCredentials("a", app: app)
    app.buttons["登录"].tap()
    XCTAssertTrue(app.textFields["身份验证器验证码"].waitForExistence(timeout: 10))
    app.buttons["更改地址"].tap()
    selectSaved(0, app: app)
    assertNoCredentials(app)
    enterCredentials("a", app: app)
    app.buttons["登录"].tap()
    let code = app.textFields["身份验证器验证码"]
    XCTAssertTrue(code.waitForExistence(timeout: 10))
    code.tap()
    code.typeText("123456")
    app.buttons["登录"].tap()
    assertHome(app)

    app.terminate()
    app.launchArguments = language
    try await configure(0, mode: "expired", reset: true)
    app.launch()
    assertCredentials("a", app: app)
    XCTAssertFalse(app.textFields["身份验证器验证码"].exists)
    let password = app.secureTextFields["密码"]
    password.tap()
    password.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 9) + "wrong")
    app.buttons["登录"].tap()
    XCTAssertTrue(app.staticTexts["用户名、密码或验证码不正确。"].waitForExistence(timeout: 10))
    app.buttons["更改地址"].tap()
    selectSaved(0, app: app)
    assertCredentials("a", app: app)
    app.switches["native-remember-credentials"].tap()
    app.buttons["更改地址"].tap()
    selectSaved(0, app: app)
    assertNoCredentials(app)
    // 密码记忆独立于会话记忆：不保持登录时，重启仍可回填，但必须再次点击登录。
    enterCredentials("a", app: app)
    app.switches["保持登录"].tap()
    try await configure(0, mode: "ready")
    app.buttons["登录"].tap()
    assertHome(app)
    app.terminate()
    app.launch()
    assertCredentials("a", app: app)
    // 再次保持登录后删除，同时验证令牌与密码均被清除。
    app.buttons["登录"].tap()
    assertHome(app)
    openPicker(app)
    revealDelete(0, app: app).tap()
    app.alerts.buttons["取消"].tap()
    XCTAssertTrue(saved(0, app: app).exists)
    revealDelete(0, app: app).tap()
    app.alerts.buttons["删除"].tap()
    let removed = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: saved(0, app: app))
    XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 15), .completed)
    connect(0, app: app)
    assertNoCredentials(app)
    capture("多服务-删除后重新连接")
    app.terminate()
  }

  /// 最大辅助功能字号和横屏下，完整地址和左滑操作仍可通过系统列表滚动访问。
  func testSavedServicesRemainUsableWithLargeText() async throws {
    try await configure(0, mode: "expired")
    try await configure(1, mode: "expired")
    let app = try launchCleanPicker()
    connect(0, app: app)
    app.buttons["更改地址"].tap()
    connect(1, app: app)
    app.buttons["更改地址"].tap()
    app.terminate()
    app.launchArguments += [
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ]
    app.launch()
    XCTAssertTrue(app.staticTexts["已保存的服务"].waitForExistence(timeout: 10))
    XCUIDevice.shared.orientation = .landscapeLeft
    defer { XCUIDevice.shared.orientation = .portrait }
    let rotated = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed)
    let row = saved(0, app: app)
    for _ in 0..<5 where !row.isHittable { app.tables["server-connections"].swipeUp() }
    XCTAssertTrue(row.isHittable)
    capture("多服务-横屏最大字号")
    selectSaved(0, app: app)
    XCTAssertTrue(app.textFields["用户名"].waitForExistence(timeout: 15))
    app.terminate()
  }

  /// 只在显式启用专用回环夹具时运行，通过真实左滑手势清理这两个测试服务。
  private func launchCleanPicker() throws -> XCUIApplication {
    guard ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_SERVER_PROFILES"] == "1" else {
      throw XCTSkip("需要两个独立的本机多服务回归夹具。")
    }
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    let app = XCUIApplication()
    app.launchArguments = ["-moviepilot.instance.selected.v1", ""] + language
    app.launch()
    XCTAssertTrue(app.textFields["MoviePilot 服务地址"].waitForExistence(timeout: 10))
    for index in servers.indices {
      let row = saved(index, app: app)
      if row.exists {
        revealDelete(index, app: app).tap()
        app.alerts.buttons["删除"].tap()
        let removed = XCTNSPredicateExpectation(
          predicate: NSPredicate(format: "exists == false"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 15), .completed)
      }
    }
    return app
  }

  /// 手动新增服务只使用真实 URL 输入，首次连接不得继承另一服务账号。
  private func connect(_ index: Int, app: XCUIApplication) {
    let field = app.textFields["MoviePilot 服务地址"]
    field.tap()
    let clear = field.buttons.firstMatch
    if clear.exists { clear.tap() }
    field.typeText(servers[index] + "\n")
    XCTAssertTrue(app.textFields["用户名"].waitForExistence(timeout: 15))
  }

  /// 登录后从产品菜单进入服务列表，覆盖用户实际发现和切换的入口。
  private func openPicker(_ app: XCUIApplication) {
    app.buttons["操作菜单"].tap()
    app.buttons["连接与显示"].tap()
    app.buttons["切换服务"].tap()
    XCTAssertTrue(app.staticTexts["已保存的服务"].waitForExistence(timeout: 10))
  }

  /// 唯一标准地址也是可访问性标识，列表选择无需重填 URL。
  private func saved(_ index: Int, app: XCUIApplication) -> XCUIElement {
    app.cells["saved-service-\(servers[index])"]
  }

  /// 列表平时没有常驻删除按钮，向左滑动后才出现系统删除动作。
  private func revealDelete(_ index: Int, app: XCUIApplication) -> XCUIElement {
    let row = saved(index, app: app)
    XCTAssertTrue(row.waitForExistence(timeout: 10))
    row.swipeLeft()
    let remove = app.buttons["删除"]
    XCTAssertTrue(remove.waitForExistence(timeout: 5))
    return remove
  }

  /// 直接点选已保存服务，后续由其独立令牌或登录表单接续。
  private func selectSaved(_ index: Int, app: XCUIApplication) {
    let button = saved(index, app: app)
    XCTAssertTrue(button.waitForExistence(timeout: 10))
    button.tap()
  }

  /// 合成账号首次由用户主动开启密码记忆，测试不依赖默认自动保存。
  private func enterCredentials(_ profile: String, app: XCUIApplication) {
    app.textFields["用户名"].tap()
    app.textFields["用户名"].typeText("server-\(profile)")
    app.secureTextFields["密码"].tap()
    app.secureTextFields["密码"].typeText("fixture-\(profile)")
    app.switches["native-remember-credentials"].tap()
  }

  /// 普通密码认证必须真正完成网页接管，并且没有钥匙串保存失败提示。
  private func authenticate(_ profile: String, app: XCUIApplication) {
    enterCredentials(profile, app: app)
    app.buttons["登录"].tap()
    assertHome(app)
  }

  /// 原生导航证明前端已使用当前认证结果完成接管。
  private func assertHome(_ app: XCUIApplication) {
    XCTAssertTrue(app.tabBars["native-root-navigation"].waitForExistence(timeout: 45))
    XCTAssertFalse(app.alerts["已登录"].exists)
  }

  /// 仅合成密码可临时显示来检查确切回填值，截图前立即恢复安全输入。
  private func assertCredentials(_ profile: String, app: XCUIApplication) {
    XCTAssertTrue(app.textFields["用户名"].waitForExistence(timeout: 15))
    XCTAssertEqual(app.textFields["用户名"].value as? String, "server-\(profile)")
    XCTAssertEqual(app.switches["native-remember-credentials"].value as? String, "1")
    app.buttons["显示密码"].tap()
    XCTAssertEqual(app.textFields["密码"].value as? String, "fixture-\(profile)")
    app.buttons["隐藏密码"].tap()
  }

  /// 删除或未成功认证的服务应回到空表单，不残留账号、密码或验证码。
  private func assertNoCredentials(_ app: XCUIApplication) {
    XCTAssertTrue(app.textFields["用户名"].waitForExistence(timeout: 15))
    XCTAssertEqual(app.textFields["用户名"].value as? String, "用户名")
    XCTAssertEqual(app.secureTextFields["密码"].value as? String, "密码")
    XCTAssertEqual(app.switches["native-remember-credentials"].value as? String, "0")
    XCTAssertFalse(app.textFields["身份验证器验证码"].exists)
  }

  /// 两个服务各自配置失效及 OTP 场景，只向固定回环端点写入合成控制状态。
  private func configure(_ index: Int, mode: String, reset: Bool = false) async throws {
    guard ProcessInfo.processInfo.environment["MOVIEPILOT_E2E_SERVER_PROFILES"] == "1" else {
      throw XCTSkip("需要显式启动两个本机夹具。")
    }
    var request = URLRequest(url: URL(string: servers[index] + "__service/config")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: ["mode": mode, "reset": reset])
    let (_, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
  }

  /// 只读请求计数用于证明恢复和账号回填没有自动重发密码。
  private func stats(_ index: Int) async throws -> [String: Int] {
    let (data, _) = try await URLSession.shared.data(
      from: URL(string: servers[index] + "__service/stats")!)
    return try JSONDecoder().decode([String: Int].self, from: data)
  }

  /// 截图只包含合成地址与账号，密码始终处于系统安全输入状态。
  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
