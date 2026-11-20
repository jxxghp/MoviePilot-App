# P3a 原生媒体主壳层、发现页、仪表盘与媒体搜索验收证据

- 日期：2026-11-20
- 分支：`MoviePilot-App` / `v2`
- 目标范围：以单一深色渐变玻璃风格（Cinematic 视觉体系）落地原生根级 `TabView` 主壳层，接通真实 MoviePilot 发现、推荐、媒体服务器继续观看/最新入库/媒体库、海报网格自动翻页、基础媒体详情、仪表盘与媒体搜索，并在全仓清除外部产品名称引用以规避法律风险。

## 主要实现面

1. **网络与会话安全边界（`Sources/MoviePilotAPI`、`Sources/MoviePilotSession`）**
   - `APIClient` 支持同源受控图片代理 `requestImage(_:maximumWidth:)`，使用短效资源 Cookie（`MoviePilot` HttpOnly JWT），绝不将主 Bearer Token 透传给外部图片源。
   - 隔离独立 `imageSession` 与 JSON API `session`，避免大量海报加载阻塞业务接口（如分页翻页与详情加载）。
   - `NativeMediaArtwork` 在同源代理前剥离媒体服务器 URL 的前端签名 `#fragment`，并按目标宽度将 TMDB `/t/p/original/` 映射至 `/t/p/w500/`、`/t/p/w780/` 或 `/t/p/w1280/`；列表与网格统一 `420px` 内存缓存键以秒开复现海报。
2. **原生主导航与四大入口（`ios/MoviePilot/NativeV2/`）**
   - `NativeV2RootView` / `NativeV2MainShell`：认证后以系统原生 `TabView` 作为根容器（iOS 26+ 自动获得原生浮动 Liquid Glass 标签栏与独立搜索球），每个标签持有独立 `NavigationStack`，发现栏与搜索均采用原生推入导航与原生圆形 Liquid Glass 返回按钮。
   - `NativeDiscoverPage`：67% 视口高度多条推荐轮播主视觉（`TabView(.page)` + 指示点），经 `onScrollGeometryChange` 驱动 4 段连续滚动退场（7% 视差、0→18pt 渐进柔焦、多段 alpha 溶解、近黑 `#0A0A16` 至烟灰紫背景渐变、顶部状态栏软渐隐遮罩）；边缘出画横向海报栏、`继续观看` 进度横卡、`本周趋势` 16:9 横卡、`最新入库` 与 `媒体库` 分区，使用 `LazyVStack` 按需加载。
   - `NativeDiscoverRailGrid`：三列居中海报网格，滚动触底自动翻页并保留已浏览位置，仅在失败时显式展示重试按钮。
   - `NativeDashboardPage`：全屏连续紫玫瑰渐变底色、原生工具栏 Liquid Glass 刷新按钮、2×2 媒体库统计玻璃卡（带当月增量胶囊）、环形存储空间与后台服务列表。
   - `NativeMediaSearchPage`：单行 5 枚半透明细边筛选胶囊（影视/人物/音乐/合集/来源）、人物圆形头像横向栏与玻璃结果卡。
3. **合规清理**
   - 清理全仓源码、测试、脚本与文档中的外部第三方产品名称引用，并在 `AGENTS.md` 固化命名禁令。

## 验证记录

### 1. 单元、脚本与静态检查
- `swift test --scratch-path /Volumes/DISK/TmpBuild/mp-v2-check/swiftpm`：全部通过（含 `MoviePilotAPITests`、`MoviePilotSessionTests`、`MoviePilotCoreTests`、`MoviePilotPluginUITests`、`MoviePilotPluginFormsTests`）。
- `python3 -m unittest discover -s scripts/tests`：26/26 通过。
- `node --test scripts/tests/*.test.mjs`：3/3 通过。
- `xcrun swift-format lint --strict`：0 警告、0 错误。
- 全仓文本敏感命名扫描：0 处匹配。

### 2. API-only 合成夹具 UI 验收（`scripts/native-v2-fixture.py`，WebView 数 = 0）
- **iPhone 17（5/5 通过，0 跳过）**：
  - `testNativeBusinessHidesUnpermittedEntries`（31.79s）
  - `testNativeDashboardRetainsStatisticsDuringPartialFailure`（35.54s）
  - `testNativeDiscoverLoadsArtworkAndPaginatedDetail`（46.10s）
  - `testNativeDiscoverRetainsAvailableRailsAndRetriesPartialFailure`（37.65s）
  - `testNativeMediaSearchOnlySubmitsOnActionAndRetries`（50.85s）
- **iPad Pro 11-inch (M5)（2/2 通过，0 跳过）**：
  - `testNativeDashboardRetainsStatisticsDuringPartialFailure`（41.14s）
  - `testNativeDiscoverLoadsArtworkAndPaginatedDetail`（47.36s）

### 3. 本机真实后端只读验收（`http://127.0.0.1:3001/`，凭据仅驻内存并即时销毁）
- `scripts/native-v2-live.py`：`{"result": "Passed", "passedTests": 1, "failedTests": 0, "skippedTests": 0, "backend": "http://127.0.0.1:3001/"}`。
- 逐张视觉复核全部 10 张实时截图（`discover-phase-1..4`、`grid-before-pagination`、`grid-pagination-state`、`grid-automatic-page`、`detail`、`dashboard`、`search`）：
  - 确认 4 段滚动柔焦渐隐、顶部状态栏软遮罩、Emby 真实「继续观看」缩略图与进度条、TMDB 真实海报与 16:9 趋势横图、自动翻页加载、全宽详情头图、紫玫瑰透色仪表盘与单行筛选搜索页全部符合视觉标准，且 `webViews.count == 0`。

## 未覆盖与后续叶子

- 本叶子只覆盖媒体主壳层、只读发现/翻页网格、基础媒体详情、仪表盘基础统计与媒体搜索；不包含详情页订阅/搜索资源/播放动作、季集/演职员/人物页（转下一叶子 **P3.4**）、资源搜索与下载确认（**P3.3b**）、下载管理与订阅管理（**P5.1 / P4.1**）、发现页多来源筛选与模块编排（**P3.2b**）及剩余插件/系统/P8 门禁。
- 默认客户端入口仍保留 `1.x`，不提前切换。
