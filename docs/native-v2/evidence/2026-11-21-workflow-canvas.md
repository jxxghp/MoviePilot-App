# P5.5 原生工作流节点画布、参数编辑与社区分享复用验收记录

- 日期：2026-11-21
- 仓库与分支：`MoviePilot-App` / `v2`
- 范围：
  1. `NativeWorkflowCanvasPage`（`ios/MoviePilot/NativeV2/Pages/NativeWorkflowCanvasPage.swift`）：纯 SwiftUI `Canvas` + 手势实现的原生工作流节点画布（零 WebView），直连 `GET /api/v1/workflow/{id}`、`GET /api/v1/workflow/actions` 与单次 `PUT /api/v1/workflow/{id}` 保存。
     - 轻柔点阵参考网格、三次贝塞尔有向连线与箭头、透色紫玫瑰玻璃节点卡片、节点单指拖拽定位、画布平移与缩放/多节点自动适配视口居中。
     - 节点目录弹层（搜索/点击新增并自动从当前选中节点连线）、底部属性工具条（参数计数/出边计数、编辑参数、出边连线管理弹层、删除节点）、原生节点参数编辑器（名称/描述/超时/布尔与文本参数动态编辑与新增键值）。
  2. `NativeWorkflowsPage`（`ios/MoviePilot/NativeV2/Pages/NativeWorkflowsPage.swift`）：新增顶部「我的工作流」/「社区分享」切换、工作流卡片「画布」直达入口及社区分享浏览与二次确认复用（`GET /api/v1/workflow/shares` + `POST /api/v1/workflow/fork`）。

## 自动化验证

1. 工程生成与严格格式检查：
   - `xcodegen generate --spec ios/project.yml --project ios`：通过。
   - `xcrun swift-format lint --strict` 覆盖全部新增与修改 Swift 文件：0 告警。
2. 脚本与夹具单测：
   - `python3 -m unittest discover -s scripts/tests`：27/27 通过。
3. iPhone 17 与 iPad Pro 11-inch (M5) API-only 合成 UI 验收（回环端口 5330）：
   - `testNativeWorkflowCanvasEditSaveAndCommunityFork`：验证进入工作流 `31` 纯原生画布、读取现有节点、打开动作目录添加 `SendMessageAction`、打开节点参数编辑器并应用、点击右上角保存单次 `PUT /api/v1/workflow/31`，返回切至「社区分享」确认复用单次 `POST /api/v1/workflow/fork`；全程 `webViews.count == 0`、`unexpected == [:]`。
   - iPhone 17 与 iPad Pro 11-inch (M5) 均 0 失败、0 跳过。
4. 本地 `http://127.0.0.1:3001/` 真实后端只读实测与逐图核查（41 张全屏实测截图，`passedTests: 1, failedTests: 0, skippedTests: 0`）：
   - `native-v2-live-workflows.png`：展示真实工作流「观众海外剧集」卡片及「画布」「运行」「启用」「重置」原生按钮。
   - `native-v2-live-workflow-canvas.png`：纯原生画布渲染「观众海外剧集（7 节点 · 5 连线）」，节点卡「获取 RSS 资源 · FetchRssAction」、平滑贝塞尔连线与底部属性操作栏清晰对齐，零 WebView。
   - `native-v2-live-workflow-shares.png`：社区分享列表完整展示复用次数、作者、Cron 表达式及「复用」按钮。

## 下一步叶子

- 推进 **P6.2b / P6.3b 扩展系统设置八类视图、运行日志查看与用户安全管理**，随后推进 **P7.2 / P7.3 系统集成与原生播放解耦** 及 **P8 默认入口切换与遗留 WebKit 移除**。
