MoviePilot iOS 1.0.9，改善启动加载与连接恢复。支持 iOS 17+，iOS 26+ 使用系统 Liquid Glass。

### 更新内容

- 页面加载超过 10 秒时显示等待状态，并提供“立即重试”和“更改地址”，无需一直停在 Logo 界面。
- 页面准备完成、进入后台或切换服务后撤销旧等待提示，避免迟到的提示遮住已恢复的首页。
- 配合本次重新打包的 MoviePilot-Frontend 3.2.2，修复媒体来源或模块目录接口偶发失败后无法完成 App 导航启动的问题；目录请求有超时上限和有限重试。

### 安装

下载 `MoviePilot-1.0.9-unsigned.ipa`，使用自己的 Apple 账户通过 SideStore、AltStore Classic 或 Sideloadly 重签后覆盖安装。小组件需要同时重签扩展并保留共享组。免费签名通常 7 天有效。

请同步更新本次重新打包的 MoviePilot-Frontend **3.2.2** 或更新的兼容前端。目录自动恢复属于前端页面修复，需要实例同步最新前端资源后生效；只更新 App 不会替换实例的前端页面。

[安装与续签](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/install.md) · [小组件](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/widgets.md) · [通知配置](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/notifications.md)

Release 同时提供 `SHA256SUMS`。本包使用 iPhoneOS SDK 和 arm64 架构构建；iPhone 完整系统集成验收仍在进行。
