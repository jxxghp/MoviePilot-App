# P7.2 系统集成原生解耦（推送通知、桌面小组件、外部深链与主屏幕快捷项）验收记录

- 日期：2026-11-21
- 分支：`v2`
- 目标范围：将 APNs 系统推送通知、桌面小组件（WidgetKit 只读授权/续期/改名/刷新/撤销）、自定义深链（`moviepilot-app://notification`、`moviepilot://widget`）与主屏幕快捷方式（`HomeShortcut`）全面脱离旧 `WebCoordinator`，直连 `NativeSession` 与 `NativeSystemRouteHub`。

## 核心交付

1. **原生系统路由中枢（`NativeSystemRouteHub.swift`）**：
   - 白名单映射内部通知路径、小组件 `WidgetContent` 与主屏幕 `HomeShortcut`（搜索 / 通知 / 插件）至原生 4+1 标签及工作台页面，绝不执行任意 URL 或写操作。
   - 保持 `PendingHomeShortcut` 5 分钟有效期与实例绑定，并在切实例或退出登录时立即清空，杜绝跨实例重放。
   - 跨账号/权限不匹配时仅展示顶部可关闭提示横幅，绝不自动切换账号或泄露凭据。
2. **推送通知原生直连（`NotificationService.swift` + `NativeNotificationSettingsSheet`）**：
   - 新增 `attachNative(_ session: NativeSession?)` 与 `nativeRequest(session:action:extra:)`，直接调用 `POST /api/v1/notification/app` 完成状态核验、APNs 令牌绑定、测试推送与解除绑定。
   - 「设置 -> 使用偏好与目录 / 系统集成」提供原生「系统推送通知」设置页。
3. **桌面小组件原生直连（`WidgetService.swift` + `NativeWidgetSettingsSheet`）**：
   - 新增基于 `NativeSession` 的 `settings(native:)`、`reconcile(native:)`、`enable(native:name:)`、`rename(native:profile:name:)`、`refresh(native:profile:)`、`disable(native:)` 与 `resumePending(native:)`，直连 `/api/v1/widget/context` 与 `/api/v1/widget/registrations` 并复用 `MoviePilotCore.WidgetBridgeResponse` 严格白名单与长度校验。
   - 注销、登录过期与忘记实例时立即清理本机共享仓资料并尝试撤销服务端只读凭据，随后刷新 `WidgetCenter.shared.reloadAllTimelines()`。
   - 「设置 -> 使用偏好与目录 / 系统集成」提供原生「桌面小组件」设置页。
4. **场景入口与生命周期接线（`NativeV2SceneDelegate.swift` + `SceneDelegate.swift` + `NativeAppModel.swift` + `NativeV2MainShell.swift`）**：
   - 冷启动与热启动统一承接 `urlContexts` 与 `shortcutItem`，前台恢复自动触发 `resumeSystemIntegrations()`。
   - `NativeV2MainShell` 订阅 `NativeSystemRouteHub.shared` 并在权限门禁校验后完成一次性路由消费。

## 验证结果

- `xcodegen generate` 与 `xcrun swift-format lint --strict` 全部 0 警告。
- SwiftPM 单元测试：35/35 通过。
- iPhone 17 合成端到端 UI 测试：`testNativeFourPlusOneNavOverflowDynamicActionAndSettingsHub`（覆盖原生系统推送弹窗、桌面小组件弹窗、4+1 导航、站点范围、用户管理、刮削与网络诊断，`webViews.count == 0`，`unexpected == [:]`）通过。
