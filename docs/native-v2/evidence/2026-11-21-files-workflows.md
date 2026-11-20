# P5.2 / P5.4 原生文件管理与工作流清单/执行验收证据

- 日期：2026-11-21
- 分支：`MoviePilot-App` / `v2`
- 目标范围：以单一深色渐变玻璃风格实现原生多存储文件浏览器（`/filemanager`）与原生工作流清单与运行控制页（`/workflow`），全部直连 MoviePilot 后端 API，严守管理权限门控与二次确认删除/重置边界，零 WebView。

## 主要实现面

1. **`ios/MoviePilot/NativeV2/Pages/NativeFileManagerPage.swift`（P5.2）**
   - 直连 `GET /api/v1/storage/options`（兼容 `type`/`name` 与 `value`/`title`）、`POST /api/v1/storage/list`、`POST /api/v1/storage/mkdir` 与 `POST /api/v1/storage/delete`。
   - 多存储切换胶囊（`本地` / `SMB网络共享` 等）、路径面包屑与返回上级按钮、目录优先排序、原生视频/音频/字幕/图片符号、顶部 Liquid Glass 双按钮工具栏（新建文件夹 + 刷新）及二次确认删除弹窗。
2. **`ios/MoviePilot/NativeV2/Pages/NativeWorkflowsPage.swift`（P5.4）**
   - 直连 `GET /api/v1/workflow/`、`POST /api/v1/workflow/{id}/run`、`POST /api/v1/workflow/{id}/start`、`POST /api/v1/workflow/{id}/pause` 与 `POST /api/v1/workflow/{id}/reset`。
   - 工作流状态徽标（运行中/已完成/失败/已停用/待触发）、Cron 调度计划与运行次数统计、单次手动运行、启停切换及二次确认重置弹窗。
3. **`ios/MoviePilot/NativeV2/NativeV2MainShell.swift`**
   - 在「我的 -> 媒体工作台」按管理权限接入「文件管理」与「工作流」原生推入入口。

## 验证记录

1. **脚本与格式检查**
   - `python3 -m unittest discover -s scripts/tests`：27/27 通过。
   - `xcrun swift-format lint --strict`：0 错误。
   - 全仓文本敏感命名检查：0 匹配。
2. **API-only 合成夹具全链路 UI 验收（`testNativeFileManagerAndWorkflowFlows`）**
   - **iPhone 17**：1/1 通过（71.40s），覆盖多存储加载、目录钻取与返回上级、二次确认删除文件、工作流手动运行与停用控制，`unexpected == [:]`，`webViews.count == 0`。
   - **iPad Pro 11-inch (M5)**：1/1 通过（75.93s），全链路断言与请求计数一致。
3. **本机 3001 真实后端只读逐图验收（`scripts/native-v2-live.py`）**
   - 逐张复核「文件管理」（`本地` / `SMB网络共享` 多存储胶囊、Liquid Glass 双按钮工具栏、`/` 根目录 18 项）与「工作流」（`观众海外剧集` 调度计划、停用状态徽标、立即运行/启用/重置动作），零 WebView。

## 未覆盖与后续叶子

- 文件移动/复制/整理弹窗、工作流原生节点画布（P5.5）、系统设置八类视图与用户管理（下一激活叶子 **P6.2 / P6.3**）、多来源发现与模块编排（P3.2b）、音乐流程（P3.5）、插件剩余生态与 P8 门禁继续推进。
