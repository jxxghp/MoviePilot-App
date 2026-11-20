# P5.3 / P6.1 / P6.4 原生整理历史、站点管理与消息中心验收证据

- 日期：2026-11-21
- 分支：`MoviePilot-App` / `v2`
- 目标范围：以单一深色渐变玻璃风格实现原生整理历史（`/history`）、原生站点管理（`/site`）与原生消息中心（`/message/web`），全部直连 MoviePilot 后端 API，严守权限与敏感信息屏蔽边界，零 WebView。

## 主要实现面

1. **`ios/MoviePilot/NativeV2/Pages/NativeTransferHistoryPage.swift`（P5.3）**
   - 直连 `GET /api/v1/history/transfer`（分页 + 按片名搜索）与 `DELETE /api/v1/history/transfer`（显式确认仅删除记录，`deletesrc=false&deletedest=false`）。
   - 状态筛选胶囊（全部/成功/失败）、海报与整理模式徽标、可展开源/目标路径与错误原因、触底自动翻页及点击片名推入影视详情页。
2. **`ios/MoviePilot/NativeV2/Pages/NativeSitesPage.swift`（P6.1）**
   - 直连 `GET /api/v1/site/` 与 `GET /api/v1/site/test/{id}`；仅解码非敏感站点元数据，主动忽略 `cookie`/`apikey`/`token`/`rss` 等敏感凭据字段。
   - 启用状态计数筛选（全部/已启用/已停用）、站名/域名搜索与单站实时连通测试。
3. **`ios/MoviePilot/NativeV2/Pages/NativeMessagesPage.swift`（P6.4）**
   - 直连 `GET /api/v1/message/web` 分页消息时间线，支持按分类（全部/订阅/整理/下载/站点）筛选、带配图的透色通知玻璃卡片与触底翻页。
4. **`ios/MoviePilot/NativeV2/NativeV2MainShell.swift`**
   - 在「我的 -> 媒体工作台」按管理权限接入「整理历史」「站点管理」，面向全部已认证用户开放「消息中心」。

## 验证记录

1. **脚本与格式检查**
   - `python3 -m unittest discover -s scripts/tests`：27/27 通过。
   - `xcrun swift-format lint --strict`：0 错误。
   - 全仓文本敏感命名检查：0 匹配。
2. **本机 3001 真实后端只读逐图验收（`scripts/native-v2-live.py`）**
   - `{"result": "Passed", "passedTests": 1, "failedTests": 0, "skippedTests": 0, "backend": "http://127.0.0.1:3001/"}`。
   - 逐张复核实图：真实 2,250 条「整理历史」（海报、成功徽标、复制方式、路径展开与删除按钮）、真实 51 个「站点管理」（启用计数、域名、优先级、连通测试按钮、零敏感凭据泄漏）与「消息中心」（单行分类胶囊、真实资源下载/订阅通知与全宽 16:9 配图），零 WebView。
3. **API-only 合成夹具全链路 UI 验收（`testNativeHistorySitesAndMessagesFlows`）**
   - **iPhone 17 & iPad Pro 11-inch (M5)**：覆盖整理历史路径展开与二次确认删除（`DELETE api/v1/history/transfer`）、站点连通测试（`GET api/v1/site/test/3` -> `连接正常`）与消息中心分类过滤（`GET api/v1/message/web`），`unexpected == [:]`，`webViews.count == 0`。

## 未覆盖与后续叶子

- 站点新增/编辑/Cookie 同步与资源浏览、整理重做/刮削弹窗、文件管理与工作流（转入下一激活叶子 **P5.2 / P5.4**）、设置八视图、用户/MFA、插件剩余生态与 P8 门禁继续推进。
