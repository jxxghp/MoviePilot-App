MoviePilot iOS 1.0.5，修复系统明暗切换后顶部导航栏渐变未更新的问题。支持 iOS 17+，iOS 26+ 使用系统 Liquid Glass。

### 更新内容

- 修复关闭业务弹窗后，系统切换明暗主题时顶部导航栏模糊渐变仍保留旧底色的问题，覆盖前台切换和后台恢复。
- 原生更多目录同步使用动态主题底色，保留手动选择明暗主题的优先级及业务弹窗的透明材质。

### 安装

下载 `MoviePilot-1.0.5-unsigned.ipa`，使用自己的 Apple 账户通过 SideStore、AltStore Classic 或 Sideloadly 重签后覆盖安装。小组件需要同时重签扩展并保留共享组。免费签名通常 7 天有效。

建议同步更新至 MoviePilot-Frontend **3.2.1** 或更新的兼容前端，前端页面修复在实例资源同步后生效。

[安装与续签](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/install.md) · [小组件](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/widgets.md) · [通知配置](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/notifications.md)

Release 同时提供 `SHA256SUMS`。本包使用 iPhoneOS SDK 和 arm64 架构构建；iPhone 完整系统集成验收仍在进行。
