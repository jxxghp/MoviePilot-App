MoviePilot iOS 1.0.1，同版本更新；支持 iOS 17+，iOS 26+ 使用系统 Liquid Glass。

### 本次更新

- 配合最新 MoviePilot-Frontend **3.2.0**：处理中使用紧凑的原生进度弹层；媒体识别结果及文件统计统一标题与关闭按钮，Agent 标题动作收到左上角三点菜单。
- 通知中心优先竖版海报，缺少海报时居中裁剪历史图片；正文保留换行与自动折行，继续支持触底加载。
- 修正顶部、筛选及右下角菜单图标；用户二级菜单保留分隔条并显示当前主题，浅色插件卡片及资源标签恢复清晰文字。

### 安装

下载 `MoviePilot-1.0.1-unsigned.ipa`，通过 SideStore、AltStore Classic 或 Sideloadly，使用自己的 Apple 账户重签后覆盖安装。免费签名通常 7 天有效；免费自签的消息通知使用主屏幕 Web Push，默认中心为 `https://movie-pilot.org`。

[安装与续签](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/install.md) · [通知配置](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/notifications.md) · [界面截图](https://github.com/jxxghp/MoviePilot-App/blob/main/screenshots/README.md)

同时下载 `SHA256SUMS`，在下载目录运行 `shasum -a 256 -c SHA256SUMS` 校验。本包由 GitHub Actions 构建并校验版本、真机平台与 arm64 架构；iPhone 的完整系统集成验收仍在进行。
