MoviePilot iOS，当前为开发预览版，支持 iOS 17+；iOS 26+ 使用系统 Liquid Glass。

### 下载与安装

- 下载本页的 `MoviePilot-版本号-unsigned.ipa`，这是为真实 iPhone/iPad 构建的 arm64 安装包。
- 此 IPA 未签名，可通过 [SideStore](https://sidestore.io/)、AltStore Classic 或 [Sideloadly](https://sideloadly.io/)，用自己的 Apple 账户重签安装；不能下载后直接点安装。
- 免费 Apple 账户通常每 7 天续签一次，不需要付费开发者账号。按 README 完成 SideStore 首次配置，并保持 Wi-Fi、LocalDevVPN 与后台刷新可用以自动续签。
- App 通知服务中心默认内置 `https://movie-pilot.org`，可在通知设置中按实例修改；免费自签的通知使用主屏幕 Web Push。

[安装与使用说明](https://github.com/jxxghp/MoviePilot-App#下载-ipa-并安装) · [全部界面截图](https://github.com/jxxghp/MoviePilot-App/blob/main/screenshots/README.md)

### 校验

同时下载 `SHA256SUMS`，在下载目录运行 `shasum -a 256 -c SHA256SUMS`。本包由 GitHub Actions 构建并校验版本、真机平台与架构；真实 iPhone 的完整验收仍在进行。
