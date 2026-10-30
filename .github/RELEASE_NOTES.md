MoviePilot iOS 1.0.7，新增多服务切换与账号密码记忆。支持 iOS 17+，iOS 26+ 使用系统 Liquid Glass。

### 更新内容

- 新增已保存的服务列表，支持内网、外网与开发实例点选切换，各地址分别保留登录状态，并兼容旧版记录。
- 新增可选的“记住账号密码”，成功登录后保存在本机钥匙串，重新登录时自动回填；验证码仍需每次输入。
- 使用更紧凑的原生分组列表，左滑显示垃圾桶按钮，可删除服务，同时清除该地址保存的账号密码、登录状态和网页数据。

### 安装

下载 `MoviePilot-1.0.7-unsigned.ipa`，使用自己的 Apple 账户通过 SideStore、AltStore Classic 或 Sideloadly 重签后覆盖安装。小组件需要同时重签扩展并保留共享组。免费签名通常 7 天有效。

建议同步更新至 MoviePilot-Frontend **3.2.2** 或更新的兼容前端，前端页面修复在实例资源同步后生效。

[安装与续签](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/install.md) · [小组件](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/widgets.md) · [通知配置](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/notifications.md)

Release 同时提供 `SHA256SUMS`。本包使用 iPhoneOS SDK 和 arm64 架构构建；iPhone 完整系统集成验收仍在进行。
