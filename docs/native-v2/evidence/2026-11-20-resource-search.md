# P3.3b 原生资源搜索与下载确认验收证据

- 日期：2026-11-20
- 分支：`MoviePilot-App` / `v2`
- 目标范围：在影视详情页和媒体工作台接入受 `search` 权限门控的原生站点资源搜索与下载确认闭环，支持按媒体精准检索、最近搜索结果与关键词检索、站点多选、免费/4K/1080p/中字筛选、排序，以及选择下载器与保存目录后的显式单次下载提交（绝不自动重试）。

## 主要实现面

- `ios/MoviePilot/NativeV2/Pages/NativeResourceSearchPage.swift`：
  - `NativeResourceSearchPage`：直连 `GET /api/v1/search/media/{id}`、`GET /api/v1/search/title`、`GET /api/v1/search/last` 与 `GET /api/v1/site/`；以 64 位 FNV-1a 全量摘要生成无碰撞列表键，完整呈现同站点全部资源卡。
  - `NativeDownloadConfirmSheet`：读取 `GET /api/v1/download/clients` 与 `GET /api/v1/download/paths`，支持显式取消或单次提交 `POST /api/v1/download/add`（完整透传 `torrent_in`、`media_source`、`media_id`、`downloader`、`save_path`）。
- `ios/MoviePilot/NativeV2/Pages/NativeMediaDetailPage.swift`：在 `CinematicGlassGroup` 主操作栏补齐圆形玻璃「搜索站点资源」入口，直达该作品资源列表。
- `ios/MoviePilot/NativeV2/NativeV2MainShell.swift`：在「我的 -> 媒体工作台」与发现页悬浮快捷菜单接入受 `search` 权限控制的「资源搜索」入口。

## 验证记录

1. **脚本与格式检查**
   - `python3 -m unittest discover -s scripts/tests`：27/27 通过。
   - `xcrun swift-format lint --strict`：0 错误。
   - 全仓文本敏感命名检查：0 匹配。
2. **API-only 合成夹具全链路 UI 验收（`testNativeResourceSearchAndDownloadConfirmation`）**
   - **iPhone 17**：1/1 通过（61.78s），验证详情直达精确检索、免费筛选、下载确认弹窗取消再显式提交 `POST api/v1/download/add`（计数严格为 1），`unexpected == [:]`，`webViews.count == 0`。
   - **iPad Pro 11-inch (M5)**：1/1 通过（61.09s），全链路断言一致。
3. **本机 3001 真实后端只读逐图验收（`scripts/native-v2-live.py`）**
   - 详情页主操作栏圆形玻璃搜索按钮排版与通透度核对通过；修复同站点链接前缀哈希碰撞后，完整多条真实站点种子结果（站点徽标、分辨率、促销、大小、做种数、发布时长与下载按钮）全部正常渲染，零 WebView。

## 未覆盖与后续叶子

- 资源搜索 SSE 渐进流式进度与字幕搜索、媒体整理历史（`/history`）、站点管理（`/site`）、文件管理（`/filemanager`）、工作流、设置与插件剩余生态按路线图继续推进。
