# 2026-11-21 原生插件市场与插件生命周期管理验收记录（P7.1）

## 范围与实现

- 新增 [NativePluginMarketPage.swift](../../../ios/MoviePilot/NativeV2/Pages/NativePluginMarketPage.swift)：
  - 仅超级管理员可见，提供「插件市场」（`GET /api/v1/plugin/?state=market&page={page}&count=60` 自动分页，避免一次传输 559 项 1.57 MB 阻塞首屏）与「已安装管理」（`GET /api/v1/plugin/?state=installed`）双视图。
  - 市场支持 `全部 / 可更新 / 未安装` 状态筛选、名称/作者/标签搜索及二次确认安装或更新（`GET /api/v1/plugin/install/{id}`）。
  - 已安装管理支持直达现有原生 JSON 配置表单（`NativePluginFormView`）、二次确认重置（`GET /api/v1/plugin/reset/{id}`）与二次确认卸载（`DELETE /api/v1/plugin/{id}`）。
- 更新 [NativePluginCatalogView.swift](../../../ios/MoviePilot/NativeV2/NativePluginCatalogView.swift) 与 [NativeV2MainShell.swift](../../../ios/MoviePilot/NativeV2/NativeV2MainShell.swift)：
  - 保留既有插件配置清单全部行为与标识，同时在顶栏与「我的 -> 系统管理」同步提供「插件市场」原生入口。

## 验证结果

1. **静态与格式校验**
   - `xcodegen generate --spec ios/project.yml` 通过。
   - `xcrun swift-format lint --strict` 0 告警通过。
   - 全仓禁用命名（整词及驼峰）扫描：0 匹配。
   - `python3 -m unittest discover -s scripts/tests`：27 项全部通过。
2. **API-only 合成夹具双端 UI 回归（零 WebView）**
   - iPhone 17 (`56286E2B-6AC1-4087-9936-F9DDA70D9E0A`)：`testNativePluginMarketInstallResetAndUninstall` 通过（72.6s，0 失败，0 跳过；验证 `GET /api/v1/plugin/install/AutoSignIn == 1`、`GET /api/v1/plugin/reset/DemoPlugin == 1`、`DELETE /api/v1/plugin/DemoPlugin == 1`、`webViews.count == 0`、`unexpected == [:]`）。
   - iPad Pro 11-inch (M5) (`26D71997-F654-4AE6-8D8E-BFDB7CC0E766`)：`testNativePluginMarketInstallResetAndUninstall` 通过（86.8s，0 失败，0 跳过）。
3. **本机 `3001` 真实后端只读逐图验收**
   - `scripts/native-v2-live.py` 针对 `http://127.0.0.1:3001/` 全程只读执行通过（`passedTests: 1`, `failedTests: 0`, `skippedTests: 0`）。
   - 逐图核验 `native-v2-live-plugin-market.png` 与 `native-v2-live-plugin-installed.png`：
     - `插件市场` 准确解包标准 `{success, data}` 响应并分页渲染真实市场卡片（`简单观影日历 v0.1.5`、`媒体下载目录 v1.0.0`、`Tracker 替换 v2.0`、`种子黑名单 v1.0.0` 等）及作者、标签与安装按钮。
     - `已安装管理` 准确渲染本机 9 个真实已安装插件（`媒体库服务器刷新 v1.3.3`、`猫眼榜单订阅 v4.1.4`、`站点数据统计 v1.9.7`、`站点健康守卫 v1.0.2` 等）及运行状态、配置/重置/卸载入口。

## 保留范围

- 插件克隆分身/来源绑定切换、插件 JSON 数据页/仪表板（P2.3）及受控 Web 兼容容器（P2.4/P2.5）继续归入对应后续叶子。
