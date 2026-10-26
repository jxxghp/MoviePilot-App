MoviePilot iOS 1.0.2，汇总近期导航、登录与弹窗修复。支持 iOS 17+，iOS 26+ 使用系统 Liquid Glass。

### 更新内容

- 顶栏保留系统滚动边缘效果，移除下沿形成横向亮带的额外模糊层。
- 包含 iOS 26 底部导航布局、后台恢复、插件搜索与卸载等近期修复。
- 通行密钥登录复用系统认证。配合最新前端，登录图标置顶，避免被系统凭证面板遮挡。

### 安装

下载 `MoviePilot-1.0.2-unsigned.ipa`，使用自己的 Apple 账户通过 SideStore、AltStore Classic 或 Sideloadly 重签后覆盖安装。小组件需要同时重签扩展并保留共享组。免费签名通常 7 天有效。

建议同步更新至 MoviePilot-Frontend **3.2.1** 或更新的兼容前端，前端页面修复在实例资源同步后生效。

[安装与续签](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/install.md) · [小组件](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/widgets.md) · [通知配置](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/notifications.md)

Release 同时提供 `SHA256SUMS`。本包使用 iPhoneOS SDK 和 arm64 架构构建；iPhone 完整系统集成验收仍在进行。
