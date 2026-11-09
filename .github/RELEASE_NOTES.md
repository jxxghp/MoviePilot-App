MoviePilot iOS 1.2.2，修复嵌套弹窗动画、iOS 16–25 底栏材质与原生搜索分类配色问题。

### 更新内容

- 修复 App 嵌套打开弹窗时直接切换内容的问题，补齐进入子弹窗、返回父弹窗和高度变化的动画，并适配系统“减弱动态效果”。
- iOS 16–25 的底栏改用超薄系统磨砂材质，保留底页壁纸和明暗主题变化；iOS 26+ 继续使用系统 Liquid Glass。
- 修复旧系统搜索页分类选中态使用相同强调色绘制背景和前景，导致图标与文字消失的问题。
- 保留 iOS 16 设备的原生底栏布局、动态搜索按钮和路由确认行为。

### 安装

下载 `MoviePilot-1.2.2-unsigned.ipa` 后自行重签。本包没有 Apple 证书签名，不能直接安装；原生推送需要开发者团队为 `com.moviepilot.app` 启用 Push Notifications，并使用带该权限的生产描述文件，同时重签小组件、保留一致的 App Groups。免费账户须在重签时移除 `aps-environment`，继续使用主屏幕网页通知。

如果旧版使用 `org.moviepilot.app`，新版会作为独立 App 安装，需要重新登录及绑定通知；旧 App 和数据不会自动迁移或删除。重签后 Bundle ID 与已有安装一致时才能覆盖更新，原生推送还须与 Server 的 topics 允许名单一致。

MoviePilot 后台启用 AppPush 后，在 App **右上角三点 → 连接与显示 → 通知 → 开启系统通知** 中授权，再发送测试通知。Apple `.p8` 私钥、Team ID 与 Key ID 由 Server 配置，App 无需填写。开发签名须同时将 App 的 APNs 环境改为 `development`，不能仅替换描述文件。

此版本无需为此更新前端；独立搜索仍需 [MoviePilot-Frontend v3.2.4](https://github.com/jxxghp/MoviePilot-Frontend/releases/tag/v3.2.4) 或更新的兼容版本。真实 Apple 投递、后台及锁屏接收需在具有推送权限的签名和真机上验证。

[安装与续签](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/install.md) · [小组件](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/widgets.md) · [通知配置](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/notifications.md)

Release 同时提供 `SHA256SUMS`。本包使用 iPhoneOS SDK 和 arm64 架构构建。
