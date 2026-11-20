# P2.3 / P2.4 原生插件 JSON 数据页、仪表板组件与受控兼容容器验收记录

- 日期：2026-11-21
- 仓库与分支：`MoviePilot-App` / `v2`
- 范围：
  1. `NativePluginDataPageView` / `NativePluginJSONRenderer` / `NativePluginApexChartView`（`ios/MoviePilot/NativeV2/Pages/NativePluginDataPageView.swift`）：直连 `GET /api/v1/plugin/page/{id}`，有界递归解析（最大深度 24、最大节点 1500）并原生渲染 Vuetify JSON 树（`VRow`/`VCol`/`VCard`/`VCardTitle`/`VCardSubtitle`/`VCardText`/`VAlert`/`VChip`/`VTable`/`VList`/`VListItem`/`VProgressLinear`/`VImg`/`VAvatar`/`VApexChart`/`VBtn` 等），安全跳过 `style`/`script`；对 `VApexChart` 使用纯 SwiftUI 多段环形图（Pie/Donut）与横向柱状图实现零 WebView 原生图表渲染。
  2. 受控兼容容器门禁（`NativePluginCompatSheet` / `NativePluginCompatWebView`）：仅在插件明确返回 `render_mode == "vue"` 且用户显式点击「在受控兼容容器中打开」按钮（`native-plugin-open-compat`）时才创建非持久化、同源锁死的 `WKWebView`；默认页面浏览保持零 WebView。
  3. 插件管理页接入（`NativePluginMarketPage.swift`）：解码 `has_page`，在「已安装管理」列表为含数据页插件展示「数据页」入口（`native-installed-page-{id}`）。
  4. 原生仪表板插件扩展卡片（`NativeDashboardPage.swift`）：并发直读 `GET /api/v1/plugin/dashboard/meta` 与 `GET /api/v1/plugin/dashboard/{id}[/{key}]`，在后台服务区下方原生渲染插件扩展图表/卡片，失败时静默降级不阻塞核心仪表盘分区。

## 自动化验证

1. 工程生成与严格格式检查：
   - `xcodegen generate --spec ios/project.yml --project ios`：通过。
   - `xcrun swift-format lint --strict` 覆盖全部新增与修改 Swift 文件：0 告警。
2. 脚本与夹具单测：
   - `python3 -m unittest discover -s scripts/tests`：27/27 通过。
3. iPhone 17 与 iPad Pro 11-inch (M5) API-only 合成 UI 验收（回环端口 5330）：
   - `testNativePluginDataPageChartsAndVueCompatGate`：验证仪表板 `DemoPlugin` 原生插件图表卡片、`DemoPlugin` 数据页原生图表/表格/提示渲染（`webViews.count == 0`）、`VueCompatDemo` 受控兼容容器显式入口门禁（未点击前 `webViews.count == 0`），且 `unexpected == [:]`。
   - `testNativeDashboardRetainsStatisticsDuringPartialFailure` 与 `testNativePluginMarketInstallResetAndUninstall` 回归零失败。
   - iPhone 17（3 项）与 iPad Pro 11-inch (M5)（2 项）均 0 失败、0 跳过。
4. 本地 `http://127.0.0.1:3001/` 真实后端只读实测与逐图核查（39 张全屏实测截图，`passedTests: 1, failedTests: 0, skippedTests: 0`）：
   - `native-v2-live-plugin-installed.png`：已安装插件列表清晰展示「猫眼榜单订阅」「站点数据统计」「站点健康守卫」的「数据页」紫玫瑰玻璃按钮。
   - `native-v2-live-plugin-page-statistic.png`：「站点数据统计」纯原生渲染总上传/下载/做种概览卡及多段环形增量图表与图例数值，零 WebView。
   - `native-v2-live-plugin-page-maoyan.png`：「猫眼榜单订阅」纯原生渲染订阅统计卡、剧集海报横幅、类型/来源胶囊与订阅时间。
   - `native-v2-live-dashboard-plugins.png`：原生仪表板「后台服务」下方展示「插件扩展面板（1 项）· 站点数据统计」真实多段环形图，零 WebView。

## 已知边界与后续叶子

- 通用插件复杂自定义事件槽位、多 `navKey` 侧栏 AppPage 路由与插件 SDK 完整桥接继续留在后续专项深化；下一步推进 **P5.5 原生工作流节点画布与参数编辑**（含社区工作流分享浏览与复用，纯原生零 WebView）。
