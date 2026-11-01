MoviePilot iOS 1.0.10，统一更多菜单与业务页面的壁纸背景。支持 iOS 17+，iOS 26+ 使用系统 Liquid Glass。

### 更新内容

- 更多菜单与业务页面共用正在渲染的壁纸，沿用相同的明暗、自动轮播和渐变效果，切换主入口时保持背景连续。
- 菜单分组使用系统原生 Liquid Glass，实时透出下方壁纸；iOS 17–25 使用系统超薄磨砂材质。没有壁纸时沿用当前主题底色。
- 主题弹窗关闭后恢复相同背景与原生目录层级，滚动及横竖屏切换保持分组玻璃布局。

### 安装

下载 `MoviePilot-1.0.10-unsigned.ipa`，使用自己的 Apple 账户通过 SideStore、AltStore Classic 或 Sideloadly 重签后覆盖安装。小组件需要同时重签扩展并保留共享组。免费签名通常 7 天有效。

实例继续使用现有兼容前端即可，本次更新无需单独重新打包前端；壁纸是否启用及其明暗规则遵循前端当前设置。

[安装与续签](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/install.md) · [小组件](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/widgets.md) · [通知配置](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/notifications.md)

Release 同时提供 `SHA256SUMS`。本包使用 iPhoneOS SDK 和 arm64 架构构建；已通过真实账号的 iOS 26.1 模拟器验收，iPhone 完整系统集成验收仍在进行。
