# 安装与续签

[返回首页](../README.md)

需要 iOS 17+ 的 iPhone、自己的 Apple 账户和 MoviePilot 实例。首次配置 SideStore 等工具通常需要一台电脑。

在 [最新 Release](https://github.com/jxxghp/MoviePilot-App/releases/latest) 下载 `MoviePilot-版本号-unsigned.ipa`，当前版本为 **1.0.1**。安装包由 GitHub Actions 构建，**需要使用自己的 Apple 账户重签安装，不能下载后直接点开安装**。免费账户即可，无需付费开发者账号或 Xcode。

## 通过 SideStore 安装并自动续签

1. 按 [SideStore 准备指南](https://docs.sidestore.io/docs/installation/prerequisites) 和 [安装指南](https://docs.sidestore.io/docs/installation/install) 完成首次设置。当前官方流程使用电脑上的 **iloader** 安装 SideStore，并在 iPhone 上配置 **LocalDevVPN**、信任个人签名和开启开发者模式。
2. 在手机上打开 SideStore，使用首次配置时的同一 Apple 账户登录。在 **My Apps（我的 App）** 中先刷新 SideStore 自身一次，完成初始化。
3. 将下载的 MoviePilot IPA 保存到 iPhone 的“文件”App，在 SideStore 的 **My Apps** 页面导入该文件，等待签名和安装完成。
4. 安装、更新和续签时，连接 **Wi-Fi** 并开启 **LocalDevVPN**；在 iPhone **设置 → 通用 → 后台 App 刷新**中允许 SideStore 刷新。SideStore 会周期性在后台为自己和已安装的 App 续签，日常续签不需要连接电脑。
5. 定期查看 **My Apps** 中的剩余有效天数。自动续签失败时，在到期前点击剩余天数或 **Refresh All（全部刷新）**手动续签。升级 MoviePilot 时，从 Release 下载新版 IPA，使用同一平台和 Apple 账户覆盖安装。

免费账户的签名通常有效 **7 天**，同时激活的 App 一般最多 **3 个（包含 SideStore 自身）**。具体限制、后台刷新和故障处理以 [SideStore 官方 FAQ](https://docs.sidestore.io/docs/faq) 为准。

使用小组件时，请保留 IPA 内的 `MoviePilotWidgets` 扩展，让安装工具同时重签扩展和共享组；不要选择移除扩展。添加与配置见[系统小组件](widgets.md)。

## 其他安装工具

也可使用 [AltStore Classic](https://altstore.io/) 或 [Sideloadly](https://sideloadly.io/) 导入同一个 IPA。AltStore Classic 的日常刷新通常需要可连接的 AltServer；Sideloadly 的自动续签需要电脑上的刷新组件运行。按所选工具的官方指南完成签名、安装和自动刷新设置。

Release 同时提供 `SHA256SUMS`。将它与 IPA 放在同一目录，在 macOS 运行 `shasum -a 256 -c SHA256SUMS`；Windows 可用 `Get-FileHash .\MoviePilot-1.0.1-unsigned.ipa -Algorithm SHA256` 对照校验。

若希望通过 Xcode 安装或修改源码，见 [自行构建与开发](../ios/README.md)。安装后按照[连接说明](connection.md)登录实例。
