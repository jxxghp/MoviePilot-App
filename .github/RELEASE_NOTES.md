MoviePilot iOS 1.2.4，统一设置与搜索弹窗，修复播放控制并支持 iOS 系统画中画。

### 更新内容

- 主题和语言统一放到“连接与显示”，用户菜单不再重复显示；主题继续沿用当前实例的设置。
- 搜索结果的单项过滤使用半屏弹窗，支持下拉关闭和右上角关闭；综合筛选保留较大的展示空间。
- 媒体库搜索与媒体详情共用选集界面，显示集海报、标题、简介和时长，并统一右上角关闭按钮。
- 修复文件管理等操作菜单在 App 与系统明暗主题不同时出现黑底的问题。
- 视频画面点击只显示或隐藏控制条，播放、暂停和跳转由对应按钮触发；全屏按钮采用系统圆形玻璃样式，快进快退统一为 10 秒。
- 小窗播放改为 iOS 系统画中画，支持桌面悬浮、系统移动与缩放、播放控制及返回原播放进度。

### 安装

下载 `MoviePilot-1.2.4-unsigned.ipa` 后自行重签。本包没有 Apple 证书签名，不能直接安装；原生推送需要开发者团队为 `com.moviepilot.app` 启用 Push Notifications，并使用带该权限的生产描述文件，同时重签小组件、保留一致的 App Groups。免费账户须在重签时移除 `aps-environment`，继续使用主屏幕网页通知。

如果旧版使用 `org.moviepilot.app`，新版会作为独立 App 安装，需要重新登录及绑定通知；旧 App 和数据不会自动迁移或删除。重签后 Bundle ID 与已有安装一致时才能覆盖更新，原生推送还须与 Server 的 topics 允许名单一致。

MoviePilot 后台启用 AppPush 后，在 App **右上角三点 → 连接与显示 → 通知 → 开启系统通知** 中授权，再发送测试通知。Apple `.p8` 私钥、Team ID 与 Key ID 由 Server 配置，App 无需填写。开发签名须同时将 App 的 APNs 环境改为 `development`，不能仅替换描述文件。

搜索弹窗调整需搭配 [MoviePilot-Frontend v3.2.8](https://github.com/jxxghp/MoviePilot-Frontend/releases/tag/v3.2.8)；集海报与标题信息还需要 MoviePilot 后端 v3.2.8。真实 Apple 投递、后台及锁屏接收需在具有推送权限的签名和真机上验证。

[安装与续签](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/install.md) · [小组件](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/widgets.md) · [通知配置](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/notifications.md)

Release 同时提供 `SHA256SUMS`。本包使用 iPhoneOS SDK 和 arm64 架构构建。
