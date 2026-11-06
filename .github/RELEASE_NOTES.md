MoviePilot iOS 1.2.1，同版本重新打包，修复插件设置保存后导航中断，并保留启动连接恢复修复。

### 更新内容

- 修复插件设置保存成功后进入“App 导航连接已中断”恢复页的问题；保存进度与配置弹窗快速切换时可正确归还页面，保存失败后也能继续编辑和重试。
- 启动时的初始化检查和登录会话恢复最多等待 15 秒；仍未连通会自动返回服务地址列表并提示，方便从内网地址切换到外网地址。
- 原生登录成功后，如果网页启动时连接中断，也会自动返回地址列表。
- 连接失败保留已保存的服务和登录状态；切换地址后撤销旧请求，避免迟到响应打开旧服务。
- 保留临时故障自动恢复、手动重试和后台暂停检测，密码与验证码不会自动重发。

### 安装

下载 `MoviePilot-1.2.1-unsigned.ipa` 后自行重签。本包没有 Apple 证书签名，不能直接安装；原生推送需要开发者团队为 `com.moviepilot.app` 启用 Push Notifications，并使用带该权限的生产描述文件，同时重签小组件、保留一致的 App Groups。免费账户须在重签时移除 `aps-environment`，继续使用主屏幕网页通知。

如果旧版使用 `org.moviepilot.app`，新版会作为独立 App 安装，需要重新登录及绑定通知；旧 App 和数据不会自动迁移或删除。重签后 Bundle ID 与已有安装一致时才能覆盖更新，原生推送还须与 Server 的 topics 允许名单一致。

MoviePilot 后台启用 AppPush 后，在 App **右上角三点 → 连接与显示 → 通知 → 开启系统通知** 中授权，再发送测试通知。Apple `.p8` 私钥、Team ID 与 Key ID 由 Server 配置，App 无需填写。开发签名须同时将 App 的 APNs 环境改为 `development`，不能仅替换描述文件。

此版本无需为此更新前端；独立搜索仍需 [MoviePilot-Frontend v3.2.4](https://github.com/jxxghp/MoviePilot-Frontend/releases/tag/v3.2.4) 或更新的兼容版本。真实 Apple 投递、后台及锁屏接收需在具有推送权限的签名和真机上验证。

[安装与续签](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/install.md) · [小组件](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/widgets.md) · [通知配置](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/notifications.md)

Release 同时提供 `SHA256SUMS`。本包使用 iPhoneOS SDK 和 arm64 架构构建。
