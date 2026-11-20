# 2026-11-21 原生多来源探索片库与发现模块编排验收记录（P3.2b）

## 范围与实现

- 新增 [NativeExplorePage.swift](../../../ios/MoviePilot/NativeV2/Pages/NativeExplorePage.swift)：
  - 原生多来源探索与筛选页面，支持 `TMDB 电影`、`TMDB 剧集`、`豆瓣电影`、`豆瓣剧集`、`Bangumi` 及 `GET /api/v1/discover/source` 动态插件发现源。
  - 按所选来源呈现对应排序/风格/语言/标签/年份筛选胶囊，采用 3 列（iPad 5 列）自动翻页海报网格，复用 `420px` 同源代理图片缓存，点击直达原生 `NativeMediaDetailPage`。
- 新增 [NativeDiscoverModulesSheet.swift](../../../ios/MoviePilot/NativeV2/Pages/NativeDiscoverModulesSheet.swift)：
  - 参照视觉参考 `10` 实现深色紫玫瑰透色玻璃「管理模块」弹层，支持 8 项 MoviePilot 发现模块（继续观看、热门电影、热门剧集、本周趋势、豆瓣热映、豆瓣 Top250、最新入库、媒体库与分类）的原生开关显隐控制与右侧原生手柄拖拽排序，并经 `GET/POST /api/v1/user/config/NativeDiscoverModules` 单次持久化。
- 更新 [NativeDiscoverPage.swift](../../../ios/MoviePilot/NativeV2/Pages/NativeDiscoverPage.swift) 与 [NativeV2MainShell.swift](../../../ios/MoviePilot/NativeV2/NativeV2MainShell.swift)：
  - 发现页按用户持久化模块顺序动态排布，补充参照视觉参考 `14` 的「分类探索」两列确定性玻璃海报入口（消除 `LazyVStack` 嵌套 `LazyVGrid` 在 iPadOS 26 动态插入模块时的布局振荡）与页底「管理发现模块」按钮。
  - 在发现页悬浮快捷菜单及「我的 -> 媒体工作台」同步接入「探索片库」与「管理模块」，并在 `iOS 18+` 移除旧版 `GeometryReader` 滚动偏好探测、截断深滚动偏移避免无意义重算。

## 验证结果

1. **静态与格式校验**
   - `xcodegen generate --spec ios/project.yml` 通过。
   - `xcrun swift-format lint --strict` 0 告警通过。
   - 全仓禁用命名（整词及驼峰）扫描：0 匹配。
   - `python3 -m unittest discover -s scripts/tests`：27 项全部通过。
2. **API-only 合成夹具双端 UI 回归（零 WebView）**
   - iPad Pro 11-inch (M5) (`26D71997-F654-4AE6-8D8E-BFDB7CC0E766`)：`testNativeExploreSourcesAndModuleArrangement` 通过（73.7s，0 失败，0 跳过；验证 `POST api/v1/user/config/NativeDiscoverModules == 1`、`GET api/v1/recommend/douban_showing == 1`、豆瓣/Bangumi 切换与海报加载、`webViews.count == 0`、`unexpected == [:]`）。
   - iPhone 17 (`56286E2B-6AC1-4087-9936-F9DDA70D9E0A`)：`testNativeExploreSourcesAndModuleArrangement` 通过（0 失败，0 跳过）。
3. **本机 `3001` 真实后端只读逐图验收**
   - `scripts/native-v2-live.py` 针对 `http://127.0.0.1:3001/` 全程只读执行通过（`passedTests: 1`, `failedTests: 0`, `skippedTests: 0`）。
   - 逐图核验 `native-v2-live-modules.png`、`native-v2-live-explore.png` 与 `native-v2-live-explore-douban.png`：
     - `管理模块` 弹层完整还原视觉参考 `10` 的深色紫玫瑰玻璃容器、前置图标、绿色开关、右侧拖拽手柄与 Liquid Glass 顶栏按钮。
     - `探索片库` 清晰加载 TMDB 电影与豆瓣电影真实代理海报、评分徽标与多行筛选胶囊。

## 保留范围

- 音乐多来源探索/专辑/艺术家详情（P3.5）、订阅高级规则编辑器与热门分享（P4.2/P4.3）及插件剩余生态继续归入后续叶子。
