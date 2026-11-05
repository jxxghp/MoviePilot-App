MoviePilot iOS 1.1.2，默认开启原生 APNs 消息推送。支持 iOS 17+，iOS 26+ 使用系统 Liquid Glass。

### 更新内容

- 主 App 默认使用生产 APNs，通知页提供“开启系统通知”；授权后自动注册设备令牌，并继续复用 MoviePilot 的 AppPush 渠道、消息类型和用户路由。
- 安装包默认 Bundle ID 调整为 `com.moviepilot.app`，小组件为 `com.moviepilot.app.widgets`，与中心服务的允许名单保持一致。
- 未签名 IPA 保留主包的生产推送与共享组元数据，小组件仅保留共享组；发布前检查实际安装包中的 APNs 环境、包名和权限，拒绝不匹配的产物。

### 安装与通知

下载 `MoviePilot-1.1.2-unsigned.ipa` 后自行重签。本包没有 Apple 证书签名，不能直接安装；原生推送需要开发者团队为 `com.moviepilot.app` 启用 Push Notifications，并使用带该权限的生产描述文件，同时重签小组件、保留一致的 App Groups。免费账户须在重签时移除 `aps-environment`，继续使用主屏幕网页通知。

如果旧版使用 `org.moviepilot.app`，新版会作为独立 App 安装，需要重新登录及绑定通知；旧 App 和数据不会自动迁移或删除。重签后 Bundle ID 与已有安装一致时才能覆盖更新，原生推送还须与 Server 的 topics 允许名单一致。

MoviePilot 后台启用 AppPush 后，在 App **右上角三点 → 连接与显示 → 通知 → 开启系统通知** 中授权，再发送测试通知。Apple `.p8` 私钥、Team ID 与 Key ID 由 Server 配置，App 无需填写。开发签名须同时将 App 的 APNs 环境改为 `development`，不能仅替换描述文件。

此版本无需为此更新前端；独立搜索仍需 [MoviePilot-Frontend v3.2.4](https://github.com/jxxghp/MoviePilot-Frontend/releases/tag/v3.2.4) 或更新的兼容版本。真实 Apple 投递、后台及锁屏接收需在具有推送权限的签名和真机上验证。

[安装与续签](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/install.md) · [小组件](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/widgets.md) · [通知配置](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/notifications.md)

Release 同时提供 `SHA256SUMS`。本包使用 iPhoneOS SDK 和 arm64 架构构建。
