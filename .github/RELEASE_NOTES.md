MoviePilot iOS 1.1.1，修复原生“更多”和搜索页面中 AI 助手形象透出、显示但无法点击的问题。支持 iOS 17+，iOS 26+ 使用系统 Liquid Glass。

### 更新内容

- 原生“更多”和搜索页面隐藏网页侧的助手悬浮入口与桌面形象，避免从原生菜单卡片间透出不可点击的机器人。
- 离开这些页面后自动恢复助手；保留形象实例与状态，不改变原有路由和手势。
- 保留动态壁纸、主题与业务 Sheet 的原有处理。

### 前端兼容

此修复只需升级 App，无需为此更新前端。独立搜索仍需 [MoviePilot-Frontend v3.2.4](https://github.com/jxxghp/MoviePilot-Frontend/releases/tag/v3.2.4) 或更新的兼容版本；旧前端继续使用原搜索浮层。

### 安装

下载 `MoviePilot-1.1.1-unsigned.ipa`，使用自己的 Apple 账户通过 SideStore、AltStore Classic 或 Sideloadly 重签后覆盖安装。小组件需要同时重签扩展并保留共享组。免费签名通常 7 天有效。

[安装与续签](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/install.md) · [小组件](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/widgets.md) · [通知配置](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/notifications.md)

Release 同时提供 `SHA256SUMS`。本包使用 iPhoneOS SDK 和 arm64 架构构建；安装前需自行重签。
