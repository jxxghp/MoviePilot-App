MoviePilot iOS 1.0.1，同版本更新；支持 iOS 17+，iOS 26+ 使用系统 Liquid Glass。

### 本次更新

- 配合 MoviePilot-Frontend **3.2.0**：隔离弹窗外的网页绘制层，修复订阅进度条穿透和嵌套弹窗关闭残留；网页菜单先关闭再打开弹窗。
- 侧滑返回提供跟手卡片转场，支持完成与取消；底栏入口拉开间距，动态按钮显隐时保持按钮间距和聚焦宽度，无动态按钮时居中。
- 修复进入流行趋势后底栏无法切页；通知中心加宽、使用竖版海报，并支持触底连续加载和失败重试。
- 常用入口中的“用户”移至最后并采用系统二级菜单，保留头像、用户信息及红色重启/退出操作；主题与语言相邻，勋章、认证入口同步网页状态。
- 统一玻璃主题，清理旧主题实现；App 和网页均可选择浅色、深色、跟随系统，默认跟随系统。App 固定大圆角，系统半屏主题面板提供明暗与主色；网页保留布局、圆角和材质调节。
- 深色玻璃恢复原蓝灰配色，更多目录跟随皮肤底色；弹窗使用系统默认材质与文字处理，版本历史操作固定在底部。文件详情统一标题和关闭按钮，网页确认使用系统确认框。
- 订阅菜单明确显示“批量操作”，并呈现选择计数；精简首页，安装、连接、通知与截图说明分别提供独立文档。

### 安装

下载 `MoviePilot-1.0.1-unsigned.ipa`，通过 SideStore、AltStore Classic 或 Sideloadly，使用自己的 Apple 账户重签后覆盖安装。免费签名通常 7 天有效；免费自签的消息通知使用主屏幕 Web Push，默认中心为 `https://movie-pilot.org`。

[安装与续签](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/install.md) · [通知配置](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/notifications.md) · [界面截图](https://github.com/jxxghp/MoviePilot-App/blob/main/screenshots/README.md)

同时下载 `SHA256SUMS`，在下载目录运行 `shasum -a 256 -c SHA256SUMS` 校验。本包由 GitHub Actions 构建并校验版本、真机平台与 arm64 架构；iPhone 的完整系统集成验收仍在进行。
