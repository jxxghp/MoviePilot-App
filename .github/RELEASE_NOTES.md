MoviePilot iOS 1.0.8，新增匿名安装版本统计。支持 iOS 17+，iOS 26+ 使用系统 Liquid Glass。

### 更新内容

- 新增 iOS App 版本安装统计，按匿名安装标识去重，升级后更新为当前版本，连接多个实例不重复计数。
- 遵守实例的“分享使用统计”开关；管理员登录并开启开关后，每个版本每天最多成功上报一次，仅发送随机安装标识和 App 版本。
- 配合新版 MoviePilot-Server 和 MoviePilot-Frontend 3.2.2，在安装版本统计中查看 iOS App 版本分布；不影响原有后端实例与活跃用户计数。

### 安装

下载 `MoviePilot-1.0.8-unsigned.ipa`，使用自己的 Apple 账户通过 SideStore、AltStore Classic 或 Sideloadly 重签后覆盖安装。小组件需要同时重签扩展并保留共享组。免费签名通常 7 天有效。

建议同步更新至 MoviePilot-Frontend **3.2.2** 或更新的兼容前端，前端页面修复在实例资源同步后生效。

[安装与续签](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/install.md) · [小组件](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/widgets.md) · [通知配置](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/notifications.md)

Release 同时提供 `SHA256SUMS`。本包使用 iPhoneOS SDK 和 arm64 架构构建；iPhone 完整系统集成验收仍在进行。
