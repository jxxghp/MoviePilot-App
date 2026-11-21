# P8 默认切流原生入口、清理旧主流程 WebKit、捷径诊断与登录重设计验收记录

- 日期：2026-11-21
- 分支：`v2`
- 目标范围：默认入口切流为原生 SwiftUI v2、彻底移除旧 1.x 主流程 WebView/UIKit 桥接、新增设置页捷径与诊断工具集（系统检查、网络测试、名称识别与过滤规则测试、实时日志、定时服务）、重设计连接服务与登录页视觉、完成 Debug/Release 双构建与 iPhone/iPad 无参数默认启动全矩阵回归。

## 核心交付

1. **默认切流原生 v2 与清理旧主流程 WebKit**
   - `SceneDelegate.swift` 在 Debug 与 Release 构建中均直接初始化并托管 `NativeV2SceneDelegate`，移除 `--native-v2` 启动开关与 `LegacyWebSceneDelegate`。
   - 彻底移除 21 个旧 1.x 主流程 WebView/UIKit 桥接文件（`WebCoordinator.swift`、`LegacyWebSceneDelegate.swift`、`ShellController.swift`、`WebContentController.swift` 等）及 4 个旧网页壳 UI 测试文件。
   - `NotificationService.swift`、`WidgetService.swift` 彻底清除遗留 `WebCoordinator` 分支；`AccountAppearance.swift` 收口为极简 1.x 外观清理辅助。
   - 全仓 `import WebKit` 核查：仅保留 `PluginWeb/LegacyWebsiteStorage.swift`（忘记旧实例清理残留存储）与 `NativeV2/Pages/NativePluginDataPageView.swift`（严格受控的 `render_mode == "vue"` 插件兼容隔离容器）。
2. **原生捷径与诊断工具集（`NativeDiagnosticsToolsPage.swift` + `NativeSettingsHubPage.swift`）**
   - 新增「设置 -> 捷径与诊断」4 列瓷砖与 2×2 横向「常用配置」胶囊卡，补齐：
     - **系统检查**（`GET /api/v1/system/modulelist` + 逐项 `GET /api/v1/system/moduletest/{id}`）
     - **网络测试**（`GET /api/v1/system/nettest/targets` + `GET /api/v1/system/nettest`）
     - **识别与规则测试**（`GET /api/v1/media/recognize` + `GET /api/v1/system/ruletest` + 规则组选择）
     - **实时日志**（`APIClient` 新增严格 `.plainText` MIME 契约，直连 `GET /api/v1/system/logging`，支持级别筛选、关键字过滤、着色与实时跟随）
     - **定时服务**（`GET /api/v1/dashboard/schedule` + `GET /api/v1/system/runscheduler` 一键触发）
3. **连接服务与登录页视觉重设计（`NativeV2RootView.swift`）**
   - 居中 `76×76` 品牌图标与紫玫瑰径向微光光晕；登录态展示居中「已连接服务」透色状态胶囊并支持一键切换。
   - 去除表单内重复小节标题；主操作升级为与全站一致的高对比度白色主胶囊按钮；地址输入补充 `https://` / `http://` 快捷前缀；已保存服务升级为带图标徽标、粗体主机名与完整地址的玻璃卡片；登录开关统一为紫丁香主题色。

## 验证结果

- 静态检查：`xcrun swift-format lint --strict` 0 警告；全仓禁用词与凭据扫描 0 命中；`import WebKit` 仅余 2 处合规隔离点。
- 单元测试：SwiftPM 35/35 通过；Python 27/27 通过。
- 构建验证：`xcodebuild build-for-testing`（Debug）与 `xcodebuild build`（Release，无签名模拟器通用目标）均通过。
- iPhone 17 默认无参数启动合成 UI 回归（10/10 全部通过，零 WebView，`unexpected == [:]`）：
  - `testStableSceneRoutingAndNativeLanguages`（验证无 `--native-v2` 参数冷启动默认进入原生 v2 与三语即时切换）
  - `testSeparateInstancesRestorationAndExplicitPasswordMemory`（含新版连接/已保存服务/登录页逐图视觉核验）
  - `testCinematicFormControlsAndSecretConcealment`（含首次初始化页、秘密遮盖与 44pt 触控区）
  - `testUnavailableRetryCancellationAndLargeText`（超大辅助字体与离线取消重试）
  - `testNativeFourPlusOneNavOverflowDynamicActionAndSettingsHub`（4+1 导航、极简弹出菜单、多样化设置中心、站点范围、推送/小组件弹窗）
  - `testNativeDiagnosticsAndShortcutsTools`（系统检查、名称识别、实时日志）
  - `testNativeMediaDetailSubscribesAndNavigatesToPerson`
  - `testNativeHistorySitesAndMessagesFlows`
  - `testNativePluginDataPageChartsAndVueCompatGate`
  - `testNativeWorkflowCanvasEditSaveAndCommunityFork`
- iPad Pro 11-inch (M5) 默认无参数启动回归：`testStableSceneRoutingAndNativeLanguages`、`testNativeDiagnosticsAndShortcutsTools` 全部通过。
- 临时缓存清理：`~/Library/Caches/MoviePilotSimulator/` 与 `/Volumes/DISK/TmpBuild/` 下全部任务临时目录已清理。
