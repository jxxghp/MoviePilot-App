# 2026-11-21 原生 AI Agent 流式对话与交互面板验收记录（P6.5）

## 范围与实现

- 增强传输层 [APIError.swift](../../../Sources/MoviePilotAPI/APIError.swift) 与 [APIClient.swift](../../../Sources/MoviePilotAPI/APIClient.swift)：
  - 新增 `APIResponseContract.eventStream`，在请求侧显式声明 `Accept: text/event-stream` 并在响应侧严格校验 `Content-Type: text/event-stream`，使 SSE 端点完全复用同源校验、令牌隔离、大小上限与取消机制，拒绝非流式 HTML 响应。
- 新增 [NativeAgentChatPage.swift](../../../ios/MoviePilot/NativeV2/Pages/NativeAgentChatPage.swift)：
  - 对接 `GET /api/v1/agent/commands`、`GET /api/v1/agent/sessions`、`GET /api/v1/agent/sessions/{id}`、`DELETE /api/v1/agent/sessions/{id}`、`POST /api/v1/agent/sessions/{id}/stop` 与 `POST /api/v1/agent/stream`。
  - 提供深色紫玫瑰透色玻璃欢迎页与快捷提问、可用斜杠命令提示、用户/助手消息气泡、工具调用摘要条、历史会话管理弹层、新建会话与任务中断停止，零 WebView。
- 更新 [NativeV2MainShell.swift](../../../ios/MoviePilot/NativeV2/NativeV2MainShell.swift)：
  - 在「我的 -> 媒体工作台」与发现页悬浮快捷菜单同步接入「智能助手」原生入口。

## 验证结果

1. **静态与包级校验**
   - `xcodegen generate --spec ios/project.yml` 通过。
   - `xcrun swift-format lint --strict` 0 告警通过。
   - `swift test --scratch-path /Volumes/DISK/TmpBuild/MoviePilotAppSPM`：35 项测试全部通过。
   - `python3 -m unittest discover -s scripts/tests`：27 项全部通过。
   - 全仓禁用命名（整词及驼峰）扫描：0 匹配。
2. **API-only 合成夹具双端 UI 回归（零 WebView）**
   - iPhone 17 (`56286E2B-6AC1-4087-9936-F9DDA70D9E0A`)：`testNativeAgentChatStreamAndSessionHistory` 通过（65.0s，0 失败，0 跳过；验证 `POST /api/v1/agent/stream == 1`、`GET /api/v1/agent/sessions/sess-1 == 1`、SSE 工具与文本增量解析、历史会话切换、`webViews.count == 0`、`unexpected == [:]`）。
   - iPad Pro 11-inch (M5) (`26D71997-F654-4AE6-8D8E-BFDB7CC0E766`)：`testNativeAgentChatStreamAndSessionHistory` 通过（77.0s，0 失败，0 跳过）。
3. **本机 `3001` 真实后端只读逐图验收**
   - `scripts/native-v2-live.py` 针对 `http://127.0.0.1:3001/` 全程只读执行通过（`passedTests: 1`, `failedTests: 0`, `skippedTests: 0`）。
   - 逐图核验 `native-v2-live-agent.png`：发光紫玫瑰星芒徽标、3 张玻璃快捷提问卡、顶栏配对 Liquid Glass 历史会话/新对话胶囊与底部半透明输入栏层次完整。

## 保留范围

- Agent 附件上传/选择卡片回调/远程插件形象、插件 JSON 数据页/仪表板/受控 Web 兼容容器（P2.3–2.5）、原生工作流节点画布（P5.5）、系统集成解耦（P7.2–7.3）及 P8 切换门禁继续按路线推进。
