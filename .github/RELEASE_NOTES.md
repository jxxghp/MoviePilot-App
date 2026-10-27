MoviePilot iOS 1.0.3，新增原生服务启动等待页。支持 iOS 17+，iOS 26+ 使用系统 Liquid Glass。

### 更新内容

- 服务启动、重启或暂时无法连接时显示原生等待页，自动检测服务恢复。
- 服务就绪后继续登录或恢复已保存的会话，等待时可立即重试或更改地址。
- 进入后台暂停检测，返回前台继续；密码、验证码和通行密钥提交不会自动重发。

### 安装

下载 `MoviePilot-1.0.3-unsigned.ipa`，使用自己的 Apple 账户通过 SideStore、AltStore Classic 或 Sideloadly 重签后覆盖安装。小组件需要同时重签扩展并保留共享组。免费签名通常 7 天有效。

建议同步更新至 MoviePilot-Frontend **3.2.1** 或更新的兼容前端，前端页面修复在实例资源同步后生效。

[安装与续签](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/install.md) · [小组件](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/widgets.md) · [通知配置](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/notifications.md)

Release 同时提供 `SHA256SUMS`。本包使用 iPhoneOS SDK 和 arm64 架构构建；iPhone 完整系统集成验收仍在进行。
