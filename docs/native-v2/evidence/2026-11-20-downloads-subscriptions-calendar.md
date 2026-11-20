# P5.1 / P4.1 / P4.4 原生下载管理、订阅中心、追剧日历与发现页快捷菜单验收证据

- 日期：2026-11-20
- 分支：`MoviePilot-App` / `v2`
- 目标范围：以单一深色渐变玻璃风格实现原生下载管理（参照视觉参考 07）、原生订阅中心、原生追剧日历（参照视觉参考 13）与发现页重复点击悬浮快捷菜单（参照视觉参考 09），全部直连 MoviePilot 后端 API 且零 WebView。

## 主要实现面

1. **`ios/MoviePilot/NativeV2/Pages/NativeDownloadsPage.swift`（P5.1）**
   - 直连 `GET /api/v1/download/clients`、`GET /api/v1/download/`、`GET /api/v1/download/start/{hash}`、`GET /api/v1/download/stop/{hash}` 与 `DELETE /api/v1/download/{hash}`。
   - 多下载器筛选胶囊、16:9 媒体缩略图带进度百分比覆层、下载/上传速度与剩余时间、白色进度条、单次启停控制及二次确认删除弹窗；具备有效影视身份时可直接推入 `NativeMediaDetailPage`。
2. **`ios/MoviePilot/NativeV2/Pages/NativeSubscriptionsPage.swift`（P4.1）**
   - 直连 `GET /api/v1/subscribe/`、`PUT /api/v1/subscribe/status/{id}?state=S|R` 与 `DELETE /api/v1/subscribe/{id}`。
   - 分类筛选胶囊（全部/电影/电视剧/音乐 + 实时计数）、本地片名搜索、2:3 竖版海报、状态徽标（订阅中/洗版/已暂停）、剧集完成进度条、单次暂停/恢复、二次确认删除及点击海报/片名推入详情页。
3. **`ios/MoviePilot/NativeV2/Pages/NativeCalendarPage.swift`（P4.4）**
   - 直连 `GET /api/v1/subscribe/calendar?start=...&end=...`。
   - 自然周 7 天日签条（暖红标注今日、圆角玻璃高亮选中日、紫色小点标记播出日、左右切周与「今天」按钮）、当日播出列表或空态玻璃卡、`LazyVStack` 本周排期汇总与统一 `420px` 内存海报缓存档位。
4. **`ios/MoviePilot/NativeV2/NativeV2MainShell.swift`**
   - 发现页重复点击「发现」标签弹出深色透色悬浮快捷菜单（直达订阅、下载、日历、仪表盘）；「我的」页内通过 `CinematicFormSection` 提供按权限门控的「媒体工作台」原生入口。

## 验证记录

1. **脚本与格式检查**
   - `python3 -m unittest discover -s scripts/tests`：27/27 通过。
   - `xcrun swift-format lint --strict`：0 错误。
   - 全仓文本敏感命名检查：0 匹配。
2. **API-only 合成夹具全链路 UI 验收（`testNativeDownloadsSubscriptionsAndCalendarFlows`）**
   - **iPhone 17**：1/1 通过（75.58s），覆盖订阅暂停/二次确认删除、下载暂停/二次确认删除进入空态与追剧日历切周，`unexpected == [:]`，`webViews.count == 0`。
   - **iPad Pro 11-inch (M5)**：1/1 通过（77.53s），全链路断言与请求计数一致。
3. **本机 3001 真实后端只读逐图验收（`scripts/native-v2-live.py`）**
   - `{"result": "Passed", "passedTests": 1, "failedTests": 0, "skippedTests": 0, "backend": "http://127.0.0.1:3001/"}`。
   - 逐张复核真实 72 项「我的订阅」（全部 72 / 电影 28 / 电视剧 43 / 音乐 1）、真实 Qbittorrent「正在下载」（`合伙人 S03` 16:9 缩略图、14.4% 进度、实时速率）与「追剧日历」（2026-11-15–21 周签条、当日播出列表与海报渲染），无任何 WebView。

## 未覆盖与后续叶子

- 订阅高级规则编辑器/共享订阅（P4.2/P4.3）、资源搜索与下载确认（下一激活叶子 **P3.3b**）、多来源发现与模块编排（**P3.2b**）、文件管理/整理历史/工作流/设置/插件剩余生态与 P8 门禁继续推进。
