# 2026-11-21 原生订阅高级编辑与订阅广场/社区分享验收记录（P4.2 / P4.3）

## 范围与实现

- 新增 [NativeSubscribeEditorSheet.swift](../../../ios/MoviePilot/NativeV2/Pages/NativeSubscribeEditorSheet.swift)：
  - 从 `GET /api/v1/subscribe/{id}` 读取实时订阅详情及 `GET /api/v1/download/clients` 下载器列表，以深色紫玫瑰透色分组表单提供画质/分辨率/特效/自动洗版、关键字/包含/排除/自定义识别词、剧集总集数与开始集数、下载器与保存路径编辑。
  - 仅提交 `id` 与用户修改过的公共可写字段至 `PUT /api/v1/subscribe/`（支持 `CLEARABLE_OPTIONAL_FIELDS` 显式清空且不提交受保护运行态字段），显式单次保存、不自动重试。
- 新增 [NativeSubscribeCommunityPage.swift](../../../ios/MoviePilot/NativeV2/Pages/NativeSubscribeCommunityPage.swift)：
  - 提供「热门电影」、「热门剧集」（`GET /api/v1/subscribe/popular`，三列/五列海报网格 + 热度人数徽标 + 详情跳转）与「社区分享」（`GET /api/v1/subscribe/shares`，海报/分享者/复用次数/规则胶囊/搜索过滤及二次确认单次 `POST /api/v1/subscribe/fork` 复用）。
- 更新 [NativeSubscriptionsPage.swift](../../../ios/MoviePilot/NativeV2/Pages/NativeSubscriptionsPage.swift) 与 [NativeV2MainShell.swift](../../../ios/MoviePilot/NativeV2/NativeV2MainShell.swift)：
  - 订阅卡片新增「编辑」入口，顶栏新增「订阅广场」入口；「我的 -> 媒体工作台」同步新增受 `subscribe` 权限门控的「订阅广场」直达项。

## 验证结果

1. **静态与格式校验**
   - `xcodegen generate --spec ios/project.yml` 通过。
   - `xcrun swift-format lint --strict` 0 告警通过。
   - 全仓禁用命名（整词及驼峰）扫描：0 匹配。
   - `python3 -m unittest discover -s scripts/tests`：27 项全部通过。
2. **API-only 合成夹具双端 UI 回归（零 WebView）**
   - iPhone 17 (`56286E2B-6AC1-4087-9936-F9DDA70D9E0A`)：`testNativeSubscribeEditorAndCommunityForkFlows` 通过（77.6s，0 失败，0 跳过；验证 `GET /api/v1/subscribe/702 == 1`、`PUT /api/v1/subscribe/ == 1`、`GET /api/v1/subscribe/popular == 1`、`GET /api/v1/subscribe/shares == 1`、`POST /api/v1/subscribe/fork == 1`、`webViews.count == 0`、`unexpected == [:]`）。
   - iPad Pro 11-inch (M5) (`26D71997-F654-4AE6-8D8E-BFDB7CC0E766`)：`testNativeSubscribeEditorAndCommunityForkFlows` 通过（95.8s，0 失败，0 跳过）。
3. **本机 `3001` 真实后端只读逐图验收**
   - `scripts/native-v2-live.py`（配额调整至 420s 以覆盖 28 张全量页面采集）针对 `http://127.0.0.1:3001/` 全程只读执行通过。
   - 逐图核验 `native-v2-live-subscribe-editor.png`、`native-v2-live-community-popular.png` 与 `native-v2-live-community-shares.png`：
     - `编辑订阅 · 活色生香` 准确呈现分组玻璃表单、下载器下拉与未改禁用保存状态。
     - `订阅广场 · 热门电影` 清晰加载 9+ 部真实热门海报与热度徽标（`7.5k`、`7.3k`、`6.7k` 等）。
     - `订阅广场 · 社区分享` 清晰加载社区分享卡片、分享者、复用人数、分辨率/HDR 过滤规则胶囊与「复用订阅」按钮。

## 保留范围

- 音乐多来源探索/专辑/艺术家详情与音乐订阅（P3.5）、原生插件市场与完整插件生态（P7.1/P2.3–2.5）、Agent 流式对话（P6.5）、工作流节点画布（P5.5）及系统集成解耦与 P8 总切换门禁继续按路线推进。
