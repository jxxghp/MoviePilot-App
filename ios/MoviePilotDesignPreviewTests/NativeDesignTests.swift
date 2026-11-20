import UIKit
import XCTest

/// 独立预览的真实原生交互与截图；不依赖账号、后端、网页或主 App 的测试状态。
@MainActor
final class NativeDesignTests: XCTestCase {
  /// 首页海报、原生详情、搜索弹层与内存队列形成可操作的设计闭环。
  func testDiscoveryDetailAndQueue() {
    let app = launch()
    let hero = app.buttons["preview-hero-detail"]
    require(hero, app: app, timeout: 10)
    capture("cinematic-native-discover")
    hero.tap()
    XCTAssertTrue(app.buttons["preview-search-resources"].waitForExistence(timeout: 5))
    capture("cinematic-native-detail")
    reveal(app.buttons["preview-search-resources"], app: app)
    app.buttons["preview-search-resources"].tap()
    let queue = app.buttons["preview-queue-action"]
    XCTAssertTrue(queue.waitForExistence(timeout: 5))
    reveal(queue, app: app)
    queue.tap()
    XCTAssertFalse(queue.isEnabled)
    XCTAssertTrue(app.staticTexts["已添加到队列"].exists)
    XCTAssertEqual(app.webViews.count, 0)
    app.terminate()
  }

  /// 工作台的原生图表与统计卡在同一渐变背景下可读。
  func testDashboard() {
    let app = launch(screen: "dashboard")
    XCTAssertTrue(app.staticTexts["下载速率"].waitForExistence(timeout: 10))
    capture("cinematic-native-dashboard")
    XCTAssertEqual(app.webViews.count, 0)
    app.terminate()
  }

  /// 设备旋转后检查真实窗口尺寸与内容可达性，不用裁剪竖屏图冒充横屏布局。
  func testRotatedLayout() {
    let app = launch(screen: "dashboard")
    XCUIDevice.shared.orientation = .landscapeLeft
    require(app.staticTexts["下载速率"], app: app)
    XCTAssertGreaterThan(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height)
    capture("cinematic-native-landscape-initial")
    reveal(app.staticTexts["存储空间"], app: app)
    capture("cinematic-native-landscape")
    app.terminate()
    XCUIDevice.shared.orientation = .portrait
  }

  /// 设置与插件表单的开关和保存真实绑定状态，视觉不靠静态图片代替。
  func testSettingsAndPluginForm() {
    let app = launch(screen: "settings")
    XCTAssertTrue(app.buttons["preview-plugin-form"].waitForExistence(timeout: 10))
    capture("cinematic-native-settings")
    reveal(app.buttons["preview-plugin-form"], app: app)
    app.buttons["preview-plugin-form"].tap()
    let row = app.switches["preview-plugin-enabled"]
    require(row, app: app)
    capture("cinematic-native-plugin-form")
    let control = row.switches.firstMatch
    if control.exists { control.tap() } else { row.tap() }
    XCTAssertEqual(row.value as? String, "0")
    let save = app.buttons["preview-plugin-save"]
    reveal(save, app: app)
    save.tap()
    XCTAssertTrue(app.alerts["配置已保存"].waitForExistence(timeout: 5))
    app.alerts.buttons["好"].tap()
    XCTAssertEqual(app.webViews.count, 0)
    app.terminate()
  }

  /// 订阅海报与网格原生呈现；详情添加/取消仍可通过导航返回。
  func testSubscriptions() {
    let app = launch(screen: "subscriptions")
    let poster = app.buttons["preview-poster-rings"]
    XCTAssertTrue(poster.waitForExistence(timeout: 10))
    capture("cinematic-native-subscriptions")
    poster.tap()
    XCTAssertTrue(app.buttons["取消订阅"].waitForExistence(timeout: 5))
    app.buttons["取消订阅"].tap()
    XCTAssertTrue(app.buttons["添加订阅"].exists)
    app.terminate()
  }

  /// 通过发现页的真实分区入口进入九张海报网格，检查完整三列密度与点击区域。
  func testAiringPosterGrid() {
    let app = launch()
    let section = app.buttons["preview-section-正在播出"]
    reveal(section, app: app)
    section.tap()
    let firstPoster = app.buttons["preview-poster-rings"]
    XCTAssertTrue(firstPoster.waitForExistence(timeout: 5))
    capture("cinematic-native-poster-grid")
    firstPoster.tap()
    XCTAssertTrue(app.buttons["preview-search-resources"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.webViews.count, 0)
    app.terminate()
  }

  /// 系统浅色设置不能切换固定 Cinematic 风格，大字号仍可滚动到配置与保存。
  func testSingleStyleAndLargeText() {
    let app = launch(
      screen: "settings",
      extra: [
        "-AppleInterfaceStyle", "Light", "-UIPreferredContentSizeCategoryName",
        "UICTContentSizeCategoryAccessibilityXXXL",
      ])
    let form = app.buttons["preview-plugin-form"]
    reveal(form, app: app)
    form.tap()
    let save = app.buttons["preview-plugin-save"]
    reveal(save, app: app)
    capture("cinematic-native-large-text")
    save.tap()
    XCTAssertTrue(app.alerts["配置已保存"].waitForExistence(timeout: 5))
    app.terminate()
  }

  /// 冷启动只改变预览初始页，不注入真实实例或认证数据。
  private func launch(screen: String = "discover", extra: [String] = []) -> XCUIApplication {
    continueAfterFailure = false
    print(
      "NativePreview system accessibility: reduceTransparency=\(UIAccessibility.isReduceTransparencyEnabled), reduceMotion=\(UIAccessibility.isReduceMotionEnabled)"
    )
    XCUIDevice.shared.orientation = .portrait
    let app = XCUIApplication(bundleIdentifier: "com.moviepilot.app.v2preview")
    app.launchArguments =
      ["--screen", screen, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + extra
    app.launch()
    return app
  }

  /// 沿滚动容器内容边缘定向拖动，避免图表居中手势或横屏快捷 swipe 的坐标歧义。
  private func reveal(_ element: XCUIElement, app: XCUIApplication) {
    let scroll = app.scrollViews.firstMatch
    let upper = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.14, dy: 0.25))
    let lower = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.14, dy: 0.80))
    for _ in 0..<10 where !element.exists || !element.isHittable {
      lower.press(forDuration: 0.05, thenDragTo: upper)
    }
    if !element.isHittable {
      for _ in 0..<10 where !element.exists || !element.isHittable {
        upper.press(forDuration: 0.05, thenDragTo: lower)
      }
    }
    if !element.exists || !element.isHittable {
      capture("cinematic-native-scroll-failure")
      let hierarchy = XCTAttachment(string: app.debugDescription)
      hierarchy.name = "cinematic-native-scroll-hierarchy"
      hierarchy.lifetime = .keepAlways
      add(hierarchy)
    }
    XCTAssertTrue(element.exists)
    XCTAssertTrue(element.isHittable)
  }

  /// 等待失败时保留实际窗口和可访问性树，且继续保留原断言的位置与失败结果。
  private func require(
    _ element: XCUIElement, app: XCUIApplication, timeout: TimeInterval = 5,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let exists = element.waitForExistence(timeout: timeout)
    if !exists {
      capture("cinematic-native-failure")
      let hierarchy = XCTAttachment(string: app.debugDescription)
      hierarchy.name = "cinematic-native-failure-hierarchy"
      hierarchy.lifetime = .keepAlways
      add(hierarchy)
    }
    XCTAssertTrue(exists, file: file, line: line)
  }

  /// 系统截图仅捕获原生预览内容，状态栏和导航不做后期拼接。
  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
