# 2026-11-21 原生系统设置中心与用户权限管理验收记录（P6.2 / P6.3）

## 范围与实现

- 新增 [NativeSystemSettingsPage.swift](../../../ios/MoviePilot/NativeV2/Pages/NativeSystemSettingsPage.swift)：
  - 参照视觉参考 `04` 的深色紫玫瑰透色分组风格，提供 2×2 状态概览玻璃卡（主识别源、订阅模式、全局图片缓存、日志级别）与三大分组设置面板（媒体识别与搜索、订阅与下载、系统与缓存，含后端版本与服务端时区只读摘要）。
  - 仅解码白名单非敏感 `GET /api/v1/system/env` 字段，严格过滤密钥、Token 与敏感凭据；保存时仅计算变更差量并经用户显式点击单次提交至 `POST /api/v1/system/env`，不自动重试。
- 新增 [NativeUsersPage.swift](../../../ios/MoviePilot/NativeV2/Pages/NativeUsersPage.swift)：
  - 仅超级管理员可见，直连 `GET /api/v1/user/` 展示用户头像徽标、角色标签（当前账号、超级管理员/普通用户）、启用状态、2FA 状态与四类权限胶囊，支持关键词检索与手动刷新，绝不解码密码哈希或密钥。
- 更新 [NativeV2MainShell.swift](../../../ios/MoviePilot/NativeV2/NativeV2MainShell.swift)：
  - 在「我的」独立导航栈新增受 `snapshot.user.isSuperuser` 门控的「系统管理」分组，直达 `系统设置` 与 `用户管理`。

## 验证结果

1. **静态与格式校验**
   - `xcodegen generate --spec ios/project.yml` 通过。
   - `xcrun swift-format lint --strict` 针对全部新增与修改 Swift 文件 0 告警通过。
   - 全仓禁用命名（整词及驼峰）扫描：0 匹配。
2. **包级与脚本单测**
   - `swift test --scratch-path /Volumes/DISK/TmpBuild/MoviePilotAppSPM`：35 项测试全部通过。
   - `python3 -m unittest discover -s scripts/tests`：27 项测试全部通过。
3. **API-only 合成夹具双端 UI 回归（零 WebView）**
   - iPhone 17 (`56286E2B-6AC1-4087-9936-F9DDA70D9E0A`)：`testNativeSystemSettingsAndUsersFlows` 通过（0 失败，0 跳过；验证 `GET/POST /api/v1/system/env` 单次增量保存、`GET /api/v1/user/` 列表与刷新、`webViews.count == 0`、`unexpected == [:]`）。
   - iPad Pro 11-inch (M5) (`26D71997-F654-4AE6-8D8E-BFDB7CC0E766`)：`testNativeSystemSettingsAndUsersFlows` 通过（0 失败，0 跳过）。
4. **本机 `3001` 真实后端只读逐图验收**
   - `scripts/native-v2-live.py` 针对 `http://127.0.0.1:3001/` 全程只读执行通过（`passedTests: 1`, `failedTests: 0`, `skippedTests: 0`）。
   - 逐图核验 `native-v2-live-settings.png` 与 `native-v2-live-users.png`：
     - 系统设置页准确呈现真实环境快照（`TheMovieDb`、`站点爬虫`、`全局图片缓存: 已开启`、`日志级别: INFO`、`刷新周期: 30 分钟`），2×2 透色概览卡、分组玻璃表单与 iOS 26 Liquid Glass 返回/保存按钮层次清晰，未变更时保存按钮保持禁用。
     - 用户管理页准确呈现真实管理员账号、当前账号/超级管理员/正常状态徽标及全部管理权限胶囊，零敏感字段暴露。

## 保留范围

- 其余八类 `AccountSetting` 高级子页（目录映射、二级分类、过滤规则、通知渠道等）与用户增改删/MFA/Passkey 编排归入后续 `P6.2b` / `P6.3b` 叶子，不将全部设置与用户安全子功能冒标为已完成。
