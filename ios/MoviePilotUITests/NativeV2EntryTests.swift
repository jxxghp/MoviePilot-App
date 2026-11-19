import XCTest

/// API-only 服务通过真实按钮验收原生入口，不启动前端或借用网页登录结果。
@MainActor
final class NativeV2EntryTests: XCTestCase {
  private let base = "http://127.0.0.1:5330/"
  private let arguments = ["--native-v2", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]

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
    XCTAssertFalse(app.buttons["native-v2-retry"].exists)
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
    XCUIDevice.shared.orientation = .portrait
    let app = XCUIApplication()
    app.launchArguments = arguments + ["-moviepilot.instance.selected.v1", ""] + extra
    app.launch()
    XCTAssertTrue(app.textFields["native-v2-address"].waitForExistence(timeout: 15))
    for name in ["a", "b", "new", "slow"] {
      let row = app.buttons["native-v2-saved-\(base)\(name)/"]
      if row.exists {
        for _ in 0..<8 where !row.isHittable { app.swipeUp() }
        row.swipeLeft()
        app.buttons["删除"].tap()
        app.alerts.buttons["删除"].tap()
        let gone = XCTNSPredicateExpectation(
          predicate: NSPredicate(format: "exists == false"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 15), .completed)
      }
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

  /// Form 会延迟创建屏幕外的行，大字号下先滚动再验证元素存在。
  private func reveal(_ element: XCUIElement, app: XCUIApplication) {
    _ = element.waitForExistence(timeout: 2)
    let scroll = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app
    for _ in 0..<8 where !element.exists || !element.isHittable { scroll.swipeUp() }
    if !element.isHittable {
      for _ in 0..<8 where !element.exists || !element.isHittable { scroll.swipeDown() }
    }
    if !element.exists || !element.isHittable {
      capture("native-v2-unreachable-control")
      let details = XCTAttachment(string: app.debugDescription)
      details.name = "native-v2-unreachable-hierarchy"
      details.lifetime = .keepAlways
      add(details)
    }
    XCTAssertTrue(element.exists)
    XCTAssertTrue(element.isHittable)
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
    let account = app.descendants(matching: .any)["native-v2-account"].firstMatch
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
