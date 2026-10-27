MoviePilot iOS 1.0.4，适配 iOS 桌面图标外观并支持 HTTP 实例连接。支持 iOS 17+，iOS 26+ 使用系统 Liquid Glass。

### 更新内容

- 新增浅色桌面图标，保留深色图标，由 iOS 主屏幕“自定义”中的外观选项切换。
- 新增专用单色图标资源，使用“色调”时跟随桌面选定的颜色。
- 实例连接支持 HTTP 和 HTTPS，公网域名、IP 与局域网地址均可使用；同步适配原生登录、内嵌页面与小组件。

### 安装

下载 `MoviePilot-1.0.4-unsigned.ipa`，使用自己的 Apple 账户通过 SideStore、AltStore Classic 或 Sideloadly 重签后覆盖安装。小组件需要同时重签扩展并保留共享组。免费签名通常 7 天有效。

建议同步更新至 MoviePilot-Frontend **3.2.1** 或更新的兼容前端，前端页面修复在实例资源同步后生效。

[安装与续签](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/install.md) · [小组件](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/widgets.md) · [通知配置](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/notifications.md)

Release 同时提供 `SHA256SUMS`。本包使用 iPhoneOS SDK 和 arm64 架构构建；iPhone 完整系统集成验收仍在进行。
