MoviePilot iOS，当前为开发预览版，支持 iOS 17+；iOS 26+ 使用系统 Liquid Glass。

### 本版更新

- 捷径、搜索、消息中心、插件面板和用户菜单改用原生系统面板，避开顶部导航遮挡。
- 页面筛选菜单同样使用原生控件，通知中心保留海报图片。
- 右上角三点菜单区分“常用入口”和“当前页面”，常用入口保持固定顺序，刷新、筛选等页面操作显示名称。
- 用户菜单增加头像、昵称和身份摘要；菜单根据内容适配宽度，简单菜单更紧凑。
- 系统浮层使用原生玻璃材质；业务 HTML 弹窗使用原生 Sheet 的动画、标题和关闭按钮，保留原 Vue 内容。
- 主题设置直接放进用户菜单的分组中，减少一次菜单跳转。
- 普通菜单保留主页背景和底栏，菜单本体使用系统玻璃；Sheet 的材质、外围压暗与转场交由 UIKit 处理，修正勋章关闭按钮及无动态动作时的底栏居中。
- 点击“更多”直接返回完整目录，修复榜单返回，并同步原生菜单的主题颜色。

### 下载与安装

- 下载本页的 `MoviePilot-版本号-unsigned.ipa`，这是为真实 iPhone/iPad 构建的 arm64 安装包。
- 此 IPA 未签名，可通过 [SideStore](https://sidestore.io/)、AltStore Classic 或 [Sideloadly](https://sideloadly.io/)，用自己的 Apple 账户重签安装；不能下载后直接点安装。
- 免费 Apple 账户通常每 7 天续签一次，不需要付费开发者账号。按 README 完成 SideStore 首次配置，并保持 Wi-Fi、LocalDevVPN 与后台刷新可用以自动续签。
- App 通知服务中心默认内置 `https://movie-pilot.org`，可在通知设置中按实例修改；免费自签的通知使用主屏幕 Web Push。

[安装与使用说明](https://github.com/jxxghp/MoviePilot-App#下载-ipa-并安装) · [全部界面截图](https://github.com/jxxghp/MoviePilot-App/blob/main/screenshots/README.md)

### 校验

同时下载 `SHA256SUMS`，在下载目录运行 `shasum -a 256 -c SHA256SUMS`。本包由 GitHub Actions 构建并校验版本、真机平台与架构；真实 iPhone 的完整验收仍在进行。
