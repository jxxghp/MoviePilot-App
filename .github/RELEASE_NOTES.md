MoviePilot iOS 1.0.1，同版本更新；支持 iOS 17+，iOS 26+ 使用系统 Liquid Glass。

### 本次更新

- 新增系统小组件：桌面及今天视图提供小、中、大尺寸，锁屏提供行内、圆形、矩形；每个组件可单独选择服务与内容。
- 下载状态显示下载速度、上传速度和剩余磁盘空间；最小尺寸保留双向速度。数据沿用原账号权限，默认隐藏媒体名称。
- 组件直接读取实例的专用只读摘要，点击进入对应原页面；配合最新 MoviePilot-Frontend **3.2.0** 支持冷启动、重复点击和登录后接续。

### 安装

下载 `MoviePilot-1.0.1-unsigned.ipa`，通过 SideStore、AltStore Classic 或 Sideloadly，使用自己的 Apple 账户重签后覆盖安装。免费签名通常 7 天有效；免费自签的消息通知使用主屏幕 Web Push，默认中心为 `https://movie-pilot.org`。

使用小组件时，请保留并同时重签 `MoviePilotWidgets` 扩展与共享组。

[安装与续签](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/install.md) · [小组件](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/widgets.md) · [通知配置](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/notifications.md) · [界面截图](https://github.com/jxxghp/MoviePilot-App/blob/main/screenshots/README.md)

同时下载 `SHA256SUMS`，在下载目录运行 `shasum -a 256 -c SHA256SUMS` 校验。本包由 GitHub Actions 构建并校验版本、真机平台与 arm64 架构；iPhone 的完整系统集成验收仍在进行。
